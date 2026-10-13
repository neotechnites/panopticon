#!/usr/bin/env python3
"""expect.py <log> <expect>...: check a smoke run's [event] lines against a brief entry's expect: clauses.

Clauses (';'-separated): "<kind> [who] lo-hi" (absolute s), "<kind> [who] +lo-hi" (after the first clause's
event), "<kind> [who]" (happened; never the anchor),
"alive <who>" (no out/ghosted), "max_yaw N" (every max_yaw event <= N), "lens_clear" ([lens] near < 0.8 m
for >= 0.1 s fails), "lens_cover <= N" (cover > N for >= 0.1 s fails); lens clauses read EXPECT_WINDOW="in seconds".
Exit 1 with the numbers on a miss.
"""
import os
import re
import sys

EVENT = re.compile(r"^\[event\]\s+([0-9.]+)\s+(\S+)\s*(.*)$")
LENS = re.compile(r"^\[lens\]\s+([0-9.]+)\s+near=([0-9.]+)\s+cover=([0-9.]+)")
LENS_NEAR_METRES = 0.8
LENS_NEAR_SECONDS = 0.1
LENS_COVER_SECONDS = 0.1


def longest_run(frames, bad):
    """(seconds, frames) of the longest unbroken run of frames where bad(frame) holds; a run spans from the frame before it."""
    best, run, run_from, prev = (0.0, []), [], 0.0, None
    for f in frames:
        if not bad(f):
            run = []
        else:
            if not run:
                run_from = prev[0] if prev is not None else f[0]
            run.append(f)
            if f[0] - run_from > best[0]:
                best = (f[0] - run_from, list(run))
        prev = f
    return best


def main() -> int:
    events, lens = [], []
    with open(sys.argv[1], errors="replace") as log:
        for line in log:
            m = EVENT.match(line)
            if m:
                events.append((float(m.group(1)), m.group(2), m.group(3)))
            m = LENS.match(line)
            if m:
                lens.append((float(m.group(1)), float(m.group(2)), float(m.group(3))))
    window = os.environ.get("EXPECT_WINDOW", "").split()
    if len(window) == 2:
        lo_t, hi_t = float(window[0]), float(window[0]) + float(window[1])
        lens = [f for f in lens if lo_t <= f[0] <= hi_t]
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
        if kind in ("lens_clear", "lens_cover"):
            if not lens:
                misses.append("%s: no [lens] lines" % clause)
                continue
            if kind == "lens_clear":
                span, run = longest_run(lens, lambda f: f[1] < LENS_NEAR_METRES)
                limit, what = LENS_NEAR_SECONDS, "near %.2f m" % min((f[1] for f in run), default=9.0)
            else:
                cap = float(words[-1])
                span, run = longest_run(lens, lambda f: f[2] > cap)
                limit, what = LENS_COVER_SECONDS, "cover %.2f" % max((f[2] for f in run), default=0.0)
            at = run[0][0] if run else 0.0
            print("  lens %s: longest %.2f s from %.2f (worst %s)" % (kind, span, at, what))
            if run and span >= limit:
                misses.append("%s: %.2f s from %.2f, worst %s" % (clause, span, at, what))
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
