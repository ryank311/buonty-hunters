// End-to-end check of the live link. Two things are proved here that the headless suite
// (tests/live_regression.gd) cannot:
//
//   1. The `game` MCP server acts on the real game and nothing else. With a hidden QA
//      sandbox running, the server must neither list it nor send it a call.
//   2. The tools that need a real window and a real process (pictures, restart) work.
//
// The tools are exercised on a hidden sandbox reached by its port from the command line,
// so the run never touches a game someone is playing and never takes their focus.
// Run: tools/dev live smoke   (add --verbose to print every answer)
import { execFileSync, spawn } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const front = resolve(here, "live-mcp.mjs");
const verbose = process.argv.includes("--verbose");
const env = { ...process.env, SOCOM_LIVE_AGENT: `smoke${process.pid}` };
let failures = 0;

function check(ok, label, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${!ok && detail ? `\n     ${String(detail).slice(0, 600)}` : ""}`);
  if (!ok) failures += 1;
}

// One command-line invocation of the front; returns its lines, parsed where they are JSON.
function cli(...args) {
  let output = "";
  let failed = false;
  try {
    output = execFileSync("node", [front, ...args], { env, encoding: "utf8", timeout: 180_000, stdio: ["ignore", "pipe", "pipe"] });
  } catch (error) {
    output = `${error.stdout ?? ""}${error.stderr ?? ""}`;
    failed = true;
  }
  if (verbose) console.log(`--- ${args.join(" ")}\n${output.slice(0, 1500)}`);
  const lines = output.trim().split("\n");
  const parsed = lines.map((line) => {
    try {
      return JSON.parse(line);
    } catch {
      return null;
    }
  });
  return { text: output, data: parsed[0] ?? {}, all: parsed.filter(Boolean), failed };
}

// The MCP server, started the way the agent configs start it.
const server = spawn("node", [front, "smoke"], { stdio: ["pipe", "pipe", "pipe"] });
const pending = new Map();
let buffer = "";
let nextId = 1;
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

function rpc(method, params, timeoutMs = 60_000) {
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

async function mcp(name, args = {}) {
  const reply = await rpc("tools/call", { name, arguments: args });
  const texts = (reply.result?.content ?? []).filter((part) => part.type === "text").map((part) => part.text);
  if (verbose) console.log(`--- mcp ${name}\n${texts.join("\n").slice(0, 1500)}`);
  let data = {};
  try {
    data = JSON.parse(texts[0] ?? "{}");
  } catch {
    data = { text: texts[0] };
  }
  return { data, failed: Boolean(reply.error || reply.result?.isError) };
}

let port = 0;
try {
  const init = await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "socom-live-smoke", version: "1" } });
  server.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" })}\n`);
  check(init.result?.serverInfo?.name === "socom-game", `the MCP server starts (${init.result?.serverInfo?.name})`);

  const offered = (await rpc("tools/list", {})).result?.tools ?? [];
  const names = offered.map((tool) => tool.name);
  const needed = ["game_status", "game_launch", "game_stop", "state", "telemetry", "tuning_set", "screenshot", "filmstrip", "setup", "play", "reload", "restart"];
  const launch = offered.find((tool) => tool.name === "game_launch");
  check(needed.every((name) => names.includes(name)), `tools are offered whether or not the game runs (${names.length} tools)`, `missing: ${needed.filter((name) => !names.includes(name))}`);
  check(launch && !JSON.stringify(launch.inputSchema).includes("sandbox"), "game_launch has no way to ask for a test instance");

  const started = cli("sandbox");
  port = Number(/port (\d+)/.exec(started.text)?.[1] ?? 0);
  check(!started.failed && port > 0, `a hidden sandbox starts from the command line (port ${port})`, started.text);
  const at = `--port=${port}`;

  // The point of the exercise: the MCP server does not know the sandbox exists.
  const status = await mcp("game_status");
  const listed = status.data.games ?? [];
  check(!listed.some((game) => game.port === port) && listed.every((game) => game.role === "player"), `the MCP server lists only the real game, not the sandbox (${listed.length} listed)`, JSON.stringify(status.data));
  if (listed.length === 0) {
    const reached = await mcp("state");
    check(reached.failed && /not running/.test(reached.data.error ?? ""), "with only a sandbox up, the MCP server says the game is not running", JSON.stringify(reached.data));
  } else {
    console.log("NOTE the real game is running, so the sandbox-only case is not exercised here");
  }
  const bare = cli("call", "state");
  check(listed.length > 0 ? !bare.failed : bare.failed, "from the command line, a call without a port goes to the real game only", bare.text.slice(0, 200));

  const range = cli("call", "setup", JSON.stringify({ scenario: "lab_range" }), at).data;
  check(range.level === "lab" && range.aim?.hit === "Target10", "setup puts the crosshair on the 10 m target", JSON.stringify(range.aim));

  const burst = cli("call", "play", JSON.stringify({ frames: 30, hold: ["fire"] }), at).data;
  check(burst.weapon?.shots >= 2 && burst.weapon?.hits >= 1, `play fires a burst (${burst.weapon?.shots} shots, ${burst.weapon?.hits} hits)`, JSON.stringify(burst.weapon));

  const shot = cli("call", "screenshot", JSON.stringify({ inline: false }), at).data;
  const side = cli("call", "screenshot", JSON.stringify({ view: "right", distance: 3, inline: false }), at).data;
  const size = (file) => (file && existsSync(file) ? statSync(file).size : 0);
  check(size(shot.png) > 10_000 && size(side.png) > 10_000 && shot.png !== side.png, "screenshots of the player's view and an outside view are saved", `${JSON.stringify(shot)} ${JSON.stringify(side)}`);
  const inline = cli("call", "screenshot", "{}", at);
  check(/\(image, image\/png\)/.test(inline.text), "a screenshot also comes back as a picture");

  cli("call", "setup", JSON.stringify({ scenario: "lab_start" }), at);
  const strip = cli("call", "filmstrip", JSON.stringify({ frames: 6, every: 5, columns: 3, view: "right", input: { forward: 1 }, inline: false }), at).data;
  check(size(strip.png) > 10_000 && strip.tick_of_each_frame?.length === 6 && strip.player?.pos?.[2] < 25, `filmstrip records a run (${strip.tick_of_each_frame})`, JSON.stringify(strip));

  cli("call", "setup", JSON.stringify({ level: "lab", pos: [23, 0.1, 5], look_at: "Targets/Target10", stance: "crouch", class: "breacher", weapon: "secondary" }), at);
  cli("call", "tuning_set", JSON.stringify({ changes: { "movement.walk_speed": 2.2 } }), at);
  const before = cli("call", "state", "{}", at).data;
  const restart = cli("call", "restart", "{}", at);
  const back = restart.all.find((each) => "restarted" in each);
  const after = cli("call", "state", "{}", at).data;
  const walk = cli("call", "tuning_get", JSON.stringify({ section: "movement" }), at).data.movement?.values?.walk_speed;
  const same = (a, b) => Math.abs(a - b) < 0.05;
  check(
    back?.restarted && after.level === "lab" && same(after.player.pos[0], before.player.pos[0]) && same(after.player.pos[2], before.player.pos[2]) && after.player.stance === "crouch" && after.class === "breacher" && after.weapon.slot === 1 && same(walk, 2.2),
    "restart brings the instance back on new code with the player, class, weapon, and tuning as they were",
    `${restart.text.slice(0, 300)} ${JSON.stringify(after.player)} walk=${walk}`,
  );

  const logs = cli("call", "logs", JSON.stringify({ level: "errors" }), at).data;
  const ours = (logs.lines ?? []).filter((line) => String(line.where).includes("scripts/live/"));
  check(ours.length === 0, "the live link raised no script errors of its own", JSON.stringify(ours.slice(0, 3)));
} catch (error) {
  check(false, "smoke run completed", String(error?.stack ?? error));
} finally {
  if (port) {
    const stopped = cli("stop", String(port));
    check(/stopped/.test(stopped.text), "the sandbox stops", stopped.text);
  }
  server.stdin.end();
  setTimeout(() => {
    server.kill();
    console.log(failures === 0 ? "LIVE: ok" : `LIVE: FAIL (${failures})`);
    process.exit(failures === 0 ? 0 : 1);
  }, 300);
}
