---
name: steam-deploy
description: Build this Godot project for Linux, deploy it over SSH to the SteamOS desktop, and register or update SOCOM Playtest under Steam's Non-Steam games with its local box art. Use when asked to ship, push, or update a playtest build on the Steam machine.
---

# Ship to SteamOS

Run from this repository's root. This skill is shared by Codex and Claude Code: `.claude/skills` links to `.agents/skills`. Use the terminal commands below; no product-specific MCP server is needed.

The configured desktop is **deck@192.168.86.121**, SSH port **22**, native **Linux x86_64**. The title is **SOCOM Playtest**, installed as a **non-Steam game**, and the supplied art is **concept-art/Socom_2_Box_Art.jpg**. The stable launcher is `/home/deck/Games/socom/play.sh`.

## Normal delivery

```sh
tools/dev ship steam --restart-steam
```

This builds the current checkout with the pinned Godot release templates, deploys that exact verified bundle, registers the shortcut, and copies the original JPEG into its portrait and recent-game Steam library slots. It preserves the shortcut's existing app ID, launch options, controller configuration and other games. Builds are versioned; the stable shortcut follows `current` to the newest accepted release.

A request to ship authorizes the build, transfer, shortcut/art update and any required idle Steam refresh. `--restart-steam` only refreshes Steam if registration or art changed; it refuses while a Steam game is running. It never kills a game or restarts the desktop. Ordinary subsequent deliveries need no Steam restart. Do not launch the game unless requested.

The command already performs import/load checks, a packed-asset audit, checksums and a short native Linux headless startup. **Do not add full gameplay suites, live-MCP smoke tests, repeated screenshots or extra playtests to a routine delivery.** In particular, do not drive or restart the person's local game to validate a build. After the command succeeds, report the build ID, that it is in **Library → Non-Steam → SOCOM Playtest** with the box art, and that a running copy must be relaunched to use the update. Then stop.

## Variations and failures

- `--debug` builds a Linux debug package; release is the normal playtest build.
- `--target user@host --port N` overrides the configured machine only when requested.
- `--steam-user ID` selects a Steam userdata profile if there is more than one. Do not guess between accounts.
- If a verified bundle already exists or registration was interrupted, reuse it instead of rebuilding:

  ```sh
  tools/dev ship steam --build .build/linux/BUILD_ID --restart-steam
  ```

- If SSH fails, report the connection/authentication error and stop. Do not change system SSH settings or collect passwords in chat.
- If Steam registration refuses because a game is running, the deployment may already have succeeded. Report that distinction and the exact `--build` retry command for after the game is closed. Do not kill Steam or retry the entire build.
- If import, export or startup fails, use the reported log to fix the actual blocker within the request's scope. Do not label a failed candidate as deployed or silently fall back to an older package.
- If a temporary Godot MCP bridge is active, finish only your own session; do not remove another agent's autoload or stop someone else's game.

See [Linux playtests](../../../docs/LINUX_PLAYTEST.md) for logs, rollback, native Linux builds and toolchain maintenance. The implementation lives in `tools/build/linux.py` and `tools/build/steam_shortcut.py`; change those helpers instead of rewriting SSH or binary Steam configuration logic during each deployment.
