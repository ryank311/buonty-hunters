// End-to-end check of the Blender MCP setup: starts the project proxy the way the agents
// do, lets it launch a Blender instance on a port of its own, drives it, and shuts it down.
// Run: tools/dev blender smoke   (add --verbose to print every tool response)
import { spawn, spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../../..");
const port = "9899"; // not an agent's port, so a running modelling session is left alone
const verbose = process.argv.includes("--verbose");

const server = spawn("node", [resolve(here, "../blender-mcp.mjs"), port], { stdio: ["pipe", "pipe", "pipe"] });
const pending = new Map();
let buffer = "";
let nextId = 1;
let failures = 0;
let elicitations = 0;

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
      // The proxy should keep the upstream data-sharing question from ever being asked.
      elicitations += 1;
      send({ jsonrpc: "2.0", id: message.id, result: { action: "decline" } });
    } else if (pending.has(message.id)) {
      pending.get(message.id)(message);
      pending.delete(message.id);
    }
  }
});

function send(message) {
  server.stdin.write(`${JSON.stringify(message)}\n`);
}

function rpc(method, params, timeoutMs = 150_000) {
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
  const reply = await rpc("tools/call", { name, arguments: { user_prompt: "smoke test", ...args } });
  const content = reply.result?.content ?? [];
  const text = content.filter((part) => part.type === "text").map((part) => part.text).join("\n");
  if (verbose) console.log(`--- ${name}\n${text.slice(0, 1500)}`);
  return { text, images: content.filter((part) => part.type === "image"), failed: Boolean(reply.error || reply.result?.isError) };
}

function check(ok, label, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${!ok && detail ? `\n     ${detail.slice(0, 600)}` : ""}`);
  if (!ok) failures += 1;
}

const build = `import bpy, bmesh
mesh = bpy.data.meshes.new("SmokeCube")
cube = bpy.data.objects.new("SmokeCube", mesh)
bpy.context.collection.objects.link(cube)
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1.0)
bm.to_mesh(mesh)
bm.free()
print("dimensions", [round(v, 2) for v in cube.dimensions])
`;

try {
  const init = await rpc("initialize", {
    protocolVersion: "2025-06-18",
    capabilities: { elicitation: {} },
    clientInfo: { name: "socom-blender-smoke", version: "1" },
  });
  send({ jsonrpc: "2.0", method: "notifications/initialized" });
  check(Boolean(init.result?.serverInfo), `server starts (${init.result?.serverInfo?.name})`);

  const tools = (await rpc("tools/list", {})).result?.tools?.map((tool) => tool.name) ?? [];
  const needed = ["get_scene_info", "execute_blender_code", "get_viewport_screenshot", "get_object_info"];
  check(needed.every((name) => tools.includes(name)), `modelling tools offered (${tools.length} tools)`, `missing: ${needed.filter((name) => !tools.includes(name))}`);

  const scene = await call("get_scene_info");
  check(!scene.failed && /object_count/.test(scene.text), "first tool call starts Blender and reaches it", scene.text);

  const built = await call("execute_blender_code", { code: build });
  check(!built.failed && /dimensions \[1\.0, 1\.0, 1\.0\]/.test(built.text), "scripts run inside Blender", built.text);

  const info = await call("get_object_info", { object_name: "SmokeCube" });
  check(/"vertices": 8/.test(info.text), "the new mesh is visible to inspection tools", info.text);

  const shot = await call("get_viewport_screenshot", { max_size: 600 });
  check(shot.images.length === 1 && shot.images[0].data.length > 5000, "viewport screenshot captured", shot.text);

  const blocked = await call("execute_blender_code", { code: "import os\nprint(os.getcwd())" });
  check(/Rejected by safe mode/.test(blocked.text), "safe mode rejects scripts that reach outside Blender", blocked.text);

  check(elicitations === 0, "no data-sharing prompt reaches the agent", `${elicitations} elicitation(s) received`);
} catch (error) {
  check(false, "smoke run completed", String(error));
} finally {
  server.stdin.end();
  const stopped = spawnSync(resolve(root, "tools/dev"), ["blender", "stop", `--port=${port}`, "--discard"], { encoding: "utf8" });
  check(/stopped|No Blender instance/.test(stopped.stdout), "test Blender instance shut down", stopped.stdout + stopped.stderr);
  setTimeout(() => {
    server.kill();
    console.log(failures === 0 ? "BLENDER MCP: ok" : `BLENDER MCP: FAIL (${failures})`);
    process.exit(failures === 0 ? 0 : 1);
  }, 500);
}
