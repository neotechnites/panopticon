"""G1/G2 on hand-made rows."""
import os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import plan, spec  # noqa: E402

FX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")


class GateTest(unittest.TestCase):
    def test_g2_capture_with_hit_fails(self):
        hit = {"path": "x.avi", "in": 0, "len": 3, "rule": "capture_key", "score": 1.0}
        p = {"lines": [{"id": "L1", "action": "capture", "flags": [], "match": {"explicit": None, "capture_key": hit}}], "counts": {"capture": 1}}
        self.assertFalse(plan.gate_g2(p)["pass"])
        p["lines"][0]["flags"] = ["refilm"]
        self.assertTrue(plan.gate_g2(p)["pass"])
        p["lines"][0].update(flags=[], match={"explicit": None, "capture_key": None, "description": dict(hit, rule="description")})
        self.assertIn("footage search", plan.gate_g2(p)["reason"])

    def test_g1_rewritten_and_unlisted(self):
        sp = spec.parse(os.path.join(FX, "ragdoll_vnext.md"))
        rows = [{"line": l["id"], "text": l["text"], "note": l["note"], "source": "black", "overlays": [], "beats": [], "interpreted": []}
                for l in sp["lines"]]
        self.assertTrue(plan.gate_g1(sp, {"name": "r", "rows": rows})["pass"])
        rows[0]["note"] = "rewritten"
        rows[2].update(source="game", game={"map": "forest", "pov": "guard", "stage": "x"})
        g = plan.gate_g1(sp, {"name": "r", "rows": rows})
        self.assertFalse(g["pass"])
        self.assertTrue(any("note rewritten" in x for x in g["problems"]))
        self.assertTrue(any("game.map forest guessed" in x for x in g["problems"]))
        del rows[5]
        self.assertTrue(any("no shots.json row" in x for x in plan.gate_g1(sp, {"name": "r", "rows": rows})["problems"]))


if __name__ == "__main__":
    unittest.main()
