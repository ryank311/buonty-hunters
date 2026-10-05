#!/usr/bin/env python3
"""Native Linux builds and versioned SteamOS installs. Python standard library only."""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".build"
DEV = ROOT / "tools/dev"
TOOLCHAIN = Path(__file__).with_name("linux_toolchain.json")


def digest(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def run(args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, cwd=ROOT, **kwargs)


def output(args):
    return run(args, capture_output=True, text=True).stdout.strip()


def logged(args, log, required=None, timeout=600):
    with log.open("w") as stream:
        try:
            run(args, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            print(log.read_text()[-6000:], file=sys.stderr)
            raise RuntimeError(f"Failed; full log: {log}") from None
    text = log.read_text()
    errors = [line for line in text.splitlines() if line.startswith(("ERROR:", "SCRIPT ERROR:"))]
    if errors or (required and required not in text):
        raise RuntimeError(f"{chr(10).join(errors) or 'Completion marker missing'}\nLog: {log}")


def templates(version):
    spec = json.loads(TOOLCHAIN.read_text())
    if not version.startswith(spec["engine_version"] + "."):
        raise RuntimeError(f"Engine {version} does not match pinned templates {spec['engine_version']}. Update linux_toolchain.json with a verified official release.")
    destination = CACHE / "templates"
    marker = destination / "installed.json"
    names = ["linux_debug.x86_64", "linux_release.x86_64"]
    if marker.exists():
        installed = json.loads(marker.read_text())
        if installed.get("archive_sha256") == spec["sha256"] and all(
            (destination / n).is_file() and digest(destination / n) == installed.get("files", {}).get(n) for n in names
        ):
            return
    archive = CACHE / "downloads" / spec["archive"]
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        partial = archive.with_suffix(archive.suffix + ".part")
        print("Downloading official matching export templates (about 1.3 GB)...", flush=True)
        run(["curl", "-fLsS", "--retry", "3", spec["url"], "-o", partial])
        if digest(partial) != spec["sha256"]:
            raise RuntimeError(f"Template checksum mismatch: {partial}")
        partial.replace(archive)
    if digest(archive) != spec["sha256"]:
        raise RuntimeError(f"Template checksum mismatch: {archive}")
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as pack:
        packed_version = pack.read("templates/version.txt").decode().strip()
        if packed_version != spec["engine_version"]:
            raise RuntimeError(f"Unexpected template version: {packed_version}")
        # Extract only named Linux templates, never arbitrary archive paths.
        for name in names:
            with pack.open("templates/" + name) as source, (destination / name).open("wb") as target:
                shutil.copyfileobj(source, target)
            (destination / name).chmod(0o755)
    marker.write_text(json.dumps({"version": packed_version, "archive_sha256": spec["sha256"], "files": {n: digest(destination / n) for n in names}}, indent=2) + "\n")
    print("Linux templates installed and verified in .build/templates", flush=True)


def inventory():
    """Every installed runtime model and raw recovery JSON must survive export."""
    raw = {"res://" + str(p.relative_to(ROOT)): digest(p) for p in sorted((ROOT / "resources/recovered").rglob("*.json"))}
    resources = ["res://" + str(p.relative_to(ROOT)) for p in sorted((ROOT / "art/models").rglob("*.glb"))]
    resources += ["res://scenes/main.tscn", "res://resources/recovered/native.res"]
    return raw, resources


def checksums(directory):
    names = ["socom.x86_64", "socom.pck", "play.sh", "build-info.json"]
    (directory / "SHA256SUMS").write_text("".join(f"{digest(directory / n)}  {n}\n" for n in names))


def validate_bundle(directory):
    expected = {"socom.x86_64", "socom.pck", "play.sh", "build-info.json"}
    actual = set()
    for line in (directory / "SHA256SUMS").read_text().splitlines():
        checksum, name = line.split("  ", 1)
        if name not in expected or name in actual or digest(directory / name) != checksum:
            raise RuntimeError(f"Invalid bundle checksum: {name}")
        actual.add(name)
    if actual != expected:
        raise RuntimeError("Incomplete bundle checksum list")
    info = json.loads((directory / "build-info.json").read_text())
    if not re.fullmatch(r"\d{8}T\d{12}Z-[0-9a-f]{7,40}-(release|debug)", info["build_id"]):
        raise RuntimeError("Invalid build ID")
    return info


def build(args):
    if "McpBridge=" in (ROOT / "project.godot").read_text():
        raise RuntimeError("An MCP bridge is active in project.godot. Finish that agent session before exporting; do not ship its temporary autoload.")
    version = output([DEV, "godot", "--version"])
    templates(version)
    run([DEV, "import"])
    run([DEV, "check"])
    revision = output(["git", "rev-parse", "--short=10", "HEAD"])
    status = output(["git", "status", "--porcelain", "--untracked-files=normal"])
    mode = "debug" if args.debug else "release"
    build_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + f"-{revision}-{mode}"
    directory = CACHE / "linux" / build_id
    directory.mkdir(parents=True)
    raw, resources = inventory()
    info = {"build_id": build_id, "engine": version, "revision": revision, "dirty": bool(status), "mode": mode, "platform": "linux-x86_64", "runtime_json": raw, "runtime_resources": resources}
    (directory / "build-info.json").write_text(json.dumps(info, indent=2) + "\n")
    logs = CACHE / "logs" / build_id
    logs.mkdir(parents=True)
    print(f"Exporting {build_id} ({len(resources)} runtime resources)...", flush=True)
    logged([DEV, "godot", "--headless", "--path", ROOT, "--export-" + mode, "Linux", directory / "socom.x86_64"], logs / "export.log")
    with (directory / "socom.x86_64").open("rb") as stream:
        header = stream.read(20)
    if header[:6] != b"\x7fELF\x02\x01" or int.from_bytes(header[18:20], "little") != 62:
        raise RuntimeError("Export is not a 64-bit x86 Linux ELF executable")
    shutil.copyfile(Path(__file__).with_name("play-linux.sh"), directory / "play.sh")
    for name in ["socom.x86_64", "play.sh"]:
        (directory / name).chmod(0o755)
    # The editor can read the platform-neutral PCK on this Mac. Use --main-pack so
    # missing packed files cannot silently fall back to the source checkout.
    print("Auditing packed JSON/models and starting the packaged game headlessly...", flush=True)
    logged([DEV, "godot", "--headless", "--path", directory, "--main-pack", directory / "socom.pck", "--script", Path(__file__).with_name("verify_pack.gd"), "--", directory / "build-info.json"], logs / "audit.log", required="0 failures", timeout=120)
    logged([DEV, "godot", "--headless", "--path", directory, "--main-pack", directory / "socom.pck", "--quit-after", "90", "--", "--qa"], logs / "smoke.log", timeout=120)
    checksums(directory)
    validate_bundle(directory)
    link = directory.parent / ".latest-new"
    link.unlink(missing_ok=True)
    link.symlink_to(directory.name, target_is_directory=True)
    link.replace(directory.parent / "latest")
    size = sum(p.stat().st_size for p in directory.iterdir() if p.is_file()) / (1024 * 1024)
    print(f"BUILD: ok ({size:.1f} MiB)\n{directory}\nLogs: {logs}", flush=True)


def ssh_command(target, port, script, *args):
    command = "sh -s -- " + " ".join(shlex.quote(str(a)) for a in args)
    return output_with_input(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=accept-new", "-p", str(port), target, command], script)


def output_with_input(command, script):
    try:
        result = run(command, input=script, text=True, stdout=subprocess.PIPE)
    except subprocess.CalledProcessError as error:
        print(error.stdout or "", file=sys.stderr)
        raise
    print(result.stdout.strip(), flush=True)
    return result.stdout


PREPARE = '''set -eu
test "$(uname -s)" = Linux
test "$(uname -m)" = x86_64
command -v rsync >/dev/null
command -v timeout >/dev/null
base="$HOME/Games/socom"
mkdir -p "$base/releases" "$base/logs"
if [ -e "$base/current" ] && [ ! -L "$base/current" ]; then
 echo "Refusing to replace a non-symlink current directory" >&2; exit 1
fi
mkdir -p "$base/.incoming-$1"
echo "SSH_READY: $(uname -sm)"
'''

ACTIVATE = '''set -eu
base="$HOME/Games/socom"
stage="$base/.incoming-$1"
release="$base/releases/$1"
cd "$stage"
sha256sum -c SHA256SUMS
chmod +x socom.x86_64 play.sh
log="$base/logs/$1-smoke.log"
timeout 90 ./socom.x86_64 --headless --log-file "$log" --quit-after 90 -- --qa >"$log.console" 2>&1 || { cat "$log.console"; exit 1; }
if grep -E '^(SCRIPT ERROR:|ERROR:)' "$log.console"; then exit 1; fi
if [ -e "$release" ]; then
 cmp -s SHA256SUMS "$release/SHA256SUMS" || { echo "Build ID already exists with different content" >&2; exit 1; }
else
 mv "$stage" "$release"
fi
if [ -L "$base/current" ] && [ "$(readlink "$base/current")" != "releases/$1" ]; then
 ln -sfn "$(readlink "$base/current")" "$base/previous"
fi
ln -s "releases/$1" "$base/.current-$1"
mv -Tf "$base/.current-$1" "$base/current"
cat > "$base/play.sh" <<'LAUNCH'
#!/bin/sh
exec "$HOME/Games/socom/current/play.sh" "$@"
LAUNCH
chmod +x "$base/play.sh"
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/socom-playtest.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=SOCOM Playtest
Exec="$base/play.sh"
Path=$base
Terminal=false
Categories=Game;
DESKTOP
echo "LINUX_SMOKE: passed"
echo "DEPLOY: $release"
echo "STEAM_LAUNCHER: $base/play.sh"
'''


def deploy(args):
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*(?:@[A-Za-z0-9][A-Za-z0-9_.-]*)?", args.target):
        raise RuntimeError("Use a plain SSH alias or user@hostname/IP (no shell arguments). Configure keys/proxies in ~/.ssh/config.")
    directory = Path(args.build).expanduser().resolve() if args.build else (CACHE / "linux/latest").resolve()
    info = validate_bundle(directory)
    build_id = info["build_id"]
    ssh_command(args.target, args.port, PREPARE, build_id)
    transport = shlex.join(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=accept-new", "-p", str(args.port)])
    print(f"Transferring {build_id} to {args.target}...", flush=True)
    run(["rsync", "-az", "--partial", "-e", transport, str(directory) + "/", f"{args.target}:Games/socom/.incoming-{build_id}/"])
    ssh_command(args.target, args.port, ACTIVATE, build_id)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    export = sub.add_parser("build")
    export.add_argument("platform", choices=["linux"])
    export.add_argument("--debug", action="store_true")
    transfer = sub.add_parser("deploy")
    transfer.add_argument("platform", choices=["linux"])
    transfer.add_argument("target", help="SSH alias or user@hostname/IP")
    transfer.add_argument("--port", type=int, default=22)
    transfer.add_argument("--build", help="Use a particular build folder instead of .build/linux/latest")
    args = parser.parse_args()
    if args.command == "deploy" and not 1 <= args.port <= 65535:
        parser.error("Port must be between 1 and 65535")
    CACHE.mkdir(exist_ok=True)
    with (CACHE / "linux.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        (build if args.command == "build" else deploy)(args)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"LINUX: {error}", file=sys.stderr)
        sys.exit(1)
