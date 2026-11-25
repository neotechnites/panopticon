#!/usr/bin/env python3
"""Write the scenario matrix into tools/net/scenarios/. The files are committed; rerun after editing this.

    python3 tools/net/make_scenarios.py

Axes: peers 2/3/4 x hell/marble x opening (race, named guard on the host, on a client, on a bot,
tower fight) x each held power x ghosts on/off x rematch / hub return / relaunch, the wire faults
(loss, delay, jitter, reordering, duplication, burst loss, stalls and hitches, bind delay) and the two
leavers (a client, the host).
"""

from __future__ import annotations

import json
from pathlib import Path

OUT = Path(__file__).resolve().parent / "scenarios"
MAPS = {"hell": "bentham_ring", "marble": "marble"}
# Every key the game reads, in one life, for the one power the seat holds: q three times, shove, both
# emotes; the cat is cooked (e) and thrown (f). Spaced past each power's run and cooldown (match/powers/).
LIFE_KEYS = {
    1: "q@5,f@>1.2,b@14+2,n@19+2,q@34,q@64",
    2: "q@5,f@>1.2,b@14+2,n@19+2,q@24,q@42",
    3: "q@5+2,f@>1.2,b@14+2,n@19+2,q@24+2,q@40",
    4: "q@5,f@>1.2,b@14+2,n@19+2,q@28,q@50",
    5: "q@5,e@>1,b@14+2,n@19+2,q@28,f@>1.2,q@46,e@>1",
}


def life_keys(power: int, late: float = 0.0) -> str:
    """[LIFE_KEYS] for [power], every absolute time [late] seconds later."""
    def shift(step: str) -> str:
        key, at = step.split("@")
        if at.startswith(">"):
            return step
        head = at.split("+")[0].split("/")[0]
        return f"{key}@{float(head) + late:g}{at[len(head):]}"
    return ",".join(shift(step) for step in LIFE_KEYS[power].split(","))


def mixed(powers: tuple[int, ...], late: float = 2.0) -> tuple[dict, dict]:
    """Seats 0.. hold [powers], each different: the host's --ability spec and each client's own keys."""
    peers = {str(i): {"keys": life_keys(power, late)} for i, power in enumerate(powers) if i > 0}
    return {"keys": life_keys(powers[0]), "ability": ",".join(str(p) for p in powers)}, peers

scenarios: list[dict] = []


def add(name: str, runner: str, peers: int, limit: int, tags: list[str], **parts: dict) -> None:
    scenario = {"name": name, "runner": runner, "peers": peers, "limit": limit, "tags": tags}
    scenario.update({k: v for k, v in parts.items() if v})
    scenarios.append(scenario)


def match(name: str, peers: int, seconds: int, tags: list[str], common: dict, host: dict | None = None,
          client: dict | None = None, peer: dict | None = None, expect: dict | None = None, kill: list | None = None,
          limit_extra: int = 0) -> None:
    base = {"seconds": seconds}
    base.update(common)
    add(name, "match", peers, seconds + 45 + limit_extra, tags, common=base, host=host or {}, client=client or {},
        peer=peer or {}, expect=expect or {}, kill=kill or [])


def hub(name: str, peers: int, limit: int, tags: list[str], common: dict, host: dict | None = None,
        client: dict | None = None, peer: dict | None = None, expect: dict | None = None, kill: list | None = None) -> None:
    common = dict(common)
    common.setdefault("limit", limit - 20)
    add(name, "hub", peers, limit, tags, common=common, host=host or {}, client=client or {},
        peer=peer or {}, expect=expect or {}, kill=kill or [])


# --- A. The whole flow in one run, won on its own ------------------------------
# A match between people ends when a guard clears the lane, so the people here can shoot ("marksman"):
# everywhere else the scripted guard pulls the moment it sees somebody and mostly misses, and the rounds run on.
for peers in (2, 3, 4):
    for order, maps in (("hell_marble", "bentham_ring,marble"), ("marble_hell", "marble,bentham_ring")):
        hub(f"flow_{peers}p_{order}", peers, 520, ["flow", "smoke"] if (peers, order) == (2, "hell_marble") else ["flow"],
            {"maps": maps, "matches": 2, "ceiling": 200, "hub_seconds": 6, "marksman": True},
            host={"prisoners": 3, "rounds": 1},
            expect={"matches": 2, "natural_win": True,
                    "all": ["SCENE kind=hub", "EV match_won"], "host": ["EV round_started round=1"]})
