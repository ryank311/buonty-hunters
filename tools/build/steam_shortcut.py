#!/usr/bin/env python3
"""Register the stable SOCOM launcher on SteamOS. Sent over SSH; stdlib only.

Binary KeyValues: ValveSoftware/source-sdk-2013, tier1/KeyValues.cpp.
Shortcut fields/IDs: SteamGridDB/steam-rom-manager, src/lib/vdf-shortcuts-file.ts.
Preserve existing field bytes, ordering, IDs and other shortcuts.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import time
import zlib


def decode(data):
    offset = 0

    def take(size):
        nonlocal offset
        value = data[offset:offset + size]
        if len(value) != size:
            raise ValueError("Truncated Steam shortcuts file")
        offset += size
        return value

    def string():
        nonlocal offset
        end = data.find(b"\0", offset)
        if end < 0:
            raise ValueError("Unterminated Steam shortcut field")
        value, offset = data[offset:end], end + 1
        return value

    def node(depth=0):
        if depth > 32:
            raise ValueError("Steam shortcuts nesting is too deep")
        result = []
        while True:
            kind = take(1)[0]
            if kind == 8:
                return result
            key = string()
            if kind == 0:
                value = node(depth + 1)
            elif kind == 1:
                value = string()
            elif kind in (2, 3, 4, 6, 7):
                value = take(8 if kind == 7 else 4)
            else:
                raise ValueError(f"Unsupported Steam field type {kind}; original file left intact")
            result.append((kind, key, value))

    result = node()
    if offset != len(data):
        raise ValueError("Trailing data in Steam shortcuts file")
    return result


def encode(node):
    return b"".join(bytes([kind]) + key + b"\0" + (
        encode(value) if kind == 0 else value + b"\0" if kind == 1 else value
    ) for kind, key, value in node) + b"\x08"


def get(node, key, default=b""):
    return next((v for _, k, v in node if k.lower() == key.lower()), default)


def put(node, kind, key, value):
    for index, (_, existing, _) in enumerate(node):
        if existing.lower() == key.lower():
            node[index] = (kind, existing, value)
            return
    node.append((kind, key, value))


def upsert(data, launcher):
    tree = decode(data) if data else [(0, b"shortcuts", [])]
    shortcuts = get(tree, b"shortcuts", None)
    if not isinstance(shortcuts, list) or any(k != 0 or not n.isdigit() for k, n, _ in shortcuts):
        raise ValueError("Unrecognized Steam shortcuts structure; original file left intact")
    target = str(launcher).encode()
    name = b"SOCOM Playtest"
    matches = [entry for _, _, entry in shortcuts
               if get(entry, b"exe").strip(b'"') == target or get(entry, b"appname") == name]
    if len(matches) > 1:
        raise ValueError("Multiple SOCOM shortcuts found; choose the entry to keep in Steam first")
    if matches:
        entry = matches[0]
    else:
        entry = []
        index = max((int(key) for _, key, _ in shortcuts), default=-1) + 1
        shortcuts.append((0, str(index).encode(), entry))
        appid = zlib.crc32(b'"' + target + b'"' + name) | 0x80000000
        put(entry, 2, b"appid", struct.pack("<I", appid))
        for key, value in [(b"AllowOverlay", 1), (b"AllowDesktopConfig", 1), (b"OpenVR", 0),
                           (b"Devkit", 0), (b"DevkitOverrideAppID", 0), (b"LastPlayTime", 0)]:
            put(entry, 2, key, struct.pack("<I", value))
        for key in [b"icon", b"ShortcutPath", b"LaunchOptions", b"DevkitGameID", b"FlatpakAppID"]:
            put(entry, 1, key, b"")
        put(entry, 0, b"tags", [])
    put(entry, 1, b"appname", name)
    put(entry, 1, b"exe", b'"' + target + b'"')
    put(entry, 1, b"StartDir", b'"' + str(launcher.parent).encode() + b'"')
    put(entry, 2, b"IsHidden", struct.pack("<I", 0))
    appid = get(entry, b"appid")
    if len(appid) != 4:
        raise ValueError("Existing SOCOM shortcut has no valid app ID")
    return encode(tree), struct.unpack("<I", appid)[0]


def processes():
    result = []
    for path in Path("/proc").iterdir():
        if not path.name.isdigit():
            continue
        try:
            if path.stat().st_uid != os.getuid():
                continue
            name = (path / "comm").read_text().strip()
            try:
                env = dict(p.split(b"=", 1) for p in (path / "environ").read_bytes().split(b"\0") if b"=" in p)
            except PermissionError:
                env = None
            args = [p.decode(errors="replace") for p in (path / "cmdline").read_bytes().split(b"\0") if p]
            result.append((name, env, args))
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError:
            raise RuntimeError(f"Cannot inspect process {path.name}; exit Steam manually before registering")
    return result


def steam_running():
    return any(name == "steam" for name, _, _ in processes())


def wait_steam(running, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if steam_running() == running:
            return
        time.sleep(0.5)
    raise RuntimeError("Steam did not " + ("start" if running else "exit") + "; no forced termination attempted")


def art_files(grid, appid):
    return [grid / f"{appid}p.jpg", grid / f"{appid}.jpg"]


def artwork_current(grid, appid, data):
    return bool(data) and all(p.is_file() and p.read_bytes() == data and not any(
        p.with_suffix(ext).exists() for ext in (".png", ".jpeg", ".webp")
    ) for p in art_files(grid, appid))


def install_artwork(grid, appid, data):
    grid.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    for path in art_files(grid, appid):
        # Only this shortcut's two capsule slots; retain previous art as backups.
        for existing in [path] + [path.with_suffix(ext) for ext in (".png", ".jpeg", ".webp")]:
            if existing.exists() and (existing != path or existing.read_bytes() != data):
                existing.rename(existing.with_name(existing.name + ".socom-" + stamp + ".bak"))
        if not path.exists():
            temporary = path.with_name(path.name + f".socom-{os.getpid()}.tmp")
            temporary.write_bytes(data)
            temporary.replace(path)
    if not artwork_current(grid, appid, data):
        raise RuntimeError("Steam box art verification failed")
    print(f"STEAM_ARTWORK: {grid / (str(appid) + 'p.jpg')}", flush=True)


def install(profile=None, restart=False, inspect=False, art_sha256=None):
    steam = Path.home() / ".steam/steam"
    if not steam.is_dir():
        steam = Path.home() / ".local/share/Steam"
    profiles = sorted(p for p in (steam / "userdata").iterdir() if p.is_dir() and p.name.isdigit() and p.name != "0")
    if profile:
        profiles = [p for p in profiles if p.name == profile]
    if len(profiles) != 1:
        raise RuntimeError("Select one Steam account with --steam-user; available IDs: " + ", ".join(p.name for p in profiles))
    path = profiles[0] / "config/shortcuts.vdf"
    launcher = Path.home() / "Games/socom/play.sh"
    if not launcher.is_file():
        raise RuntimeError("Deploy the Linux build before registering its Steam launcher")
    original = path.read_bytes() if path.exists() else b""
    updated, appid = upsert(original, launcher)
    art = launcher.parent / "steam-box-art.jpg"
    art_data = art.read_bytes() if art.exists() else b""
    grid = path.parent / "grid"
    if not inspect and (not art_data.startswith(b"\xff\xd8") or (art_sha256 and hashlib.sha256(art_data).hexdigest() != art_sha256)):
        raise RuntimeError("Deploy concept-art/Socom_2_Box_Art.jpg first; Steam box art missing or checksum mismatch")
    art_ready = artwork_current(grid, appid, art_data)
    print(f"STEAM_PROFILE: {profiles[0].name}; shortcut {'needs registration' if updated != original else 'already current'}", flush=True)
    print(f"STEAM_ART: {'already current' if art_ready else 'needs installation'}", flush=True)
    if inspect:
        return
    if updated == original and art_ready:
        print(f"STEAM_REGISTERED: SOCOM Playtest ({appid}); no Steam restart needed", flush=True)
        return
    running = [item for item in processes() if item[0] == "steam"]
    restart_env = dict(os.environ)
    restart_args = ["steam", "-silent"]
    if running:
        if not restart:
            raise RuntimeError("Exit Steam once, or pass --restart-steam to refresh its library when no game is running")
        current = processes()
        # SteamOS protects the environments of its login services and compositor.
        # These are infrastructure, not games. Unknown protected apps still block refresh.
        infrastructure = {"systemd", "(sd-pam)", "sshd", "sshd-session", "gamescope", "gamescope-wl"}
        unknown = [name for name, env, _ in current if env is None and name not in infrastructure]
        if unknown:
            raise RuntimeError("Cannot rule out a running game in protected processes: " + ", ".join(unknown) + "; exit Steam manually")
        active = [name for name, env, _ in current if env and any(env.get(k, b"0") not in (b"", b"0") for k in (b"SteamAppId", b"SteamGameId"))]
        if active:
            raise RuntimeError("A Steam game is running; close it before registration: " + ", ".join(sorted(set(active))))
        _, env, args = running[0]
        if env is None:
            raise RuntimeError("Cannot read the Steam display session; exit Steam manually")
        for key in ["DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "XAUTHORITY"]:
            if key.encode() in env:
                restart_env[key] = os.fsdecode(env[key.encode()])
        restart_args += [a for a in args if a in ("-steamdeck", "-gamepadui", "-pipewire")]
        print("Refreshing Steam once to register SOCOM Playtest...", flush=True)
        subprocess.run(["steam", "-shutdown"], env=restart_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15, check=True)
        wait_steam(False, 30)
    try:
        # Steam flushes its own in-memory shortcuts on exit; merge with that final file.
        original = path.read_bytes() if path.exists() else b""
        updated, appid = upsert(original, launcher)
        if steam_running():
            raise RuntimeError("Steam reopened before registration; original file left intact")
        if updated != original:
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.exists():
                stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
                backup = path.with_name(path.name + ".socom-" + stamp + ".bak")
                shutil.copy2(path, backup)
                print(f"STEAM_BACKUP: {backup}", flush=True)
            temporary = path.with_name(path.name + f".socom-{os.getpid()}.tmp")
            with temporary.open("xb") as stream:
                stream.write(updated)
                stream.flush()
                os.fsync(stream.fileno())
            temporary.chmod(path.stat().st_mode & 0o777 if path.exists() else 0o600)
            temporary.replace(path)
            if path.read_bytes() != updated:
                raise RuntimeError("Steam shortcut verification failed")
        install_artwork(grid, appid, art_data)
    finally:
        if running and not steam_running():
            subprocess.Popen(restart_args, env=restart_env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
            wait_steam(True, 20)
    # Re-read the actual persisted entry, including a stable existing app ID.
    checked, _ = upsert(path.read_bytes(), launcher)
    if checked != path.read_bytes():
        raise RuntimeError("Steam changed the shortcut during registration; inspect its library before retrying")
    print(f"STEAM_REGISTERED: SOCOM Playtest ({appid}); steam://rungameid/{(appid << 32) | 0x02000000}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--steam-user")
    parser.add_argument("--restart-steam", action="store_true")
    parser.add_argument("--inspect", action="store_true")
    parser.add_argument("--art-sha256")
    args = parser.parse_args()
    try:
        install(args.steam_user, args.restart_steam, args.inspect, args.art_sha256)
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"STEAM: {error}", file=sys.stderr)
        sys.exit(1)
