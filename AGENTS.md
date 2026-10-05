# SOCOM prototype: agent guide

A third-person tactical shooter prototype in Godot 4.7: GDScript, Jolt physics, Mobile renderer. The game starts from `scenes/main.tscn`. `README.md` describes what exists and how it plays; `docs/` holds the design, research, and playtest notes.

## Layout

| Path | Contents |
|---|---|
| `scripts/` | Gameplay code: `player/`, `combat/` (weapons, bullets, grenades, claymores, elimination and spectating, level rosters), `actors/` (stand-in soldiers), `levels/` (session and level switching), `ui/`, `resources/` (tuning profile and class definitions), `live/` (the live link: the MCP server inside the running game) |
| `scenes/` | `main.tscn`, `actors/player.tscn`, `actors/combat_dummy.tscn`, `levels/old_quarter.tscn`, `levels/movement_lab.tscn` |
| `resources/` | Default tuning values (`.tres`) for movement, camera, and each weapon and piece of equipment (`weapons/`); what each soldier class carries (`classes/`) |
| `art/` | `blender/` holds model sources (`.blend`, hidden from Godot); `models/` holds the exported `.glb` files the game loads; `decals/` |
| `tests/` | Headless regression suites, one `SceneTree` script each |
| `tools/dev` | The single command for checking, testing, and capturing the game, and for the Blender asset pipeline |
| `tools/agent/` | What `tools/dev` and the MCP servers run: Godot wrapper, MCP launchers, the live link's front (`live-mcp.mjs`), scenario harness, capture and check scripts, Blender export and preview scripts |
| `.agents/skills/` | Skills for this project (`.claude/skills` links here) |

## Asset recovery work

Read [docs/ASSET_RECOVERY_HANDOFF.md](docs/ASSET_RECOVERY_HANDOFF.md) before importing recovered weapons, props, levels or motions. Recovered characters are now the gameplay models; preserve their native proportions, weights and rigs. Do not restore the retired 19-bone player retarget. The handoff links the extraction manifests, Blender recipes, native animation calibration, known limits and checks.

## Verify every change

1. `tools/dev check`: every script, scene, and resource loads (about 1 s).
2. `tools/dev test`: the regression suites pass (about 25 s; name suites to run fewer).
3. If the change can be seen or felt, look at it: `tools/dev shot <scenario>` for a frame, the `godot` MCP server to play it, or the `game` MCP server to see it in a game that is already running.

Say what you ran and what it showed. A change that was not checked is not done.

## Skills

- `godot-dev-loop`: the check, test, look loop with `tools/dev`, the Godot pitfalls that cost time here, and how to write a regression suite.
- `godot-playtest`: driving the running game through the `godot` MCP server and the scenario harness: any level, spawn, stance, weapon, or menu state; tick-exact input; state digests; screenshots.
- `live-game`: working on the game while it runs and is played, through the `game` MCP server: what the player just did in numbers, live tuning of feel, pictures and filmstrips from any angle, slow motion, editing any variable, hot-reloading edited scripts, restarting in place.
- `blender-modeling`: building models and level objects through the `blender` MCP server, then exporting, previewing, and placing them in the game with `tools/dev blender`.

## MCP

Three servers are registered for Claude Code in `.mcp.json` and for Codex in `.codex/config.toml`:

- `godot` (godot-mcp-runtime) runs `tools/agent/mcp`, which pins the server version and points it at the Godot wrapper. `tools/dev mcp-smoke` tests it end to end.
- `game` is the live link. The real game serves MCP itself while it runs (the `Live` autoload, `scripts/live/`, on 127.0.0.1 from port 47200); `tools/agent/live-mcp.mjs` stays up between runs, finds the game in `.agent/live/`, and forwards the tools listed in `scripts/live/tools.json`. It acts on the real game only: the link never starts in a test run, and the server never lists or uses a test instance. `tools/dev live smoke` tests it end to end, and `tools/dev live call <tool>` reaches the same tools from a shell.
- `blender` (mcp-for-blender) runs `tools/agent/blender-mcp.mjs`, which starts a Blender instance for the agent at the first tool call: Claude Code's on port 9886, Codex's on 9887. `tools/dev blender smoke` tests it end to end.

## Rules

- Indent GDScript with tabs and match the style of the file you are in.
- After adding a `class_name` or an asset, run `tools/dev import`.
- Keep each `.gd.uid` file with its script when moving, renaming, or deleting.
- Do not edit `.godot/`, `.mcp/`, or `.agent/`, and do not run `tools/build_graybox.py` unless asked (it overwrites the level scenes).
- Start Godot only through `tools/dev` or the MCP server, and launch MCP game sessions with `background: true`. A bare launch takes the user's keyboard focus and mouse.
- The `game` server is the game the user is playing. Read it freely; move, freeze, drive, or restart it only when the request calls for it. When they ask for a change in the game, make it there. An experiment of your own goes in a hidden sandbox (`tools/dev live sandbox`, reached by `--port`), and what you see there is not the state of their game.
- Use Blender only through the `blender` MCP server and `tools/dev blender`. The user's own Blender, its preferences, and its files are not yours to touch.
- A model is a `.blend` in `art/blender/` plus its exported `.glb` in `art/models/`. Change the source and re-export; never edit a `.glb` or its `.import` file by hand.
- This checkout is shared with a person in the Godot editor and with other agents. Leave Godot processes you did not start, re-read a file before editing it, and report unexpected changes or failures in files you did not touch instead of reverting them.