hub("flow_3p_hell_marble_rounds2", 3, 760, ["flow"],
    {"maps": "bentham_ring,marble", "matches": 2, "ceiling": 330, "hub_seconds": 6, "marksman": True},
    host={"prisoners": 3, "rounds": 2},
    expect={"matches": 2, "natural_win": True, "host": ["EV round_started round=2"]})
FLOW_HOST, FLOW_PEERS = mixed((5, 2, 3, 1))
hub("flow_4p_hell_marble_keys", 4, 520, ["flow", "powers"],
    {"maps": "bentham_ring,marble", "matches": 2, "ceiling": 200, "hub_seconds": 6},
    host=dict(FLOW_HOST, prisoners=4, rounds=1), peer=FLOW_PEERS,
    expect={"matches": 2})

# --- B. Openings x map x peers -------------------------------------------------
for peers in (2, 3, 4):
    seats = max(4, peers) if peers < 4 else 5
    for map_name, map_id in MAPS.items():
        match(f"open_race_{peers}p_{map_name}", peers, 100, ["opening"], {"map": map_id, "seats": seats, "tower": -1},
              expect={"all": ["EV race_started"], "host": ["EV round_started round=1"]})
        match(f"open_hostguard_{peers}p_{map_name}", peers, 75, ["opening", "guard"],
              {"map": map_id, "seats": seats, "tower": 0},
              expect={"all": ["EV round_started round=1 guard=s0"], "host": ["RIFLE fired by=s0"],
                      "never": ["EV race_started"]})
        match(f"open_clientguard_{peers}p_{map_name}", peers, 75, ["opening", "guard"],
              {"map": map_id, "seats": seats, "tower": 1},
              expect={"all": ["EV round_started round=1 guard=s1"], "host": ["RIFLE fired by=s1"],
                      "never": ["EV race_started"]})
        match(f"open_brawl_{peers}p_{map_name}", peers, 90, ["opening", "brawl"],
              {"map": map_id, "seats": seats, "tower": -1}, host={"brawl": True},
              expect={"all": ["EV brawl_started", "EV round_started round=1"]})

# --- C. Powers: each key, pressed by the host and by clients, watched by a third peer ---
# name: (the host's power, or None to leave the picks, host keys). The client holds the next power round.
POWER_KEYS = {
    "shield": (1, "q@6/11"),
    "hologram": (2, "q@6/11"),
    "armorlock_hold": (3, "q@6+2.5/9"),
    "armorlock_tap": (3, "q@6/6"),
    "camo": (4, "q@6/11"),
    "cat_cook": (5, "q@6,e@>1,q@>6,e@>1,q@>6,e@>1"),
    "cat_throw": (5, "q@6,f@>1.2,q@>6,f@>1.2,q@>6,f@>1.2"),
    "cat_hold": (5, "q@6"),
    "emotes": (None, "b@6+2,n@12+2,b@18+2,n@24+2"),
    "shove": (None, "f@5/2"),
}
# The client's keys for the power it holds there, two seconds behind the host's.
CLIENT_KEYS = {1: "q@9/11", 2: "q@9/11", 3: "q@8+2.5/9", 4: "q@9/11", 5: "q@8,e@>1,q@>6,f@>1.2,q@>6,e@>1"}
EMOTE_SHOVE_CLIENT = {"emotes": "n@7+2,b@13+2,n@19+2,b@25+2", "shove": "f@6/2"}


def next_power(power: int) -> int:
    return power % 5 + 1


