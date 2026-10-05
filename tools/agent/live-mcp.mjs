#!/usr/bin/env node
// The `game` MCP server: the agents' way into a running game.
//
// The game itself serves MCP over HTTP while it runs (scripts/live/live_server.gd). An
// agent's MCP connection outlives any one game, so this script sits in front of it: it
// stays up, offers the same tools whether or not a game is running, finds the running
// games in .agent/live/, and forwards each call to one of them. It adds four tools of
// its own for choosing, starting, and stopping games.
//
//   live-mcp.mjs [agent-name]             serve MCP over stdio (what the agent configs run)
//   live-mcp.mjs status                   list the running games
//   live-mcp.mjs tools                    list the tools
//   live-mcp.mjs call <tool> ['<json>']   call one tool and print the answer
//   live-mcp.mjs launch [--play]          start a hidden sandbox game (or a visible one)
//   live-mcp.mjs stop [port]              stop games started by `launch`
//   --port=<n> on `call` picks the game when more than one is running, and on `launch`
//   asks for that port. Set SOCOM_LIVE_AGENT to a name of your own when several agents
//   use these commands at once: each then sees and stops only the sandboxes it started.
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
const commands = ["status", "tools", "call", "launch", "stop"];
const command = commands.includes(process.argv[2]) ? process.argv[2] : null;
// Games remember who started them. Each agent's server is its own owner, so one agent
// never stops another's game. The command line keeps one name across invocations:
// "cli", or "cli:<SOCOM_LIVE_AGENT>" so that two agents at their shells stay apart.
const cliName = (process.env.SOCOM_LIVE_AGENT || "").replace(/[^A-Za-z0-9_]/g, "");
const owner = command ? (cliName ? `cli:${cliName}` : "cli") : `${process.argv[2] || "agent"}-${process.pid}`;
const SANDBOX_PORTS = [47210, 47240];
const NO_GAME =
  "No game with the live link is running. The player can start theirs (F5 in the Godot editor, or `tools/dev play`), " +
  "or call game_launch: mode \"sandbox\" is a hidden game for your own tests, mode \"play\" opens a window for the player.";

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
// A sandbox whose owner has gone is nobody's; anyone may use or stop it.
const orphaned = (game) => {
  const pid = Number(String(game.launched_by).split("-").pop());
  return game.launched_by !== "" && !String(game.launched_by).startsWith("cli") && Number.isInteger(pid) && !alive(pid);
};
// What this agent may drive: the player's game, and sandboxes it started (or orphans).
const usable = (game) => game.role === "player" || mine(game) || orphaned(game);

let attached = null;

async function target(port = attached) {
  const running = await games();
  if (port) {
    const chosen = running.find((game) => game.port === port);
    if (chosen) return { game: chosen, several: running.filter(usable).length > 1 };
    if (port !== attached) throw new Problem(`No game is answering on port ${port}. ${describe(running)}`);
    attached = null;
  }
  const offered = running.filter(usable);
  if (offered.length === 1) return { game: offered[0], several: false };
  if (offered.length === 0) throw new Problem(NO_GAME);
  throw new Problem(`More than one game is running; pick one with game_attach (port, or role player/sandbox). ${describe(offered)}`);
}

function summary(game) {
  const minutes = Math.max(0, Math.round((Date.now() / 1000 - game.started) / 60));
  return {
    port: game.port,
    role: game.role,
    level: game.level,
    window: game.hidden ? "hidden" : game.focused ? "visible, focused" : "visible, not focused",
    tuning: game.qa ? "defaults (QA mode)" : "the player's saved settings",
    started_by: mine(game) ? "you" : game.launched_by ? `${game.launched_by}${orphaned(game) ? " (gone)" : ""}` : "a person",
    running_minutes: minutes,
    attached: game.port === attached,
    pid: game.pid,
  };
}

