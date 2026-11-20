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


if __name__ == "__main__":
    unittest.main()