# The tower is held by a human who never fires, so the pressers stay on the track and every press counts.
SILENT = {"aim": False, "fire-every": 0, "press-fire": 0, "keys": ""}
for map_name, map_id in MAPS.items():
    for power, (held, host_keys) in POWER_KEYS.items():
        if held is None:
            host, client_keys = {"keys": host_keys}, EMOTE_SHOVE_CLIENT[power]
        else:
            host, client_keys = {"keys": host_keys, "ability": f"{held},{next_power(held)}"}, CLIENT_KEYS[next_power(held)]
        match(f"power_{power}_3p_{map_name}", 3, 60, ["powers"], {"map": map_id, "seats": 4, "tower": 2},
              host=host, peer={"1": {"keys": client_keys}, "2": SILENT},
              expect={"valid_presses": {"0": 1, "1": 1}})
    for ability in (1, 2, 3, 4, 5):
        match(f"power_q_ability{ability}_3p_{map_name}", 3, 45, ["powers"], {"map": map_id, "seats": 4, "tower": 2},
              host={"keys": "q@6+1.5/9", "ability": f"{ability},{next_power(ability)}"},
              peer={"1": {"keys": "q@8+1.5/9"}, "2": SILENT},
              expect={"valid_presses": {"0": 1, "1": 1}})
    host, _ = mixed((5, 2))
    match(f"power_all_2p_{map_name}_hostkeys", 2, 70, ["powers"], {"map": map_id, "seats": 4, "tower": 1},
          host=host, peer={"1": SILENT}, expect={"valid_presses": {"0": 3}})
    match(f"power_all_2p_{map_name}_clientkeys", 2, 70, ["powers"], {"map": map_id, "seats": 4, "tower": 0},
          host=dict(SILENT, ability="3,5"), peer={"1": {"keys": life_keys(5, 2.0)}}, expect={"valid_presses": {"1": 3}})
    for peers, powers in ((3, (5, 2, 4)), (4, (5, 2, 3, 1))):
        host, keyed = mixed(powers)
        keyed[str(peers - 1)] = SILENT
        match(f"power_all_{peers}p_{map_name}", peers, 70, ["powers", "smoke"] if (peers, map_name) == (3, "hell") else ["powers"],
              {"map": map_id, "seats": peers + 1, "tower": peers - 1}, host=host, peer=keyed,
              expect={"valid_presses": {str(i): 3 for i in range(peers - 1)}})
    # The same keys under a bot guard that shoots: the hologram's decoy and the cat against a live rifle.
    host, keyed = mixed((2, 5, 3))
    match(f"power_all_botguard_3p_{map_name}", 3, 70, ["powers"], {"map": map_id, "seats": 4, "tower": 3}, host=host, peer=keyed)
    # A human guard holding a power presses it anyway (no waiting for a valid moment): the host refuses every one.
    match(f"power_guard_presses_3p_{map_name}", 3, 45, ["powers", "roles"], {"map": map_id, "seats": 4, "tower": 1},
          host={"ability": "5,3,2"}, peer={"1": {"keys": "q@6,q@12+2,q@18,e@>1", "keys-wait": False}},
          expect={"ruled_role_presses": {"1": 2}})
HUB_KEYS = {5: "q@4,e@>1,q@21,f@>1.2,b@33+2,n@38+2,q@43,e@>1", 2: "q@4,f@>1.2,b@14+2,n@19+2,q@24,q@40",
            3: "q@5+2,f@>1.2,b@14+2,n@19+2,q@24+2,q@40"}
for peers in (2, 3):
    powers = (5, 2, 3)[:peers]
    hub(f"power_hub_{peers}p", peers, 150, ["powers", "hub"],
        {"maps": "bentham_ring", "matches": 1, "win": 8, "hub-wait": 50},
        host={"prisoners": 3, "ability": ",".join(str(p) for p in powers), "hub-keys": HUB_KEYS[5]},
        peer={str(i): {"hub-keys": HUB_KEYS[p]} for i, p in enumerate(powers) if i > 0}, expect={"matches": 1})

