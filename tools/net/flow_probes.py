#!/usr/bin/env python3
"""Run the match-flow probe scenarios (one headless game per peer) and check what each peer logged.

  tools/net/flow_probes.py                 # every scenario, 6 at a time
  tools/net/flow_probes.py D_late_join F_  # scenarios whose name starts with an argument
  options: --jobs=N --out=DIR --godot=PATH --list

Scenarios and their expectations live in tools/net/flow_scenarios.txt. Exit 0 when every
expectation held, 1 otherwise. Each peer gets its own HOME, so no saved settings are touched.
"""
import os, re, subprocess, sys, tempfile, threading, time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCENARIOS = os.path.join(ROOT, "tools", "net", "flow_scenarios.txt")
STATE = re.compile(r"^PROBE (\S+) t=([\d.]+) (\w+) ?(.*)$")
# Engine noise a headless run always prints; anything else that says ERROR is counted.
QUIET = re.compile(r"keybind_panel|RifleRecoil|Parameter \"material\" is null")


def load():
    scenarios, current = [], None
    for raw in open(SCENARIOS):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        word, _, rest = line.partition(" ")
        if word == "scenario":
            current = {"name": rest.strip(), "peers": [], "expect": [], "exit": {}, "errors": {}}
            scenarios.append(current)
        elif word == "peer":
            name, _, plan = rest.partition(" ")
            current["peers"].append((name, plan.strip()))
        elif word == "expect":
            peer, t0, t1, mode, pattern = rest.split(" ", 4)
            current["expect"].append((peer, float(t0), float(t1), mode, pattern))
        elif word == "exit":
            peer, code = rest.split()
            current["exit"][peer] = int(code)
        elif word == "max_errors":
            peer, count = rest.split()
            current["errors"][peer] = int(count)
        else:
            raise SystemExit("flow_scenarios.txt: unknown line: " + line)
    return scenarios


def limit_of(scenario):
    latest = 0.0
    for _, plan in scenario["peers"]:
        for step in plan.split(";"):
            latest = max(latest, float(step.split(":", 1)[0]))
    return latest + 4.0


def run(scenario, port, out, godot):
    folder = os.path.join(out, scenario["name"])
    os.makedirs(folder, exist_ok=True)
    limit = limit_of(scenario)
    procs = []
    for name, plan in scenario["peers"]:
        home = os.path.join(folder, "home_" + name)
        os.makedirs(home, exist_ok=True)
        env = dict(os.environ, HOME=home, XDG_DATA_HOME=home, XDG_CONFIG_HOME=home, APPDATA=home)
        log = open(os.path.join(folder, name + ".log"), "w")
        procs.append((name, log, subprocess.Popen(
            [godot, "--headless", "--path", ROOT, "res://tools/net/flow_probe.tscn", "--",
             "--name=" + name, "--port=%d" % port, "--limit=%d" % limit, "--plan=" + plan],
            stdout=log, stderr=subprocess.STDOUT, env=env)))
    deadline = time.time() + limit + 25.0
    codes = {}
    for name, log, proc in procs:
        try:
            codes[name] = proc.wait(timeout=max(deadline - time.time(), 0.1))
        except subprocess.TimeoutExpired:
            proc.kill()
            codes[name] = "hung"
        log.close()
    return check(scenario, folder, codes)


def check(scenario, folder, codes):
    problems = []
    states, errors = {}, {}
    for name, _ in scenario["peers"]:
        lines, bad = [], 0
        for raw in open(os.path.join(folder, name + ".log"), errors="replace"):
            found = STATE.match(raw.rstrip("\n"))
            if found:
                lines.append((float(found.group(2)), found.group(3) + " " + found.group(4)))
            elif ("ERROR" in raw or "handle_crash" in raw) and not QUIET.search(raw):
                bad += 1
        states[name], errors[name] = lines, bad
    for name, _ in scenario["peers"]:
        wanted = scenario["exit"].get(name, 0)
        if codes[name] != wanted:
            problems.append("%s exited %s, expected %s" % (name, codes[name], wanted))
        if name in scenario["errors"] and errors[name] > scenario["errors"][name]:
            problems.append("%s logged %d error lines, at most %d allowed" % (name, errors[name], scenario["errors"][name]))
    for peer, t0, t1, mode, pattern in scenario["expect"]:
        rule = re.compile(pattern)
        window = [text for at, text in states.get(peer, []) if t0 <= at <= t1]
        hits = [text for text in window if rule.search(text)]
        ok = {"any": bool(hits), "none": not hits, "all": bool(window) and len(hits) == len(window)}[mode]
        if not ok:
            miss = next((text for text in window if not rule.search(text)), "<no lines in the window>")
            shown = hits[0] if mode == "none" else miss
            problems.append("%s %g-%g %s /%s/ -> %s" % (peer, t0, t1, mode, pattern, shown[:300]))
    return scenario["name"], problems, errors


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    options = dict(a[2:].split("=", 1) if "=" in a else (a[2:], "1") for a in sys.argv[1:] if a.startswith("--"))
    scenarios = load()
    if "list" in options:
        print("\n".join(s["name"] for s in scenarios))
        return 0
    if args:
        scenarios = [s for s in scenarios if any(s["name"].startswith(a) for a in args)]
    out = options.get("out") or tempfile.mkdtemp(prefix="flow_probes_")
    godot = options.get("godot", "godot")
    base = int(options.get("port", 28100)) + (os.getpid() % 50) * 40
    failed = 0
    with ThreadPoolExecutor(max_workers=int(options.get("jobs", 6))) as pool:
        futures = [pool.submit(run, s, base + i, out, godot) for i, s in enumerate(scenarios)]
        for future in futures:
            name, problems, errors = future.result()
            print("%s  %s  errors=%s" % ("PASS" if not problems else "FAIL", name, errors), flush=True)
            for problem in problems:
                print("      " + problem, flush=True)
            failed += 1 if problems else 0
    print("%d scenarios, %d failed; logs in %s" % (len(scenarios), failed, out))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
