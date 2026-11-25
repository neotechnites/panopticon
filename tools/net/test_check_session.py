#!/usr/bin/env python3
"""Deterministic checks of check_session.py on written logs: python3 tools/net/test_check_session.py"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_session as cs  # noqa: E402

BASE_MS = 1_800_000_000_000
EPOCH = "kind=match epoch=2"


def peer(folder: Path, index: int, lines: list[tuple[float, str]]) -> cs.Peer:
    """A peer log from (seconds, "TAG rest") pairs, in time order."""
    path = folder / f"peer{index}.log"
    path.write_text("".join(f"NL w={BASE_MS + int(s * 1000)} t={s:.2f} {text}\n" for s, text in sorted(lines, key=lambda x: x[0])))
    return cs.Peer(index, path)


def failures(run) -> list[dict]:
    v = cs.Verdict()
    run(v)
    return v.failures


class CatPerSeat(unittest.TestCase):
    """The cat each seat draws, compared seat by seat; a handover between two seats in one frame is not a gap."""

    HOST = [(1.0, "MATCH bound kind=match epoch=2"), (1.0, "CAT seat=s1 drawn=0"), (1.0, "CAT seat=s2 drawn=0"),
            (10.0, "CAT seat=s1 drawn=1"), (14.0, "CAT seat=s1 drawn=0"), (14.0, "CAT seat=s2 drawn=1"),
            (18.0, "CAT seat=s2 drawn=0"), (25.0, "END ok")]

    def verdict(self, client_lines: list[tuple[float, str]]) -> list[dict]:
        with tempfile.TemporaryDirectory() as d:
            host = peer(Path(d), 0, self.HOST)
            client = peer(Path(d), 1, [(1.1, "MATCH bound kind=match epoch=2"), (25.0, "END ok")] + client_lines)
            return failures(lambda v: cs.check_presentation(host, [client], v, 0.2, lambda w: False))

    def test_a_one_frame_handover_drawn_a_tick_apart_passes(self):
        self.assertEqual(self.verdict([(10.15, "CAT seat=s1 drawn=1"), (14.15, "CAT seat=s1 drawn=0"),
                                       (14.183, "CAT seat=s2 drawn=1"), (18.18, "CAT seat=s2 drawn=0")]), [])

    def test_a_cat_never_drawn_fails(self):
        found = self.verdict([(10.15, "CAT seat=s1 drawn=1"), (14.15, "CAT seat=s1 drawn=0")])
        self.assertTrue(any("cat drawn=1 for s2" in f["message"] for f in found), found)

    def test_one_seats_cat_drawn_for_the_other_fails(self):
        found = self.verdict([(10.15, "CAT seat=s1 drawn=1"), (18.18, "CAT seat=s1 drawn=0")])
        self.assertTrue(any("for s2" in f["message"] for f in found), found)
        self.assertTrue(any("for s1" in f["message"] for f in found), found)


class EventsAfterTheRecord(unittest.TestCase):
    """A client's transitions: its record's replay, then exactly the host's after the last one replayed."""

    HOST = ["match_started n=4", "round_started round=1 guard=s0", "round_resolved round=1 outcome=WIN",
            "round_started round=2 guard=s1", "round_resolved round=2 outcome=WIN", "match_won seat=s1"]

    def verdict(self, replayed: list[str], sent: list[str]) -> list[dict]:
        with tempfile.TemporaryDirectory() as d:
            host = peer(Path(d), 0, [(1.0 + i, f"EV {e} {EPOCH} record=0") for i, e in enumerate(self.HOST)] + [(30.0, "END ok")])
            lines = [(2.5, "MATCH bound kind=match epoch=2")]
            lines += [(2.5, f"EV {e} {EPOCH} record=1") for e in replayed]
            lines += [(3.2 + i, f"EV {e} {EPOCH} record=0") for i, e in enumerate(sent)]
            client = peer(Path(d), 1, lines + [(30.0, "END ok")])
            return [f for f in failures(lambda v: cs.check_events(host, [client], v, 1.0)) if f["check"] == "events"]

    def test_the_hosts_tail_after_the_replay_passes(self):
        self.assertEqual(self.verdict(self.HOST[:2], self.HOST[2:]), [])

    def test_a_dropped_transition_fails(self):
        self.assertTrue(self.verdict(self.HOST[:2], [self.HOST[2]] + self.HOST[4:]))

    def test_a_reordered_transition_fails(self):
        self.assertTrue(self.verdict(self.HOST[:2], [self.HOST[3], self.HOST[2]] + self.HOST[4:]))

    def test_the_replayed_transition_again_fails(self):
        self.assertTrue(self.verdict(self.HOST[:2], [self.HOST[1]] + self.HOST[2:]))

    def test_a_replay_the_host_never_had_fails(self):
        self.assertTrue(self.verdict([self.HOST[0], "round_started round=3 guard=s2"], self.HOST[2:]))

    def test_the_last_transitions_missing_fails(self):
        self.assertTrue(self.verdict(self.HOST[:2], self.HOST[2:-1]))


