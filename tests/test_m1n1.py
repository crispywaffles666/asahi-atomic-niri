import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "files/system/usr/libexec/asahi-atomic-niri/update-m1n1-helper.sh"


class PayloadRefreshTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "FIXTURE": str(self.root),
            "MARKER_ROOT": str(self.root / "state"),
            "MODULE_ROOT": str(self.root / "modules"),
            "UPDATE_M1N1": str(self.bin / "update-m1n1"),
        }
        self.script("bootc", 'cat "$FIXTURE/status.json"')
        self.script("uname", 'printf "%s\\n" shared-kernel')
        self.script("update-m1n1", '''
if [[ ${ASAHI_ATOMIC_INSPECT:-} == 1 ]]; then
    printf '%s\\0' "$FIXTURE/m1n1.bin" "$FIXTURE/uboot.bin" \
        "$FIXTURE/m1n1.conf" "$ASAHI_ATOMIC_DTBS" "$FIXTURE/esp.bin"
    exit 0
fi
printf 'called\\n' >> "$FIXTURE/calls"
cat "$FIXTURE/m1n1.bin" "$ASAHI_ATOMIC_DTBS/apple/t6000.dtb" > "$FIXTURE/esp.bin"
[[ ! -e "$FIXTURE/fail" ]] || exit 1
[[ ! -e "$FIXTURE/race" ]] || printf 'changed\\n' >> "$FIXTURE/m1n1.conf"
''')
        self.dtb = self.root / "modules/shared-kernel/dtb/apple/t6000.dtb"
        self.dtb.parent.mkdir(parents=True)
        (self.root / "uboot.bin").write_bytes(b"UBOOT")
        (self.root / "m1n1.conf").write_text("display=auto\n")
        self.boot("a")

    def script(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/bash\nset -euo pipefail\n" + body + "\n")
        path.chmod(0o755)

    def boot(self, letter, payload=None):
        # Both trees use the same kernel/boot files. Only the bootc tree checksum
        # and payload inputs change; proc/cmdline is deliberately never mocked.
        (self.root / "status.json").write_text(json.dumps({
            "status": {"booted": {"ostree": {"checksum": letter * 64}}}
        }))
        (self.root / "m1n1.bin").write_text(payload or letter)
        self.dtb.write_text("DTB")

    def run_helper(self, command="refresh", success=True):
        result = subprocess.run(["bash", str(HELPER), command], env=self.env,
                                capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stderr)
        return result

    def calls(self):
        path = self.root / "calls"
        return len(path.read_text().splitlines()) if path.exists() else 0

    def test_rollback_restores_payload_and_repeated_boot_skips(self):
        for letter in ("a", "b", "a"):
            self.boot(letter)
            self.run_helper()
            self.assertEqual((self.root / "esp.bin").read_text(), letter + "DTB")
        self.assertEqual(self.calls(), 3)
        self.run_helper()
        self.assertEqual(self.calls(), 3)
        self.assertFalse(list((self.root / "state").glob(".current-payload.*")))

    def test_failed_write_invalidates_marker_and_rollback_retries(self):
        self.run_helper()
        self.boot("b")
        (self.root / "fail").touch()
        self.run_helper(success=False)
        self.assertFalse((self.root / "state/current-payload").exists())
        (self.root / "fail").unlink()
        self.boot("a")
        self.run_helper()
        self.assertEqual(self.calls(), 3)
        self.assertEqual((self.root / "esp.bin").read_text(), "aDTB")

    def test_actual_tree_checksum_from_bootc(self):
        for letter in ("a", "b"):
            self.boot(letter)
            result = self.run_helper("deployment-id")
            self.assertEqual(result.stdout.strip(), letter * 64)

    def test_same_payload_in_different_trees_does_not_rewrite(self):
        self.run_helper()
        self.boot("b", payload="a")
        self.run_helper()
        self.assertEqual(self.calls(), 1)

    def test_dtb_and_config_changes_trigger_refresh(self):
        self.run_helper()
        self.dtb.write_text("new DTB")
        self.run_helper()
        (self.root / "m1n1.conf").write_text("display=other\n")
        self.run_helper()
        self.assertEqual(self.calls(), 3)

    def test_old_historical_markers_do_not_suppress_refresh(self):
        historical = self.root / "state/updates" / ("a" * 64)
        historical.parent.mkdir(parents=True)
        historical.touch()
        self.run_helper()
        self.assertEqual(self.calls(), 1)

    def test_config_change_during_write_is_not_marked_successful(self):
        (self.root / "race").touch()
        self.run_helper(success=False)
        self.assertFalse((self.root / "state/current-payload").exists())

    def test_invalid_status_fails_before_updater(self):
        (self.root / "status.json").write_text('{"booted":{"checksum":"wrong"}}')
        self.run_helper(success=False)
        self.assertEqual(self.calls(), 0)


if __name__ == "__main__":
    unittest.main()
