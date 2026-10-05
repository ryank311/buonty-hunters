"""Bundle integrity and deployment failure isolation; no SSH or game data needed."""
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import linux


class LinuxBuildTests(unittest.TestCase):
    def bundle(self, directory):
        for name in ["socom.x86_64", "socom.pck", "play.sh"]:
            (directory / name).write_text("fixture " + name)
        (directory / "build-info.json").write_text(json.dumps({"build_id": "20261005T120000123456Z-1234567890-release"}))
        linux.checksums(directory)

    def test_modified_game_data_cannot_deploy(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.bundle(directory)
            self.assertEqual(linux.validate_bundle(directory)["build_id"], "20261005T120000123456Z-1234567890-release")
            (directory / "socom.pck").write_text("truncated or modified transfer")
            with self.assertRaisesRegex(RuntimeError, "checksum"):
                linux.validate_bundle(directory)

    def test_checksum_list_cannot_escape_bundle(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.bundle(directory)
            with (directory / "SHA256SUMS").open("a") as stream:
                stream.write("0" * 64 + "  ../outside\n")
            with self.assertRaisesRegex(RuntimeError, "checksum"):
                linux.validate_bundle(directory)

    def test_missing_checksum_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.bundle(directory)
            sums = directory / "SHA256SUMS"
            sums.write_text("\n".join(sums.read_text().splitlines()[:-1]) + "\n")
            with self.assertRaisesRegex(RuntimeError, "Incomplete"):
                linux.validate_bundle(directory)

    def test_invalid_build_id_cannot_become_remote_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.bundle(directory)
            for name in ["..", "../elsewhere", "$(touch marker)", "; true"]:
                (directory / "build-info.json").write_text(json.dumps({"build_id": name}))
                linux.checksums(directory)
                with self.subTest(name=name), self.assertRaisesRegex(RuntimeError, "build ID"):
                    linux.validate_bundle(directory)

    def test_godot_zero_exit_with_script_error_still_fails(self):
        def failure(args, **kwargs):
            kwargs["stdout"].write("SCRIPT ERROR: Missing runtime asset\n")
            return subprocess.CompletedProcess(args, 0)
        with tempfile.TemporaryDirectory() as temporary, patch.object(linux, "run", side_effect=failure):
            with self.assertRaisesRegex(RuntimeError, "Missing runtime asset"):
                linux.logged(["fake-godot"], Path(temporary) / "log")

    def test_activation_failure_keeps_current_build(self):
        # Exercise the remote shell script in a temporary installation. The candidate
        # passes checksums but its Linux executable fails its smoke test.
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            base = directory / "Games/socom"
            old = base / "releases/old"
            old.mkdir(parents=True)
            (base / "logs").mkdir()
            (base / "current").symlink_to("releases/old")
            stage = base / ".incoming-new"
            stage.mkdir()
            self.bundle(stage)
            (stage / "socom.x86_64").write_text("#!/bin/sh\nexit 7\n")
            linux.checksums(stage)
            # Adapt only the install path and utility names for this Mac-side test.
            script = linux.ACTIVATE.replace('base="$HOME/Games/socom"', "base=" + shlex.quote(str(base)))
            if not shutil.which("sha256sum"):
                script = script.replace("sha256sum -c", "shasum -a 256 -c")
            script = script.replace("timeout 90 ", "")
            result = subprocess.run(["sh", "-s", "--", "new"], input=script, text=True, capture_output=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue((base / "logs/new-smoke.log.console").is_file(), result.stderr)
            self.assertEqual((base / "current").resolve(), old.resolve())
            self.assertFalse((base / "releases/new").exists())


if __name__ == "__main__":
    unittest.main()