# --- D. Ghosts on and off ------------------------------------------------------
for map_name, map_id in MAPS.items():
    for peers in (3, 4):
        match(f"ghosts_on_{peers}p_{map_name}", peers, 100, ["ghosts"], {"map": map_id, "seats": peers + 1, "tower": 1},
              host={"ghosts": "true"}, expect={"host": ["EV ghosted", "EV ghost_respawned"]})
        match(f"ghosts_off_{peers}p_{map_name}", peers, 100, ["ghosts"], {"map": map_id, "seats": peers + 1, "tower": 1},
              host={"ghosts": "false"}, expect={"host": ["EV converted"], "never": ["EV ghosted"]})
    match(f"lives3_3p_{map_name}", 3, 80, ["ghosts"], {"map": map_id, "seats": 4, "tower": 1},
          host={"lives": 3, "ghosts": "true"})

# --- E. After the result: rematch, everyone to the hub, back alone, relaunch ----
for peers in (2, 3, 4):
    hub(f"rematch_{peers}p_hell", peers, 200, ["after"], {"maps": "bentham_ring", "matches": 1, "win": 18, "rematches": 2},
        host={"prisoners": 3}, expect={"matches": 1, "all": ["REMATCH pressed left=0"], "never": ["REMATCH gave up"]})
hub("rematch_3p_marble", 3, 200, ["after"], {"maps": "marble", "matches": 1, "win": 18, "rematches": 2},
    host={"prisoners": 3}, expect={"matches": 1, "all": ["REMATCH pressed left=0"], "never": ["REMATCH gave up"]})
# One human never presses Rematch: the rest wait, the host gives up and takes everyone to the hub.
hub("rematch_one_abstains_3p", 3, 130, ["after"], {"maps": "bentham_ring", "matches": 1, "win": 15, "rematches": 1, "rematch-wait": 10},
    host={"prisoners": 3}, peer={"2": {"rematches": 0}},
    expect={"matches": 1, "host": ["REMATCH gave up"]})
hub("back_client_first_3p", 3, 160, ["after"], {"maps": "bentham_ring,marble", "matches": 2, "win": 15, "after": "back"},
    host={"prisoners": 3, "back": 7}, client={"back": 1}, expect={"matches": 2, "scene_split": True})
hub("back_host_first_3p", 3, 160, ["after"], {"maps": "bentham_ring,marble", "matches": 2, "win": 15, "after": "back"},
    host={"prisoners": 3, "back": 1}, client={"back": 6}, expect={"matches": 2, "scene_split": True})
for peers in (2, 3, 4):
    hub(f"hub_loop_{peers}p", peers, 330, ["after", "transitions"],
        {"maps": "bentham_ring,marble,marble,bentham_ring,bentham_ring,marble", "matches": 6, "win": 12, "back": 2, "hub-wait": 3},
        host={"prisoners": 3}, expect={"matches": 6})
hub("relaunch_bots_3p", 3, 200, ["after", "relaunch"],
    {"maps": "bentham_ring", "matches": 4, "win": 12, "back": 2}, host={"prisoners": 3, "relaunch-bots": "3,1,0"},
    expect={"matches": 4})
hub("relaunch_seats_2p", 2, 160, ["after", "relaunch"],
    {"maps": "marble", "matches": 2, "win": 12, "back": 2},
    host={"prisoners": 3, "relaunch-bots": "2", "relaunch-seats": "2,5", "relaunch-tower": 1},
    expect={"matches": 2})
hub("hub_shove_3p", 3, 120, ["hub"], {"maps": "bentham_ring", "matches": 1, "win": 8, "hub-wait": 30},
    host={"prisoners": 3, "shove-at": 6}, expect={"matches": 1, "host": ["EV shoved shover=s0"]})

