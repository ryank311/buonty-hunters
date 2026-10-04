#!/usr/bin/env node
// Starts the Blender MCP server (mcp-for-blender) for this project over stdio.
// Usage: blender-mcp.mjs <port>
//
// Both agent configs run this script, each with its own port, so Claude Code and Codex
// each drive a separate Blender instance and never share a scene. It sits between the
// agent and the upstream server for two reasons:
//
//   1. Blender is started on demand. The first tool call launches the agents' Blender
//      (tools/dev blender start) if nothing is listening on the port, so a session that
//      never models anything never opens Blender.
//   2. The upstream server asks, through an MCP elicitation, whether to share session
//      data with its author. An agent must not answer that for the user, so the
//      elicitation capability is withheld and the question is never raised. Telemetry
//      is also switched off outright below; remove DISABLE_TELEMETRY to change that.
import { spawn, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createConnection } from "node:net";
import { dirname, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const port = Number(process.argv[2] || process.env.SOCOM_BLENDER_PORT || 9886);
const version = readFileSync(resolve(here, "blender/mcp-version"), "utf8").trim();

const env = {
  ...process.env,
  // GUI-launched agents may start with a minimal PATH; make sure uvx resolves.
  PATH: `${process.env.PATH}:${process.env.HOME}/.local/bin:/usr/local/bin:/opt/homebrew/bin`,
  DISABLE_TELEMETRY: "true",
  // Scripts may use bpy, bmesh, mathutils, and pure-Python modules, and may save, render,
  // import, and export. No os/subprocess/network access. SOCOM_BLENDER_UNSAFE=1 lifts this.
  BLENDER_MCP_SAFE_MODE: process.env.SOCOM_BLENDER_UNSAFE === "1" ? "0" : "1",
};

const server = spawn("uvx", ["--python", "3.11", `mcp-for-blender@${version}`, "--port", String(port)], {
  env,
  stdio: ["pipe", "inherit", "inherit"],
});
server.on("error", (error) => {
  process.stderr.write(`blender-mcp: could not start uvx (${error.message}). Install uv: https://docs.astral.sh/uv/\n`);
  process.exit(1);
});
server.on("exit", (code) => process.exit(code ?? 0));

function listening() {
  return new Promise((done) => {
    const socket = createConnection({ host: "127.0.0.1", port });
    socket.setTimeout(400);
    socket.once("connect", () => { socket.destroy(); done(true); });
    socket.once("timeout", () => { socket.destroy(); done(false); });
    socket.once("error", () => done(false));
  });
}

async function ensureBlender() {
  if (await listening()) return;
  const started = spawnSync(resolve(root, "tools/dev"), ["blender", "start", `--port=${port}`], { env, encoding: "utf8" });
  process.stderr.write(`blender-mcp: ${(started.stdout || started.stderr || "").trim()}\n`);
}

// Messages are forwarded strictly in order, so a tool call waits for Blender to be up.
const lines = createInterface({ input: process.stdin });
for await (const line of lines) {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    server.stdin.write(`${line}\n`);
    continue;
  }
  if (message.method === "initialize" && message.params?.capabilities?.elicitation) {
    delete message.params.capabilities.elicitation;
  } else if (message.method === "tools/call") {
    await ensureBlender();
  }
  server.stdin.write(`${JSON.stringify(message)}\n`);
}
server.stdin.end();
