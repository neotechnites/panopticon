#!/usr/bin/env python3
"""expect.py <log> <expect>...: check a smoke run's [event] lines against a brief entry's expect: clauses.

Clauses (';'-separated): "<kind> [who] lo-hi" (absolute s), "<kind> [who] +lo-hi" (after the first clause's
event), "<kind> [who]" (happened; never the anchor),
"alive <who>" (no out/ghosted), "max_yaw N" (every max_yaw event <= N). Exit 1 with the numbers on a miss.
"""
import re
import sys

EVENT = re.compile(r"^\[event\]\s+([0-9.]+)\s+(\S+)\s*(.*)$")


def main() -> int:
    events = []
    with open(sys.argv[1], errors="replace") as log:
        for line in log:
            m = EVENT.match(line)
            if m:
                events.append((float(m.group(1)), m.group(2), m.group(3)))
    clauses = [c.strip() for arg in sys.argv[2:] for c in arg.split(";") if c.strip()]
    anchor = None
    misses = []
    for clause in clauses:
        words = clause.split()
        kind = words[0]
        if kind == "alive":
            dead = [e for e in events if e[1] in ("out", "ghosted") and e[2].split()[:1] == [words[1]]]
            if dead:
                misses.append("%s: %s %s at %.2f" % (clause, dead[0][1], words[1], dead[0][0]))
            continue
        if kind == "max_yaw":
            seen = [float(e[2].split()[0]) for e in events if e[1] == "max_yaw"]
            if not seen or max(seen) > float(words[1]):
                misses.append("%s: max_yaw %s" % (clause, max(seen) if seen else "never logged"))
            continue
        if not re.match(r"^\+?[0-9.]+-[0-9.]+$", words[-1]):
            if not any(e[1] == kind and (len(words) < 2 or words[1] in e[2].split()) for e in events):
                misses.append("%s: never happened" % clause)
            continue
        span = words[-1]
        who = words[1] if len(words) == 3 else ""
        relative = span.startswith("+")
        lo, hi = (float(x) for x in span.lstrip("+").split("-"))
        hit = next((e for e in events if e[1] == kind and (not who or who in e[2].split())), None)
        if hit is None:
            misses.append("%s: never happened" % clause)
            continue
        t = hit[0] - (anchor or 0.0) if relative else hit[0]
        if anchor is None:
            anchor = hit[0]
        if not lo <= t <= hi:
            misses.append("%s: at %s%.2f" % (clause, "+" if relative else "", t))
    for t, kind, rest in events:
        print("  smoke %6.2f  %s  %s" % (t, kind, rest))
    for miss in misses:
        print("  MISSED %s" % miss)
    return 1 if misses else 0


if __name__ == "__main__":
    sys.exit(main())
