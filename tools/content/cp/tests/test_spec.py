"""Spec parser on Ryan's real script forms (run: python3 -m unittest discover tools/content/cp/tests)."""
import os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import spec  # noqa: E402

FX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")


class SpecTest(unittest.TestCase):
    def test_typos(self):
        s = spec.parse(os.path.join(FX, "typos.md"))
        ids = [l["id"] for l in s["lines"]]
        self.assertEqual(ids, ["L1", "L2", "L3", "L3a", "L4", "M5", "L6", "L7"])
        L = {l["id"]: l for l in s["lines"]}
        self.assertEqual(L["L1"]["text"], "first line with a pause marker")
        self.assertEqual(L["L1"]["note"], "note on the next line")
        self.assertEqual(L["L2"]["pauses"][0]["seconds"], 1.5)
        self.assertEqual(L["L2"]["note"], "first note | second note")
        self.assertEqual(L["L3"]["text"], "a voice line that runs over two lines")
        self.assertIn("refilm", L["L3"]["flags"])
        self.assertIn("keep_audio", L["L4"]["flags"])
        self.assertEqual(L["M5"]["kind"], "music")
        self.assertEqual(L["L6"]["text"], "unquoted voice text")
        self.assertTrue(L["L7"]["note"].startswith("shot 7"))

    def test_ragdoll(self):
        s = spec.parse(os.path.join(FX, "ragdoll_vnext.md"))
        self.assertEqual(s["header"]["base"], "ragdoll_short")
        self.assertEqual(len(s["lines"]), 8)
        self.assertTrue(s["lines"][3]["note"].startswith("sniper POV from the tower"))

    def test_devlog_tabbed(self):
        p = os.path.expanduser("~/Documents/senate/domains/panopticon/data/research/devlog0-script4-ryan-shots-2026-10-11.md")
        if not os.path.isfile(p): self.skipTest("devlog script not on this machine")
        s = spec.parse(p)
        self.assertEqual(s["form"], "tabbed")
        self.assertEqual(s["lines"][1]["id"], "M1")
        self.assertTrue(s["lines"][0]["note"].startswith("Godot editor"))


if __name__ == "__main__":
    unittest.main()
