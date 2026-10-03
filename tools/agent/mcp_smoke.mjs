// End-to-end check of the Godot MCP setup: starts the server the same way the agents
// do, launches the game hidden, drives it, and confirms each link works.
// Run: tools/dev mcp-smoke   (add --verbose to print every tool response)
import { spawn } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const project = resolve(here, "../..");
const verbose = process.argv.includes("--verbose");

const server = spawn(resolve(here, "mcp"), [], { stdio: ["pipe", "pipe", "pipe"] });
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
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      continue;
    }
    if (message.method === "elicitation/create") {
      // The server asks before launching a project; this is our own project.
      send({ jsonrpc: "2.0", id: message.id, result: { action: "accept", content: {} } });
    } else if (pending.has(message.id)) {
      pending.get(message.id)(message);
      pending.delete(message.id);
    }
  }
});

function send(message) {
  server.stdin.write(`${JSON.stringify(message)}\n`);
}

function rpc(method, params, timeoutMs = 120_000) {
  const id = nextId++;
  return new Promise((done, fail) => {
    const timer = setTimeout(() => fail(new Error(`${method} timed out`)), timeoutMs);
    pending.set(id, (message) => {
      clearTimeout(timer);
      done(message);
    });
    send({ jsonrpc: "2.0", id, method, params });
  });
}

async function call(name, args = {}) {
  const reply = await rpc("tools/call", { name, arguments: args });
  const text = (reply.result?.content ?? []).filter((part) => part.type === "text").map((part) => part.text).join("\n");
  if (verbose) console.log(`--- ${name}\n${text.slice(0, 2000)}`);
  return { text, failed: Boolean(reply.error || reply.result?.isError) };
}

function check(ok, label, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${!ok && detail ? `\n     ${detail.slice(0, 600)}` : ""}`);
  if (!ok) failures += 1;
}

function parse(text) {
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

const harness = (body) =>
  `extends RefCounted\nconst H = preload("res://tools/agent/harness.gd")\nfunc execute(scene_tree: SceneTree) -> Variant:\n\t${body}`;

try {
  const init = await rpc("initialize", {
    protocolVersion: "2025-06-18",
    capabilities: { elicitation: {} },
    clientInfo: { name: "socom-mcp-smoke", version: "1" },
  });
  send({ jsonrpc: "2.0", method: "notifications/initialized" });
  check(Boolean(init.result?.serverInfo), `server starts (${init.result?.serverInfo?.name} ${init.result?.serverInfo?.version})`);

  const tools = (await rpc("tools/list", {})).result?.tools?.map((tool) => tool.name) ?? [];
  const needed = ["run_project", "stop_project", "take_screenshot", "simulate_input", "run_script", "get_debug_output", "validate"];
  check(needed.every((name) => tools.includes(name)), `runtime tools offered (${tools.length} tools)`, `missing: ${needed.filter((name) => !tools.includes(name))}`);

  const info = await call("check_project", { projectPath: project });
  check(!info.failed && /godotVersion/.test(info.text), `project recognised (Godot ${parse(info.text).godotVersion ?? "?"})`, info.text);

  const run = await call("run_project", { projectPath: project, background: true });
  check(!run.failed && /bridge is ready/i.test(run.text), "game launches hidden with the runtime bridge", run.text);

  const scenario = parse((await call("run_script", { script: harness('return await H.scenario(scene_tree, "lab_range")') })).text).result ?? {};
  check(scenario.level === "lab" && scenario.aim?.hit === "Target10", "harness scenario lab_range aims at Target10", JSON.stringify(scenario));

  const mode = parse((await call("run_script", { script: harness("return H.session(scene_tree).qa_mode") })).text);
  check(mode.result === true, "agent-launched game runs in QA mode", JSON.stringify(mode));

  const fire = await call("simulate_input", { actions: [{ type: "action", action: "fire", hold_ms: 400 }, { type: "wait", frames: 6 }] });
  const after = parse((await call("run_script", { script: harness("return H.state(scene_tree)") })).text).result ?? {};
  check(!fire.failed && after.weapon?.shots > 0 && after.weapon?.hits > 0, `simulated fire input shoots the target (${after.weapon?.shots} shots, ${after.weapon?.hits} hits)`, fire.text);

  const walk = parse((await call("run_script", { script: harness('return await H.step(scene_tree, 60, {"forward": 1.0})') })).text).result ?? {};
  const moved = Math.hypot((walk.player?.pos?.[0] ?? 23) - 23, (walk.player?.pos?.[2] ?? 5) - 5);
  check(moved > 3.5 && moved < 4.5, `harness step walks one second forward (${moved.toFixed(2)} m)`, JSON.stringify(walk.player));

  const shot = parse((await call("take_screenshot", { responseMode: "path_only" })).text);
  check(Boolean(shot.path) && existsSync(shot.path) && statSync(shot.path).size > 10_000, "screenshot captured", JSON.stringify(shot));

  const output = await call("get_debug_output");
  const errors = (parse(output.text).errors ?? []).filter((line) => /SCRIPT ERROR|^ERROR/.test(line));
  check(errors.length === 0, "no script errors while driving the game", errors.slice(0, 4).join("\n     "));
} catch (error) {
  check(false, "smoke run completed", String(error));
} finally {
  await call("stop_project").catch(() => {});
  server.stdin.end();
  setTimeout(() => {
    server.kill();
    console.log(failures === 0 ? "MCP: ok" : `MCP: FAIL (${failures})`);
    process.exit(failures === 0 ? 0 : 1);
  }, 500);
}
