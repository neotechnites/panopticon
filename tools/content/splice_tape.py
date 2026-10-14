#!/usr/bin/env python3
"""Splice a recorded lead-in onto a tape: lead-in ticks [0, at) then the tape from tick `onto` on, shifted;
every body's whole state at `at` is the tape's own entering `onto` (clip_tape.gd TAPE_DUMP)."""
import json
import sys


def splice(lead_path, tape_path, dump_path, at, onto, out_path, stage, dials):
    lead, tape, dump = (json.load(open(p)) for p in (lead_path, tape_path, dump_path))
    shift = at - onto
    out = dict(tape)
    out.update({"stage": stage, "set": dials, "ticks": tape["ticks"] + shift,
                "seconds": round(float(tape["seconds"]) + shift / 60.0, 4)})
    out["fires"] = [[f[0] + shift] + f[1:] for f in tape["fires"]]
    bodies = {}
    for name, old in tape["bodies"].items():
        new = lead["bodies"][name]
        rows = [r for r in new["intent"] if r[0] < at]
        live = [r for r in old["intent"] if r[0] <= onto]
        if live:
            rows.append([at] + live[-1][1:])
        rows += [[r[0] + shift] + r[1:] for r in old["intent"] if r[0] > onto]
        pre = {t: w for t, w in new["pre"].items() if int(t) < at}
        pre[str(at)] = dump[name]
        pre.update({str(int(t) + shift): w for t, w in old["pre"].items() if int(t) > onto})
        late = {t: w for t, w in new["late"].items() if int(t) < at}
        late.update({str(int(t) + shift): w for t, w in old["late"].items() if int(t) >= onto})
        bodies[name] = {"intent": rows, "late": late, "pre": pre}
    out["bodies"] = bodies
    json.dump(out, open(out_path, "w"), indent="\t", sort_keys=True)


if __name__ == "__main__":
    a = sys.argv[1:]
    splice(a[0], a[1], a[2], int(a[3]), int(a[4]), a[5], a[6], a[7])