# --- F. Wire faults ------------------------------------------------------------
FAULTS = {
    "loss10": {"loss": 0.1},
    "loss20": {"loss": 0.2},
    "delay50": {"delay-ms": 50},
    "delay120": {"delay-ms": 120},
    "loss10_delay50": {"loss": 0.1, "delay-ms": 50},
}
# Three humans holding three different powers, the cat always among them, the partners rotating.
MIXES = [(2, 5, 3), (5, 2, 4), (1, 5, 2), (5, 3, 1), (4, 2, 5), (5, 1, 2), (3, 5, 4), (2, 4, 5), (5, 2, 1)]
for map_name, map_id in MAPS.items():
    for n, (fault, flags) in enumerate(FAULTS.items()):
        common = {"map": map_id, "seats": 4, "tower": 3}
        common.update(flags)
        host, keyed = mixed(MIXES[n % len(MIXES)])
        match(f"fault_{fault}_3p_{map_name}", 3, 70, ["fault"], common, host=host, peer=keyed)
    match(f"fault_loss10_delay50_clientguard_3p_{map_name}", 3, 75, ["fault", "guard"],
          {"map": map_id, "seats": 4, "tower": 1, "loss": 0.1, "delay-ms": 50},
          expect={"host": ["RIFLE fired by=s1"]})
    for who, index in (("client", "1"), ("host", "0")):
        match(f"fault_stall3s_{who}_2p_{map_name}", 2, 60, ["fault", "stall"], {"map": map_id, "seats": 4, "tower": 3},
              peer={index: {"stall-at": 15, "stall-ms": 3000}},
              expect={"never": ["SEAT seat=s1 occupancy=BOT"]})
        match(f"fault_binddelay_{who}_3p_{map_name}", 3, 110, ["fault", "bind"], {"map": map_id, "seats": 4, "tower": -1},
              peer={index: {"bind-delay": 2.0}},
              expect={"all": ["EV round_started round=1"]}, limit_extra=5)
    match(f"fault_stall7s_client_2p_{map_name}", 2, 60, ["fault", "stall"], {"map": map_id, "seats": 4, "tower": 3},
          peer={"1": {"stall-at": 15, "stall-ms": 7000}},
          expect={"never": ["SEAT seat=s1 occupancy=BOT"]})
    # Silent past NetSettings.peer_timeout_seconds (8 s) mid-match is a dead line to everyone else, just past it
    # or long past it: the host seats a bot, and the client is told it was dropped the moment it wakes.
    for seconds, length in ((10, 60), (25, 75)):
        match(f"fault_stall{seconds}s_client_2p_{map_name}", 2, length, ["fault", "stall"], {"map": map_id, "seats": 4, "tower": 3},
              peer={"1": {"stall-at": 15, "stall-ms": seconds * 1000}},
              expect={"host": ["SEAT seat=s1 occupancy=BOT"], "host_lost": "in-match", "seat_to_bot": [1]})
    # Frozen 12 s while STANDING: the host's own rule lets it go, and the client never drops the host.
    match(f"fault_stall12s_client_2p_{map_name}", 2, 60, ["fault", "stall"], {"map": map_id, "seats": 4, "tower": 3},
          peer={"1": {"stall-at": 15, "stall-ms": 12000}},
          expect={"host": ["SEAT seat=s1 occupancy=BOT", "TIMEOUT peer=[0-9]+ state=STANDING"], "host_lost": "in-match",
                  "seat_to_bot": [1], "never": ["TIMEOUT peer=1 state"]})

