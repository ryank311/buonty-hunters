#!/usr/bin/env node
// The `game` MCP server: the agents' way into the running game.
//
// The game itself serves MCP over HTTP while it runs (scripts/live/live_server.gd). An
// agent's MCP connection outlives any one game, so this script sits in front of it: it
// stays up, offers the same tools whether or not the game is running, finds the game in
// .agent/live/, and forwards each call to it. It adds four tools of its own for seeing,
// starting, and stopping the game.
//
// It only ever acts on the real game: the one in a window, run as a player runs it. A
// hidden QA sandbox is a separate thing an agent starts on purpose from the command line
// for an experiment of its own, and reaches only by naming its port. The MCP server never
// lists, starts, or attaches to one, so an agent asked to change the game changes the game.
//
//   live-mcp.mjs [agent-name]             serve MCP over stdio (what the agent configs run)
//   live-mcp.mjs status                   list what is running
//   live-mcp.mjs tools                    list the tools
//   live-mcp.mjs call <tool> ['<json>']   call one tool on the real game and print the answer
//   live-mcp.mjs launch [--focus]         open the real game (in front, with --focus)
//   live-mcp.mjs sandbox [--port=<n>]     start a hidden QA sandbox for your own experiment
//   live-mcp.mjs stop [port]              stop games these commands started
//   --port=<n> on `call` names a sandbox. Set SOCOM_LIVE_AGENT to a name of your own when
//   several agents use these commands at once: each then stops only what it started.
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdirSync, openSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { createServer } from "node:net";
import { dirname, join, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const registry = join(root, ".agent/live");
const manifestPath = join(root, "scripts/live/tools.json");
const commands = ["status", "tools", "call", "launch", "sandbox", "stop"];
const command = commands.includes(process.argv[2]) ? process.argv[2] : null;
// Games remember who started them. Each agent's server is its own owner, so one agent
// never stops another's game. The command line keeps one name across invocations:
// "cli", or "cli:<SOCOM_LIVE_AGENT>" so that two agents at their shells stay apart.
const cliName = (process.env.SOCOM_LIVE_AGENT || "").replace(/[^A-Za-z0-9_]/g, "");
const owner = command ? (cliName ? `cli:${cliName}` : "cli") : `${process.argv[2] || "agent"}-${process.pid}`;
const SANDBOX_PORTS = [47210, 47240];
const NO_GAME =
  "The game is not running. The player can start it (F5 in the Godot editor, or `tools/dev play`), or game_launch opens it. " +
  "These tools act only on the real game, never on a test instance.";

class Problem extends Error {}

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

function alive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
}

async function health(port) {
  try {
    const reply = await fetch(`http://127.0.0.1:${port}/health`, { signal: AbortSignal.timeout(1500) });
    return reply.ok ? await reply.json() : null;
  } catch {
    return null;
  }
}

function registered() {
  let files = [];
  try {
    files = readdirSync(registry).filter((file) => /^\d+\.json$/.test(file));
  } catch {
    return [];
  }
  const entries = [];
  for (const file of files) {
    try {
      const entry = JSON.parse(readFileSync(join(registry, file), "utf8"));
      // A game that was killed leaves its entry behind.
      if (alive(entry.pid)) entries.push(entry);
      else rmSync(join(registry, file), { force: true });
    } catch {
      // Half-written by a game that is starting; it will be whole on the next look.
    }
  }
  return entries;
}

// Every game that is up and answering, lowest port first.
async function games() {
  const found = [];
  for (const entry of registered()) {
    const now = await health(entry.port);
    if (now && now.pid === entry.pid) found.push({ ...entry, ...now });
  }
  return found.sort((a, b) => a.port - b.port);
}

const mine = (game) => game.launched_by === owner;
// The real game: a window, run as a player runs it. Everything else is a sandbox.
const real = (game) => game.role === "player";

let attached = null;

// The game a call goes to. Without a port that is the real game and nothing else; a
// sandbox is reached only from the command line, by its port.
async function target(port = 0) {
  const running = await games();
  if (port) {
    const chosen = running.find((game) => game.port === port);
    if (chosen) return { game: chosen, several: false };
    throw new Problem(`Nothing is answering on port ${port}. ${describe(running)}`);
  }
  const offered = running.filter(real);
  if (offered.length === 0) throw new Problem(NO_GAME);
  if (offered.length === 1) return { game: offered[0], several: false };
  const chosen = offered.find((game) => game.port === attached);
  if (chosen) return { game: chosen, several: true };
  throw new Problem(`The game is running more than once; pick one with game_attach. ${describe(offered)}`);
}

