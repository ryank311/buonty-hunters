// End-to-end check of the live link: starts the `game` MCP server the way the agents do,
// has it launch a hidden game, and uses the tools that need a real window and a real
// process (pictures, restart) on top of the basics. tests/live_regression.gd covers each
// tool's behaviour headlessly; this proves the whole chain.
// Run: tools/dev live smoke   (add --verbose to print every answer)
import { spawn } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const verbose = process.argv.includes("--verbose");

const server = spawn("node", [resolve(here, "live-mcp.mjs"), "smoke"], { stdio: ["pipe", "pipe", "pipe"] });
const pending = new Map();
let buffer = "";
let nextId = 1;
let failures = 0;

server.stderr.on("data", (chunk) => verbose && process.stderr.write(`[server] ${chunk}`));
server.stdout.on("data", (chunk) => {
  buffer += chunk;
  let end;
  while ((end = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, end).trim();
    buffer = buffer.slice(end + 1);
    if (!line) continue;
    const message = JSON.parse(line);
    pending.get(message.id)?.(message);
    pending.delete(message.id);
  }
});

function rpc(method, params, timeoutMs = 120_000) {
  const id = nextId++;
  return new Promise((done, fail) => {
    const timer = setTimeout(() => fail(new Error(`${method} timed out`)), timeoutMs);
    pending.set(id, (message) => {
      clearTimeout(timer);
      done(message);
    });
    server.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
  });
}

// Calls a tool; returns its JSON answer with the pictures and the error flag beside it.
async function call(name, args = {}) {
  const reply = await rpc("tools/call", { name, arguments: args });
  const content = reply.result?.content ?? [];
  const texts = content.filter((part) => part.type === "text").map((part) => part.text);
  if (verbose) console.log(`--- ${name}\n${texts.join("\n").slice(0, 1500)}`);
  let data = {};
  try {
    data = JSON.parse(texts[0] ?? "{}");
  } catch {
    data = { text: texts[0] };
  }
  return { data, texts, images: content.filter((part) => part.type === "image"), failed: Boolean(reply.error || reply.result?.isError) };
}

function check(ok, label, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${!ok && detail ? `\n     ${String(detail).slice(0, 600)}` : ""}`);
  if (!ok) failures += 1;
}

const isPng = (image) => image?.mimeType === "image/png" && Buffer.from(image.data, "base64").subarray(1, 4).toString() === "PNG";

try {
  const init = await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "socom-live-smoke", version: "1" } });
  server.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" })}\n`);
  check(init.result?.serverInfo?.name === "socom-game", `server starts (${init.result?.serverInfo?.name})`);

  const tools = (await rpc("tools/list", {})).result?.tools?.map((tool) => tool.name) ?? [];
  const needed = ["game_status", "game_launch", "game_stop", "state", "telemetry", "tuning_set", "screenshot", "filmstrip", "setup", "play", "reload", "restart"];
  check(needed.every((name) => tools.includes(name)), `tools are offered before any game runs (${tools.length} tools)`, `missing: ${needed.filter((name) => !tools.includes(name))}`);

  const launched = await call("game_launch", { mode: "sandbox" });
  const port = launched.data.launched?.port;
  check(!launched.failed && launched.data.launched?.role === "sandbox" && launched.data.launched?.window === "hidden", `a hidden sandbox game launches (port ${port})`, launched.texts.join("\n"));

  const status = await call("game_status");
  check(status.data.games?.some((game) => game.port === port && game.attached && game.started_by === "you"), "game_status lists it as attached and ours", status.texts.join("\n"));

  const range = await call("setup", { scenario: "lab_range" });
  check(range.data.level === "lab" && range.data.aim?.hit === "Target10", "setup puts the crosshair on the 10 m target", JSON.stringify(range.data.aim));

  const burst = await call("play", { frames: 30, hold: ["fire"] });
  check(burst.data.weapon?.shots >= 4 && burst.data.weapon?.hits >= 1, `play fires a burst (${burst.data.weapon?.shots} shots, ${burst.data.weapon?.hits} hits)`, JSON.stringify(burst.data.weapon));

  const shot = await call("screenshot");
  check(!shot.failed && isPng(shot.images[0]) && existsSync(shot.data.png) && statSync(shot.data.png).size > 10_000, "screenshot returns the player's view inline and on disk", JSON.stringify(shot.data));

  const side = await call("screenshot", { view: "right", distance: 3 });
  const sideBytes = Buffer.from(side.images[0]?.data ?? "", "base64");
  const shotBytes = Buffer.from(shot.images[0]?.data ?? "", "base64");
  check(!side.failed && isPng(side.images[0]) && !sideBytes.equals(shotBytes), "an outside view renders a different picture", JSON.stringify(side.data));

  await call("setup", { scenario: "lab_start" });
  const strip = await call("filmstrip", { frames: 6, every: 5, columns: 3, view: "right", input: { forward: 1 } });
  check(!strip.failed && isPng(strip.images[0]) && strip.data.tick_of_each_frame?.length === 6 && strip.data.player?.pos?.[2] < 25, `filmstrip records a run (${strip.data.tick_of_each_frame})`, JSON.stringify(strip.data));

  await call("setup", { level: "lab", pos: [23, 0.1, 5], look_at: "Targets/Target10", stance: "crouch", class: "breacher", weapon: "secondary" });
  await call("tuning_set", { changes: { "movement.walk_speed": 2.2 } });
  const before = (await call("state")).data;
  const restart = await call("restart");
  const back = restart.texts.map((each) => JSON.parse(each)).find((each) => "restarted" in each);
  const after = (await call("state")).data;
  const walk = (await call("tuning_get", { section: "movement" })).data.movement?.values?.walk_speed;
  const same = (a, b) => Math.abs(a - b) < 0.05;
  check(
    back?.restarted && after.level === "lab" && same(after.player.pos[0], before.player.pos[0]) && same(after.player.pos[2], before.player.pos[2]) && after.player.stance === "crouch" && after.class === "breacher" && after.weapon.slot === 1 && same(walk, 2.2),
    "restart brings the game back on new code with the player, class, weapon, and tuning as they were",
    `${JSON.stringify(restart.texts)} ${JSON.stringify(after.player)} walk=${walk}`,
  );

  const logs = await call("logs", { level: "errors" });
  const ours = (logs.data.lines ?? []).filter((line) => String(line.where).includes("scripts/live/"));
  check(ours.length === 0, "the live link raised no script errors of its own", JSON.stringify(ours.slice(0, 3)));

  const stopped = await call("game_stop");
  const left = await call("game_status");
  check(stopped.data.stopped?.includes(port) && !(left.data.games ?? []).some((game) => game.port === port), "game_stop ends the sandbox", `${stopped.texts.join(" ")} ${left.texts.join(" ").slice(0, 300)}`);
} catch (error) {
  check(false, "smoke run completed", String(error?.stack ?? error));
} finally {
  await call("game_stop").catch(() => {});
  server.stdin.end();
  setTimeout(() => {
    server.kill();
    console.log(failures === 0 ? "LIVE: ok" : `LIVE: FAIL (${failures})`);
    process.exit(failures === 0 ? 0 : 1);
  }, 500);
}