# --- F2. The conditions the netcode design claims to survive (DESIGN.md Phase T) -----
# Each mode alone, then the design's own line: 80 ms one way, 20 ms of jitter, 2% held back. Jitter here
# remembers itself for 200 ms (a queue filling and draining), except "jitteriid": fresh per packet, in order.
# Below ENet (tools/net/wire_relay.gd), as on a real line, except the "_peer" pair: the same reordering and
# duplication above the transport, which is what a transport without sequencing (Steam) hands the game.
SOCKET = {"wire-layer": "socket"}
WIRE_MODES = {
    "jitter20u": dict(SOCKET, **{"delay-ms": 40, "jitter-ms": 20, "jitter-tau-ms": 200}),
    "jitter20n": dict(SOCKET, **{"delay-ms": 40, "jitter-ms": 20, "jitter-dist": "normal", "jitter-tau-ms": 200}),
    "jitteriid": dict(SOCKET, **{"delay-ms": 40, "jitter-ms": 15}),
    "reorder5": dict(SOCKET, **{"delay-ms": 30, "reorder": 0.05, "reorder-ms": 100}),
    "dup10": dict(SOCKET, **{"delay-ms": 20, "dup": 0.1}),
    "burst5": dict(SOCKET, **{"burst-ms": 150, "burst-gap-ms": 2850}),
    "wan80": dict(SOCKET, **{"delay-ms": 80, "jitter-ms": 20, "jitter-tau-ms": 200, "reorder": 0.02, "reorder-ms": 60}),
    "reorder5_peer": {"delay-ms": 30, "reorder": 0.05, "reorder-ms": 100},
    "dup10_peer": {"delay-ms": 20, "dup": 0.1},
}
for map_name, map_id in MAPS.items():
    for n, (mode, flags) in enumerate(WIRE_MODES.items()):
        common = {"map": map_id, "seats": 4, "tower": 3}
        common.update(flags)
        host, keyed = mixed(MIXES[n % len(MIXES)])
        match(f"fault_{mode}_3p_{map_name}", 3, 70, ["fault", "wire"], common, host=host, peer=keyed)
    # A machine that hitches the way a first-time shader compile or a debugger break does.
    for who, index in (("client", "1"), ("host", "0")):
        match(f"fault_hitches_{who}_2p_{map_name}", 2, 60, ["fault", "stall"], {"map": map_id, "seats": 4, "tower": 3},
              peer={index: {"freeze": "match@10+300,match@18+300,match@26+600,match@34+1000"}},
              expect={"never": ["SEAT seat=s1 occupancy=BOT"]})
for who, index in (("client", "1"), ("host", "0")):
    hub(f"fault_freeze3s_hub_{who}_3p", 3, 150, ["fault", "stall", "hub"],
        {"maps": "bentham_ring", "matches": 1, "win": 15, "hub-wait": 14},
        host={"prisoners": 3}, peer={index: {"freeze": "hub@5+3000"}}, expect={"matches": 1})

# --- F3. Jumps: every peer jumping all match, its brain's own ledge and pad jumps around them -----
# Hell's route has jump links and boost pads, marble's has neither. The tower is a human who never fires,
# so both jumpers stay on the track all match.
JUMP_WIRES = {
    "clean": {},
    "loss10": {"loss": 0.1},
    "delay50": {"delay-ms": 50},
    "jitter20n": WIRE_MODES["jitter20n"],
}
for map_name, map_id in MAPS.items():
    for wire, flags in JUMP_WIRES.items():
        common = {"map": map_id, "seats": 4, "tower": 2}
        common.update(flags)
        match(f"jump_{wire}_3p_{map_name}", 3, 60, ["jump", "fault"] if flags else ["jump"], common,
              host={"keys": "j@5/1.7"}, peer={"1": {"keys": "j@6/1.5"}, "2": SILENT},
              expect={"valid_presses": {"0": 10, "1": 10}})

# --- G. Leavers ----------------------------------------------------------------
for map_name, map_id in MAPS.items():
    match(f"quit_client_leave_round_3p_{map_name}", 3, 60, ["leave"], {"map": map_id, "seats": 4, "tower": 3},
          peer={"1": {"quit-at": 15}}, expect={"host": ["SEAT seat=s1 occupancy=BOT"], "seat_to_bot": [1]})
    match(f"quit_client_killed_round_3p_{map_name}", 3, 60, ["leave"], {"map": map_id, "seats": 4, "tower": 3},
          kill=[{"peer": 1, "when": "EV round_started", "after": 12}],
          expect={"host": ["SEAT seat=s1 occupancy=BOT"], "seat_to_bot": [1]})
    match(f"quit_clientguard_leave_3p_{map_name}", 3, 60, ["leave", "guard"], {"map": map_id, "seats": 4, "tower": 1},
          peer={"1": {"quit-at": 15}}, expect={"host": ["SEAT seat=s1 occupancy=BOT"], "seat_to_bot": [1]})
    match(f"quit_client_launching_3p_{map_name}", 3, 50, ["leave"], {"map": map_id, "seats": 4, "tower": 3},
          kill=[{"peer": 1, "when": "LOBBY phase=IN_MATCH", "after": 0}],
          expect={"host": ["SEAT seat=s1 occupancy=BOT"], "seat_to_bot": [1]})
    match(f"quit_host_leave_round_3p_{map_name}", 3, 60, ["leave", "host"], {"map": map_id, "seats": 4, "tower": 3},
          peer={"0": {"quit-at": 15}}, expect={"host_lost": "in-match"})
    match(f"quit_host_killed_round_3p_{map_name}", 3, 60, ["leave", "host"], {"map": map_id, "seats": 4, "tower": 3},
          kill=[{"peer": 0, "when": "EV round_started", "after": 12}], expect={"host_lost": "in-match"}, limit_extra=15)