function summary(game) {
  const minutes = Math.max(0, Math.round((Date.now() / 1000 - game.started) / 60));
  return {
    port: game.port,
    role: game.role,
    level: game.level,
    window: game.hidden ? "hidden" : game.focused ? "visible, focused" : "visible, not focused",
    tuning: game.qa ? "defaults (QA mode)" : "the player's saved settings",
    started_by: mine(game) ? "you" : game.launched_by || "a person",
    running_minutes: minutes,
    pid: game.pid,
  };
}

function describe(running) {
  if (running.length === 0) return "Nothing is running.";
  return `Running: ${running.map((game) => `${real(game) ? "the game" : "a sandbox"} on ${game.port}${mine(game) ? " (yours)" : ""}`).join(", ")}.`;
}

async function post(game, message, timeoutMs) {
  const reply = await fetch(`http://127.0.0.1:${game.port}/mcp`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json", Authorization: `Bearer ${game.token}` },
    body: JSON.stringify(message),
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!reply.ok) throw new Problem(`The game refused the request (HTTP ${reply.status}).`);
  return await reply.json();
}

function freePort(wanted = 0) {
  const tryPort = (port) =>
    new Promise((done) => {
      const probe = createServer();
      probe.once("error", () => done(false));
      probe.listen(port, "127.0.0.1", () => probe.close(() => done(true)));
    });
  return (async () => {
    const taken = new Set(registered().map((entry) => entry.port));
    if (wanted) {
      if (!taken.has(wanted) && (await tryPort(wanted))) return wanted;
      throw new Problem(`Port ${wanted} is in use.`);
    }
    for (let port = SANDBOX_PORTS[0]; port < SANDBOX_PORTS[1]; port += 1) {
      if (!taken.has(port) && (await tryPort(port))) return port;
    }
    throw new Problem(`No free port between ${SANDBOX_PORTS[0]} and ${SANDBOX_PORTS[1]}; stop a game first.`);
  })();
}

// Opens the real game in a window as a player would run it, or with `sandbox` starts a
// hidden QA instance on a port of its own.
async function launch({ sandbox = false, focus = false, wanted = 0 } = {}) {
  const logs = join(registry, "logs");
  mkdirSync(logs, { recursive: true });
  const port = sandbox ? await freePort(wanted) : 0;
  const stamp = sandbox ? String(port) : `game-${Date.now()}`;
  const output = join(logs, `${stamp}.log`);
  const stream = openSync(output, "w");
  const env = {
    ...process.env,
    // GUI-launched agents may start with a minimal PATH.
    PATH: `${process.env.PATH}:/usr/local/bin:/opt/homebrew/bin`,
    SOCOM_LIVE_OWNER: owner,
  };
  delete env.SOCOM_LIVE_RESTORE;
  delete env.SOCOM_LIVE_PORT;
  delete env.SOCOM_LIVE_HIDDEN;
  delete env.MCP_BACKGROUND;
  if (sandbox) {
    Object.assign(env, {
      SOCOM_LIVE: "1",
      SOCOM_LIVE_PORT: String(port),
      SOCOM_LIVE_HIDDEN: "1",
      SOCOM_AGENT_QA: "1",
      SOCOM_AGENT_SHOW: "0",
      MCP_BACKGROUND: "1",
      // If another agent's Godot MCP session has its bridge autoload in project.godot,
      // this instance loads it too; give it a port and token nobody uses.
      MCP_BRIDGE_PORT: String(20000 + Math.floor(Math.random() * 20000)),
      MCP_SESSION_TOKEN: randomBytes(16).toString("hex"),
    });
  } else {
    // The game as the player runs it: their saved settings, a real window. Unless asked
    // to come to the front, the launcher hands keyboard focus back to what they were in.
    Object.assign(env, { SOCOM_AGENT_QA: "0", SOCOM_AGENT_SHOW: focus ? "1" : "0" });
    delete env.SOCOM_LIVE;
  }
  const child = spawn(join(here, "godot"), ["--path", root, "--log-file", join(logs, `godot-${stamp}.log`)], {
    env,
    detached: true,
    stdio: ["ignore", stream, stream],
  });
  child.unref();
  let exited = null;
  child.once("exit", (code) => (exited = code ?? 1));
  child.once("error", (error) => (exited = error.message));
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    const game = (await games()).find((candidate) => candidate.pid === child.pid);
    if (game) return game;
    if (exited !== null) {
      throw new Problem(`The game stopped while starting (${exited}). Its output is in ${output}; \`tools/dev check\` usually names the file at fault.`);
    }
    await sleep(250);
  }
  throw new Problem(`The game did not come up within a minute. Its output is in ${output}.`);
}

