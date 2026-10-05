# Linux and SteamOS playtests

Build on this Mac or on a Linux checkout, then install a native x86_64 package over SSH. SteamOS only needs the exported package to play. Everything is installed in the user's home directory; no change to SteamOS's read-only system partition is needed.

## Build and deploy

From the repository root:

```sh
tools/dev build linux
tools/dev deploy linux deck@STEAMOS_HOST
```

Replace `STEAMOS_HOST` with the desktop's hostname or IP. `--port PORT` supports a different SSH port. The desktop must accept your SSH key and have `rsync` and `timeout`; both are available on the tested SteamOS installation. To set up a new machine, enable its SSH service in Konsole (`sudo systemctl enable --now sshd`), then authorize this Mac's existing public key from a Mac terminal (`ssh-copy-id -i ~/.ssh/id_ed25519.pub deck@STEAMOS_HOST`). Enter passwords in the terminal, never in agent configuration or chat. The commands retain SSH host-key checking.

`tools/dev build linux --debug` selects a debug export. Release is the default for performance/feel testing. Deploy an older local build explicitly with `tools/dev deploy linux deck@STEAMOS_HOST --build .build/linux/BUILD_ID`.

The build command:

1. Checks the editor version against `tools/build/linux_toolchain.json`. On first use it downloads the official template archive (about 1.3 GB), verifies its pinned SHA-256 and extracts only the two Linux x86_64 templates into `.build/templates/`. No global Godot installation settings are changed.
2. Runs `tools/dev import` and `tools/dev check`, then exports the `Linux` preset. It refuses an active temporary MCP bridge autoload. Run `tools/dev test` as the normal broader regression gate before a handoff.
3. Audits the PCK itself: every installed GLB and every raw recovery JSON file must be present; JSON bytes must match their source hashes. Starts the packaged game headlessly using this machine's Godot editor, with no source-file fallback.
4. Writes the executable, PCK, launcher, build metadata and checksums into `.build/linux/BUILD_ID/`. Only a successful build advances `.build/linux/latest`. Output and templates are ignored by Git.

`build-info.json` records the engine, commit, dirty-working-tree flag, export mode and runtime inventory. Builds intentionally include current uncommitted runtime imports; they are development snapshots, not a promise that cloning the recorded commit recreates a dirty build.

Deployment transfers to a staging directory, verifies SHA-256 on SteamOS and runs the **actual Linux executable** headlessly. Only after that succeeds does it select the versioned release through `~/Games/socom/current`. The previous release remains in `releases/` and is linked as `previous`. A transfer or startup failure leaves the current selection intact. Deployment does not kill or restart a game someone is playing: quit and relaunch to use the new build. Failed staging folders/logs remain available for diagnosis.

## Launch through KDE or Steam

Deployment installs **SOCOM Playtest** into the KDE application menu. It also creates this stable launcher:

```text
/home/deck/Games/socom/play.sh
```

In Steam, choose **Games → Add a Non-Steam Game**, select **SOCOM Playtest**, or browse to the launcher. Keep that one shortcut for every future build. Use a Gamepad controller layout for the game's native controller bindings. `--fullscreen` can be added to the shortcut's launch options. This is a native Linux application; leave forced compatibility-tool selection unchecked.

The package contains the existing fixed 640×480 presentation and Mobile renderer. The Linux renderer uses Vulkan. Startup checks do not certify GPU performance, audio, physical controller mapping, rumble or frame pacing: play it on the target hardware. Test Old Quarter, Movement Lab and recovered maps; compare analog walk/run, aim, fire, recoil, weapon changes and stance changes. Revisit the same route and camera angle when comparing performance.

## Logs and rollback

| Location | Contents |
| --- | --- |
| Local `.build/logs/BUILD_ID/` | Export, packed-data audit and local startup logs |
| SteamOS `~/Games/socom/logs/BUILD_ID-smoke.log.console` | Native startup output used to accept/reject deployment |
| SteamOS `~/.local/state/socom/play.log` | Latest interactive launch (`$XDG_STATE_HOME/socom` if set) |
| SteamOS `~/.local/state/socom/play.previous.log` | Previous interactive launch |
| SteamOS `~/Games/socom/current/build-info.json` | Selected build version and asset inventory |

To return to an earlier build, quit the game and deploy its retained local folder with `--build`. Installed release folders are not automatically deleted. If storage becomes an issue, remove only named old releases after checking `current` and `previous`.

Godot's release templates disable `--path` overrides. The packaged launcher changes into the executable's own directory and lets it find its adjacent PCK. Do not add `--path` to Steam's launch options. The live agent link is intentionally disabled in exports, including debug exports.

## Run or build natively on Linux

Install the same **Godot 4.7 stable standard editor** in your home directory and clone/sync this project, including its runtime assets. The wrapper finds `godot` or `godot4` on PATH, or accepts `GODOT_BIN` pointing to the executable. Source runs do not require export templates or Blender:

```sh
tools/dev import
tools/dev check
tools/dev test
tools/dev play
```

`tools/dev build linux` works there too with Python 3.9+, curl and the editor. Source `.godot/` caches should be regenerated on Linux. A Git clone contains committed assets only; the Mac's uncommitted recovery imports arrive in its exported builds, not automatically through Git. The live link works locally for source runs; remote inspection would need its own SSH-tunnel/discovery setup.

## Agent maintenance

`export_presets.cfg` exports all runtime resources because characters, maps and guns are loaded dynamically. It explicitly includes `resources/recovered/*.json` and nested level JSON, and excludes tools, tests, docs, the ISO/recovery tree and Blender sources. Templates use desktop S3TC/BPTC compression; PCK remains a separate file. Keep the export preset's custom-template paths aligned with the build helper. When updating Godot, update the pinned version, official download URL and verified checksum together.

After changing this pipeline, run `python3 -B -m unittest discover -s tools/build -p 'test_*.py' -v`, `tools/dev build linux`, and a real deployment. The tests cover corrupted/missing checksums, path injection, Godot script errors despite exit code zero, and preserving the installed build when a candidate fails startup. Keep remote commands scoped to this game's directories and leave other processes alone.

Initial validation, 2026-10-05: matching official 4.7 templates verified; 107 resources/scripts checked; all 25 project regression suites and six build/deploy tests passed; 37 JSON files and 318 runtime resources audited in the PCK; 276.1 MiB release package installed on SteamOS 3.8.28 x86_64 with AMD Navi 33 graphics. Checksums and native Linux headless startup passed. Physical controller and Vulkan rendering still require an interactive playtest on that desktop.

References: [Godot export configuration](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html), [Linux exporter options](https://docs.godotengine.org/en/stable/classes/class_editorexportplatformlinuxbsd.html), [official 4.7 templates](https://github.com/godotengine/godot-builds/releases/tag/4.7-stable), [Steam shortcuts](https://help.steampowered.com/en/faqs/view/4B8B-9697-2338-40EC).