hub("quit_client_in_hub_3p", 3, 150, ["leave", "hub"], {"maps": "bentham_ring", "matches": 1, "win": 15, "hub-wait": 26},
    host={"prisoners": 3}, kill=[{"peer": 2, "when": "SCENE kind=hub", "after": 6}], expect={"matches": 1})
# Killed in the hub and not yet timed out when the host starts: a dead peer in a seat at launch.
hub("quit_client_dead_at_launch_3p", 3, 150, ["leave", "hub"], {"maps": "marble", "matches": 1, "win": 20, "hub-wait": 9},
    host={"prisoners": 3}, kill=[{"peer": 2, "when": "SCENE kind=hub", "after": 6}], expect={"matches": 1})
hub("quit_host_in_hub_3p", 3, 90, ["leave", "host", "hub"], {"maps": "bentham_ring", "matches": 1, "win": 15, "hub-wait": 30},
    kill=[{"peer": 0, "when": "SCENE kind=hub", "after": 8}], expect={"host_lost": True})
hub("quit_host_at_result_3p", 3, 120, ["leave", "host"], {"maps": "marble", "matches": 1, "win": 12, "back": 30},
    host={"prisoners": 3}, kill=[{"peer": 0, "when": "RESULT showing=1", "after": 3}], expect={"host_lost": "in-match"})
hub("quit_client_midmatch_hubflow_4p", 4, 200, ["leave"], {"maps": "bentham_ring,marble", "matches": 2, "win": 25},
    host={"prisoners": 3}, peer={"2": {"quit-at": 10, "quit-match": 1}},
    expect={"matches": 2, "host": ["SEAT seat=s2 occupancy=BOT"], "seat_to_bot": [2]})

# --- H. The finale from both seats ---------------------------------------------
# The guard here keeps the scope down: a round it won by shooting would never reach the finale under test.
HOLDS_FIRE = {"aim": False, "fire-every": 0, "press-fire": 0}
for map_name, map_id in MAPS.items():
    match(f"finale_client_finisher_hostguard_3p_{map_name}", 3, 60, ["finale", "guard"], {"map": map_id, "seats": 4, "tower": 0},
          host=dict(HOLDS_FIRE, **{"arm-finisher": 10}),
          expect={"host": ["EV finisher seat=s"], "all": ["EV kill_beat guard=s0", "EV round_started round=2"]})
    match(f"finale_host_finisher_clientguard_3p_{map_name}", 3, 60, ["finale", "guard"], {"map": map_id, "seats": 4, "tower": 1},
          host={"arm-finisher": 10, "arm-host": True}, peer={"1": HOLDS_FIRE},
          expect={"host": ["EV finisher seat=s0"], "all": ["EV kill_beat guard=s1", "EV round_started round=2 guard=s0"]})


def main() -> None:
    OUT.mkdir(exist_ok=True)
    for stale in OUT.glob("*.json"):
        stale.unlink()
    names = set()
    for scenario in scenarios:
        assert scenario["name"] not in names, scenario["name"]
        names.add(scenario["name"])
        (OUT / f"{scenario['name']}.json").write_text(json.dumps(scenario, indent=1) + "\n")
    print(f"{len(scenarios)} scenarios in {OUT}")


if __name__ == "__main__":
    main()