// Stops games this owner started: the one on `port`, or all of them.
async function stop(port) {
  const running = await games();
  const chosen = port ? running.filter((game) => game.port === port) : running.filter(mine);
  const stopped = [];
  for (const game of chosen) {
    if (!mine(game)) {
      throw new Problem(
        game.launched_by
          ? `What is on port ${game.port} belongs to ${game.launched_by}; leave it running.`
          : `The game on port ${game.port} was started by a person. Ask them to close it.`,
      );
    }
    process.kill(game.pid, "SIGTERM");
    stopped.push(game.port);
    if (attached === game.port) attached = null;
  }
  for (let waited = 0; waited < 40 && stopped.some((each) => registered().some((entry) => entry.port === each)); waited += 1) {
    await sleep(100);
  }
  return stopped;
}

const ownTools = [
  {
    name: "game_status",
    description:
      "Whether the game is running, with its level and whether its window has focus. Call this first if a tool says the game is not running. Only the real game is ever listed here: the tools of this server cannot reach a test instance.",
    inputSchema: { type: "object", properties: {} },
    annotations: { readOnlyHint: true },
  },
  {
    name: "game_launch",
    description:
      "Opens the real game in a window, as the player runs it, with their saved settings. Use it when the game is not running. By default the window does not take keyboard focus from what the player is doing; pass focus true when they have asked to play now.",
    inputSchema: { type: "object", properties: { focus: { type: "boolean" } } },
  },
  {
    name: "game_stop",
    description: "Closes a game this server opened with game_launch. It never closes a game a person started.",
    inputSchema: { type: "object", properties: { port: { type: "integer" } } },
  },
  {
    name: "game_attach",
    description: "Chooses between copies of the game by port. Needed only if the game is running more than once.",
    inputSchema: { type: "object", properties: { port: { type: "integer" } }, required: ["port"] },
  },
];

function gameTools() {
  try {
    return JSON.parse(readFileSync(manifestPath, "utf8")).tools;
  } catch (error) {
    process.stderr.write(`live-mcp: cannot read ${manifestPath}: ${error.message}\n`);
    return [];
  }
}

const text = (value) => ({ content: [{ type: "text", text: typeof value === "string" ? value : JSON.stringify(value) }] });
const failure = (message) => ({ content: [{ type: "text", text: JSON.stringify({ error: message }) }], isError: true });

async function callOwn(name, args) {
  if (name === "game_status") {
    const running = (await games()).filter(real);
    return text({ games: running.map(summary), ...(running.length === 0 ? { note: NO_GAME } : {}) });
  }
  if (name === "game_launch") {
    const already = (await games()).filter(real);
    if (already.length > 0) return text({ already_running: already.map(summary), note: "The game is already open; the tools act on it." });
    const game = await launch({ focus: Boolean(args.focus) });
    return text({ launched: summary(game) });
  }
  if (name === "game_stop") {
    const stopped = await stop(args.port ? Number(args.port) : 0);
    return text({ stopped, ...(stopped.length === 0 ? { note: "This server has not opened a game." } : {}) });
  }
  if (name === "game_attach") {
    const match = (await games()).filter(real).find((game) => game.port === Number(args.port));
    if (!match) throw new Problem(`The game is not running on port ${args.port}. ${describe((await games()).filter(real))}`);
    attached = match.port;
    return text({ attached: summary(match) });
  }
  return null;
}

// After `restart` the game comes back as a new process on the same port; wait for it
// and for the player to be put back before answering.
async function awaitRestart(before) {
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    await sleep(300);
    const game = (await games()).find((candidate) => candidate.port === before.port && candidate.pid !== before.pid);
    if (game && !game.restoring) return { restarted: true, pid: game.pid };
  }
  return { restarted: false, note: "The game has not come back yet; game_status shows when it does." };
}

async function callTool(name, args = {}, port = undefined) {
  try {
    const own = await callOwn(name, args);
    if (own) return own;
    const { game, several } = await target(port ?? 0);
    let reply;
    try {
      reply = await post(game, { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name, arguments: args } }, 15 * 60_000);
    } catch (error) {
      if (error instanceof Problem) throw error;
      throw new Problem(`The game on port ${game.port} stopped answering (${error.cause?.code ?? error.name}); it may have closed or crashed. game_status shows whether it is running.`);
    }
    if (reply.error) return failure(reply.error.message);
    const result = reply.result;
    if (name === "restart" && !result.isError) result.content.push({ type: "text", text: JSON.stringify(await awaitRestart(game)) });
    // With the game open twice, say which copy answered.
    if (several) result.content.push({ type: "text", text: `[the game on port ${game.port}]` });
    return result;
  } catch (error) {
    if (error instanceof Problem) return failure(error.message);
    throw error;
  }
}