class HeldPowerPresses(unittest.TestCase):
    """A q press runs the power the presser held, the seat the scenario gave; a guard's never runs."""

    def verdict(self, press: str, rule: str, spec: str = "", client: bool = False, expect: dict | None = None) -> list[dict]:
        scenario = {"peers": 2, "host": {"ability": spec} if spec else {}, "expect": expect or {}}
        with tempfile.TemporaryDirectory() as d:
            seat = "s1" if client else "s0"
            lines = [(1.0, "MATCH bound kind=match epoch=2"), (5.0, f"PRESS key=q seat={seat} {press} frame=100"),
                     (30.0, "END ok")]
            if client:
                lines.append((5.0, "SENT seat=s1 peer=7 seq=40 frame=100 pressed=256 released=0"))
                host_rule = f"RULE seat=s1 peer=7 seq=40 frame=900 real=1 pressed=256 {rule}"
            else:
                host_rule = f"RULE seat=s0 peer=1 seq=-1 frame=100 real=1 pressed=256 {rule}"
            host_lines = [(1.0, "MATCH bound kind=match epoch=2"), (5.05, host_rule), (30.0, "END ok")]
            if client:
                host = peer(Path(d), 0, host_lines)
                peers = [host, peer(Path(d), 1, lines)]
            else:
                host = peer(Path(d), 0, host_lines + lines[1:2])
                peers = [host]
            found = failures(lambda v: cs.check_presses(host, peers, v, 0.2, lambda w: False, scenario))
            return [f for f in found if f["check"] == "press"]

    def test_the_held_power_run_passes(self):
        self.assertEqual(self.verdict("valid=1 note=ok held=2", "ruling=ran ability=2 held=2", "2,4"), [])

    def test_a_client_whose_host_ran_another_power_fails(self):
        found = self.verdict("valid=1 note=ok held=2", "ruling=ran ability=3 held=3", client=True)
        self.assertTrue(any("ruled it ran" in f["message"] for f in found), found)

    def test_a_seat_holding_other_than_its_configured_power_fails(self):
        found = self.verdict("valid=1 note=ok held=3", "ruling=ran ability=3 held=3", "4,2", client=True)
        self.assertTrue(any("the scenario gave the seat 2" in f["message"] for f in found), found)

    def test_a_guard_press_the_host_ran_fails(self):
        found = self.verdict("valid=0 note=role-TOWER held=4", "ruling=ran ability=4 held=4")
        self.assertTrue(any("while TOWER" in f["message"] for f in found), found)

    def test_a_guard_press_refused_counts(self):
        self.assertEqual(self.verdict("valid=0 note=role-TOWER held=4", "ruling=unarmed ability=0 held=4",
                                      expect={"ruled_role_presses": {"0": 1}}), [])

    def test_too_few_refused_guard_presses_fails(self):
        self.assertTrue(self.verdict("valid=0 note=role-TOWER held=4", "ruling=unarmed ability=0 held=4",
                                     expect={"ruled_role_presses": {"0": 2}}))


class RolePowers(unittest.TestCase):
    """A power running on the guard or a ghost fails; on a prisoner it is the game."""

    def verdict(self, role: str) -> list[dict]:
        with tempfile.TemporaryDirectory() as d:
            host = peer(Path(d), 0, [(1.0, f"ROLE seat=s1 role={role} kind=HUMAN"), (2.0, "POWER seat=s1 ability=4 left=6.0"),
                                     (5.0, "END ok")])
            return [f for f in failures(lambda v: cs.check_role_powers(host, v)) if f["check"] == "role-power"]

    def test_a_running_prisoners_power_passes(self):
        self.assertEqual(self.verdict("RUNNING"), [])

    def test_the_guards_power_fails(self):
        self.assertTrue(self.verdict("TOWER"))

    def test_a_ghosts_power_fails(self):
        self.assertTrue(self.verdict("GHOST"))


if __name__ == "__main__":
    unittest.main()
