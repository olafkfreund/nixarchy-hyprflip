"""Rewrite hyprpm.toml's main commit pin the way the nightly land step does."""
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "hyprpm_pin.py"
RELEASE = ["efb50993780079460b0cbed1363e2166a2de1d9f", "429d5236752b32e6ef3d8df8c6a798a0374dc6a0"]
OLD = "4bb6844b0351e4fbf2e3d4e46ae71b551a0e0a42"
NEW = "1111111111111111111111111111111111111111"
PLUGIN = "2222222222222222222222222222222222222222"
MANIFEST = f"""[repository]
name = "hyprflip"
# comments survive
commit_pins = [
    ["{RELEASE[0]}", "{RELEASE[1]}"],
    ["{OLD}", "178885bd77a0f77765a31a21a75c6e14393a6718"],
]

[hyprflip]
output = "build/hyprflip.so"
"""


class HyprpmPinTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="hyprflip-hyprpm-")
        self.addCleanup(temporary.cleanup)
        self.manifest = Path(temporary.name) / "hyprpm.toml"

    def pin(self, text, *hashes):
        self.manifest.write_text(text)
        return subprocess.run(
            [sys.executable, SCRIPT, "--file", self.manifest, *hashes],
            capture_output=True, text=True,
        )

    def pins(self):
        return tomllib.loads(self.manifest.read_text())["repository"]["commit_pins"]

    def test_replaces_the_old_main_pin_and_keeps_the_release_pin(self):
        result = self.pin(MANIFEST, OLD, NEW, PLUGIN)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.pins(), [RELEASE, [NEW, PLUGIN]])
        self.assertIn("# comments survive", self.manifest.read_text())

    def test_keeps_the_file_mode(self):
        self.manifest.write_text(MANIFEST)
        self.manifest.chmod(0o644)
        subprocess.run([sys.executable, SCRIPT, "--file", self.manifest, OLD, NEW, PLUGIN], check=True, capture_output=True)
        self.assertEqual(self.manifest.stat().st_mode & 0o777, 0o644)

    def test_appends_when_no_pin_matches_old(self):
        first_run = MANIFEST.replace(f'    ["{OLD}", "178885bd77a0f77765a31a21a75c6e14393a6718"],\n', "")
        result = self.pin(first_run, OLD, NEW, PLUGIN)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.pins(), [RELEASE, [NEW, PLUGIN]])

    def test_same_pair_is_a_no_op(self):
        result = self.pin(MANIFEST, OLD, OLD, "178885bd77a0f77765a31a21a75c6e14393a6718")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.manifest.read_text(), MANIFEST)

    def test_rejects_bad_hashes_and_leaves_the_file_alone(self):
        for bad in ("abc", PLUGIN.replace("2", "A"), "g" * 40, NEW + "1", "'" + NEW[1:]):
            with self.subTest(bad=bad):
                result = self.pin(MANIFEST, OLD, bad, PLUGIN)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.manifest.read_text(), MANIFEST)

    def test_refuses_a_manifest_without_the_release_pin(self):
        no_release = MANIFEST.replace(f'    ["{RELEASE[0]}", "{RELEASE[1]}"],\n', "")
        result = self.pin(no_release, OLD, NEW, PLUGIN)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.manifest.read_text(), no_release)


if __name__ == "__main__":
    unittest.main()