// ---- Command line ----

if (command) {
  const rest = process.argv.slice(3);
  const flag = (name) => rest.find((arg) => arg.startsWith(`--${name}=`))?.split("=")[1];
  const words = rest.filter((arg) => !arg.startsWith("--"));
  let failed = false;
  try {
    if (command === "status") {
      const running = await games();
      if (!running.some(real)) console.log("The game is not running. Start it: tools/dev play (or F5 in the Godot editor).");
      for (const game of running) {
        const each = summary(game);
        const what = real(game) ? "the game" : "sandbox ";
        console.log(`${each.port}  ${what}  ${String(each.level).padEnd(9)} ${each.window.padEnd(22)} started by ${each.started_by}, ${each.running_minutes} min ago  pid ${each.pid}`);
      }
    } else if (command === "tools") {
      for (const tool of [...ownTools, ...gameTools()]) console.log(`${tool.name.padEnd(13)} ${tool.description.split(". ")[0]}.`);
    } else if (command === "launch") {
      const game = await launch({ focus: rest.includes("--focus") });
      console.log(`the game is open on port ${game.port} (pid ${game.pid})`);
    } else if (command === "sandbox") {
      const game = await launch({ sandbox: true, wanted: flag("port") ? Number(flag("port")) : 0 });
      console.log(`sandbox on port ${game.port} (pid ${game.pid}); reach it with: call <tool> --port=${game.port}`);
    } else if (command === "stop") {
      const stopped = await stop(words[0] ? Number(words[0]) : 0);
      console.log(stopped.length ? `stopped ${stopped.join(", ")}` : "nothing to stop");
    } else if (command === "call") {
      if (!words[0]) throw new Problem("usage: live-mcp.mjs call <tool> ['<json arguments>'] [--port=<n>]");
      let args = {};
      try {
        args = words[1] ? JSON.parse(words[1]) : {};
      } catch (error) {
        throw new Problem(`The arguments are not JSON: ${error.message}`);
      }
      const result = await callTool(words[0], args, flag("port") ? Number(flag("port")) : 0);
      for (const part of result.content) console.log(part.type === "text" ? part.text : `(${part.type}, ${part.mimeType})`);
      failed = Boolean(result.isError);
    }
  } catch (error) {
    console.error(error instanceof Problem ? error.message : error);
    failed = true;
  }
  process.exit(failed ? 1 : 0);
}

// ---- MCP over stdio ----

const send = (message) => process.stdout.write(`${JSON.stringify(message)}\n`);

async function handle(message) {
  const { id, method, params } = message;
  if (id === undefined || id === null) return;
  try {
    if (method === "initialize") {
      send({
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: typeof params?.protocolVersion === "string" ? params.protocolVersion : "2025-06-18",
          capabilities: { tools: {} },
          serverInfo: { name: "socom-game", title: "SOCOM live game", version: "1.0.0" },
          instructions:
            "Inspects and changes the SOCOM game while it runs. Every tool acts on the real game, the one the player has open: there is no test instance behind this server. " +
            "state and telemetry read what the player is doing; tuning_set changes feel values at once; setup, play, time, set, call and eval act on the game; " +
            "reload and restart bring in edited code. Read freely, but move, freeze, or restart the player's game only when the request calls for it. " +
            "game_launch opens the game if it is not running. The live-game skill has the workflow.",
        },
      });
    } else if (method === "ping") {
      send({ jsonrpc: "2.0", id, result: {} });
    } else if (method === "tools/list") {
      send({ jsonrpc: "2.0", id, result: { tools: [...ownTools, ...gameTools()] } });
    } else if (method === "tools/call") {
      send({ jsonrpc: "2.0", id, result: await callTool(String(params?.name ?? ""), params?.arguments ?? {}) });
    } else {
      send({ jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } });
    }
  } catch (error) {
    send({ jsonrpc: "2.0", id, error: { code: -32603, message: String(error?.message ?? error) } });
  }
}

for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) process.on(signal, () => process.exit(0));

const lines = createInterface({ input: process.stdin });
lines.on("line", (line) => {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return;
  }
  // Calls run side by side here; the game itself takes them one at a time.
  handle(message);
});
lines.on("close", () => process.exit(0));