function describe(running) {
  if (running.length === 0) return "Nothing is running.";
  return `Running: ${running.map((game) => `${game.role} on ${game.port}${mine(game) ? " (yours)" : ""}`).join(", ")}.`;
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

async function launch(mode, wanted = 0) {
  const play = mode === "play";
  const port = await freePort(wanted);
  const logs = join(registry, "logs");
  mkdirSync(logs, { recursive: true });
  const output = join(logs, `game-${port}.log`);
  const stream = openSync(output, "w");
  const env = {
    ...process.env,
    // GUI-launched agents may start with a minimal PATH.
    PATH: `${process.env.PATH}:/usr/local/bin:/opt/homebrew/bin`,
    SOCOM_LIVE: "1",
    SOCOM_LIVE_PORT: String(port),
    SOCOM_LIVE_OWNER: owner,
    // "play" runs as the player would: their saved tuning, a window that takes focus.
    SOCOM_AGENT_QA: play ? "0" : "1",
    SOCOM_AGENT_SHOW: play ? "1" : "0",
    // If another agent's Godot MCP session has its bridge autoload in project.godot,
    // this game loads it too; give it a port and token nobody uses.
    MCP_BRIDGE_PORT: String(20000 + Math.floor(Math.random() * 20000)),
    MCP_SESSION_TOKEN: randomBytes(16).toString("hex"),
  };
  delete env.SOCOM_LIVE_RESTORE;
  if (play) {
    delete env.SOCOM_LIVE_HIDDEN;
    delete env.MCP_BACKGROUND;
  } else {
    env.SOCOM_LIVE_HIDDEN = "1";
    env.MCP_BACKGROUND = "1";
  }
  const child = spawn(join(here, "godot"), ["--path", root, "--log-file", join(logs, `godot-${port}.log`)], {
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
    const game = (await games()).find((candidate) => candidate.port === port);
    if (game) return game;
    if (exited !== null) {
      throw new Problem(`The game stopped while starting (${exited}). Its output is in ${output}; \`tools/dev check\` usually names the file at fault.`);
    }
    await sleep(250);
  }
  throw new Problem(`The game did not come up within a minute. Its output is in ${output}.`);
}

async function stop(port) {
  const running = await games();
  const stoppable = running.filter((game) => mine(game) || orphaned(game));
  const chosen = port ? running.filter((game) => game.port === port) : stoppable;
  const stopped = [];
  for (const game of chosen) {
    if (!mine(game) && !orphaned(game)) {
      throw new Problem(
        game.launched_by
          ? `The game on port ${game.port} belongs to ${game.launched_by}; leave it running.`
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

// Stops this server's hidden games when it exits. A game opened for the player stays.
function stopSandboxesNow() {
  for (const entry of registered()) {
    if (entry.launched_by === owner && entry.hidden) {
      try {
        process.kill(entry.pid, "SIGTERM");
      } catch {
        // Already gone.
      }
    }
  }
}

const ownTools = [
  {
    name: "game_status",
    description:
      "Lists the running games that have the live link: the player's own game and any sandbox games, with level, window state, and which one the other tools are talking to. Call this first if a tool says no game is running.",
    inputSchema: { type: "object", properties: {} },
    annotations: { readOnlyHint: true },
  },
  {
    name: "game_launch",
    description:
      "Starts a game and attaches to it. mode \"sandbox\" (default) is hidden, silent, uses default tuning, and never takes the player's focus: use it for your own tests and measurements. mode \"play\" opens a normal window in front for the player, with their saved settings. Not needed when the player already has a game running.",
    inputSchema: { type: "object", properties: { mode: { type: "string", enum: ["sandbox", "play"] } } },
  },
  {
    name: "game_stop",
    description: "Stops games this server started (the one on `port`, or all of them). It never stops a game a person started.",
    inputSchema: { type: "object", properties: { port: { type: "integer" } } },
  },
  {
    name: "game_attach",
    description:
      "Chooses which running game the other tools act on, by port or by role. Needed only when more than one is running, for example the player's game and your sandbox.",
    inputSchema: { type: "object", properties: { port: { type: "integer" }, role: { type: "string", enum: ["player", "sandbox"] } } },
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
    const running = await games();
    const current = running.filter(usable).length === 1 ? running.filter(usable)[0].port : attached;
    return text({
      games: running.map((game) => ({ ...summary(game), attached: game.port === current })),
      ...(running.length === 0 ? { note: NO_GAME } : {}),
    });
  }
  if (name === "game_launch") {
    const game = await launch(args.mode === "play" ? "play" : "sandbox");
    attached = game.port;
    return text({ launched: summary(game), note: "The other tools now act on this game." });
  }
  if (name === "game_stop") {
    const stopped = await stop(args.port ? Number(args.port) : 0);
    return text({ stopped, ...(stopped.length === 0 ? { note: "This server has no game of its own running." } : {}) });
  }
  if (name === "game_attach") {
    const running = await games();
    const matches = running.filter((game) => (args.port ? game.port === Number(args.port) : game.role === args.role && usable(game)));
    if (matches.length !== 1) {
      throw new Problem(`${matches.length === 0 ? "No game matches" : "More than one game matches; give a port"}. ${describe(running)}`);
    }
    attached = matches[0].port;
    return text({ attached: summary(matches[0]) });
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
    const { game, several } = await target(port);
    let reply;
    try {
      reply = await post(game, { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name, arguments: args } }, 15 * 60_000);
    } catch (error) {
      if (error instanceof Problem) throw error;
      throw new Problem(`The game on port ${game.port} stopped answering (${error.cause?.code ?? error.name}); it may have closed or crashed. game_status shows what is running.`);
    }
    if (reply.error) return failure(reply.error.message);
    const result = reply.result;
    if (name === "restart" && !result.isError) result.content.push({ type: "text", text: JSON.stringify(await awaitRestart(game)) });
    // With two games up, say which one answered.
    if (several) result.content.push({ type: "text", text: `[game: ${game.role} on port ${game.port}]` });
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
      if (running.length === 0) console.log("No game with the live link is running. Start one: tools/dev play (or F5 in the Godot editor).");
      for (const game of running) {
        const each = summary(game);
        console.log(`${each.port}  ${each.role.padEnd(8)} ${String(each.level).padEnd(9)} ${each.window.padEnd(22)} started by ${each.started_by}, ${each.running_minutes} min ago  pid ${each.pid}`);
      }
    } else if (command === "tools") {
      for (const tool of [...ownTools, ...gameTools()]) console.log(`${tool.name.padEnd(13)} ${tool.description.split(". ")[0]}.`);
    } else if (command === "launch") {
      const game = await launch(rest.includes("--play") ? "play" : "sandbox", flag("port") ? Number(flag("port")) : 0);
      console.log(`${game.role} game on port ${game.port} (pid ${game.pid})`);
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
      const result = await callTool(words[0], args, flag("port") ? Number(flag("port")) : undefined);
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
            "Inspects and changes the SOCOM game while it runs. state and telemetry read what the player is doing; tuning_set changes feel values at once; " +
            "setup, play, time, set, call and eval act on the game; reload and restart bring in edited code. By default the tools act on the player's own game, " +
            "so on that game read freely but move or freeze things only when the request calls for it. game_launch starts a hidden sandbox for your own tests. " +
            "The live-game skill has the workflow.",
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

process.on("exit", stopSandboxesNow);
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
