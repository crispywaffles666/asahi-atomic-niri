import json
from pathlib import Path
import subprocess
import unittest

HELPER = Path(__file__).resolve().parents[1] / "files/system/etc/skel/.local/bin/auto-fullwidth-dp3.sh"


class WindowEvents(unittest.TestCase):
    def shell(self, script, data=""):
        return subprocess.run(["bash", "-c", 'source "$1"; ' + script, "test", str(HELPER)],
                              input=data, text=True, capture_output=True, check=True).stdout

    def test_json_not_formatting(self):
        events = [{"WindowOpenedOrChanged": {"window": {
            "title": 'id:999 "WindowClosed"', "id": 42, "workspace_id": 7,
            "is_focused": True, "is_floating": False}}}, {"WindowClosed": {"id": 42}}]
        for separators in [(" , ", " : "), (",", ":")]:
            data = "\n".join(json.dumps(e, separators=separators) for e in events)
            self.assertEqual(self.shell("parse_events", data),
                             "window\t42\t7\ttrue\tfalse\nclosed\t42\n")

    def test_closed_window_clears_history(self):
        self.assertEqual(self.shell('window_outputs[42]=DP-3; '
                                    'handle_event closed 42; '
                                    'printf "%s" "${window_outputs[42]-removed}"'), "removed")

    def test_close_unknown_window(self):
        self.shell("handle_event closed 99")


if __name__ == "__main__":
    unittest.main()
