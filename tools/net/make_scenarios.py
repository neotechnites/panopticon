#!/usr/bin/env python3
"""Write the scenario matrix into tools/net/scenarios/. The files are committed; rerun after editing this.

    python3 tools/net/make_scenarios.py

Axes: peers 2/3/4 x hell/marble x opening (race, named guard on the host, on a client, on a bot,
tower fight) x each power key x ghosts on/off x rematch / hub return / relaunch, the wire faults
(loss, delay, stall, bind delay) and the two leavers (a client, the host).
"""

from __future__ import annotations

import json
from pathlib import Path

OUT = Path(__file__).resolve().parent / "scenarios"
MAPS = {"hell": "bentham_ring", "marble": "marble"}
# Every key the game reads, in one life: powers 1-4, the cat cooked, the picked power on Q, both emotes.
ALL_KEYS = "1@5,2@12,3@19+2,4@24,5@31,e@>1,b@37+2,n@42+2,q@47"
ALL_KEYS_LATE = "2@7,1@14,4@21,3@27+2,5@33,f@>1.2,n@39+2,b@44+2,q@49"

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
hub("flow_4p_hell_marble_keys", 4, 520, ["flow", "powers"],
    {"maps": "bentham_ring,marble", "matches": 2, "ceiling": 200, "hub_seconds": 6, "keys": ALL_KEYS},
    host={"prisoners": 4, "rounds": 1, "ability": 1},
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
POWER_KEYS = {
    "shield": ("1@6/11", "1@9/11"),
    "hologram": ("2@6/11", "2@9/11"),
    "armorlock_hold": ("3@6+2.5/9", "3@8+2.5/9"),
    "armorlock_tap": ("3@6/6", "3@8/6"),
    "camo": ("4@6/11", "4@9/11"),
    "cat_cook": ("5@6,e@>1,5@>6,e@>1,5@>6,e@>1", "5@8,e@>1,5@>6,e@>1,5@>6,e@>1"),
    "cat_throw": ("5@6,f@>1.2,5@>6,f@>1.2,5@>6,f@>1.2", "5@8,f@>1.2,5@>6,f@>1.2,5@>6,f@>1.2"),
    "cat_hold": ("5@6", "5@8"),
    "emotes": ("b@6+2,n@12+2,b@18+2,n@24+2", "n@7+2,b@13+2,n@19+2,b@25+2"),
    "shove": ("f@5/2", "f@6/2"),
}
# The tower is held by a human who never fires, so the pressers stay on the track and every press counts.
SILENT = {"aim": False, "fire-every": 0, "press-fire": 0, "keys": ""}
for map_name, map_id in MAPS.items():
    for power, (host_keys, client_keys) in POWER_KEYS.items():
        match(f"power_{power}_3p_{map_name}", 3, 60, ["powers"], {"map": map_id, "seats": 4, "tower": 2},
              host={"keys": host_keys}, peer={"1": {"keys": client_keys}, "2": SILENT},
              expect={"valid_presses": {"0": 1, "1": 1}})
    for ability in (1, 2, 3, 4, 5):
        match(f"power_q_ability{ability}_3p_{map_name}", 3, 45, ["powers"], {"map": map_id, "seats": 4, "tower": 2},
              host={"keys": "q@6+1.5/9", "ability": ability}, peer={"1": {"keys": "q@8+1.5/9"}, "2": SILENT},
              expect={"valid_presses": {"0": 1, "1": 1}})
    match(f"power_all_2p_{map_name}_hostkeys", 2, 70, ["powers"], {"map": map_id, "seats": 4, "tower": 1},
          host={"keys": ALL_KEYS, "ability": 4}, peer={"1": SILENT}, expect={"valid_presses": {"0": 3}})
    match(f"power_all_2p_{map_name}_clientkeys", 2, 70, ["powers"], {"map": map_id, "seats": 4, "tower": 0},
          host=dict(SILENT, ability=4), peer={"1": {"keys": ALL_KEYS_LATE}}, expect={"valid_presses": {"1": 3}})
    for peers in (3, 4):
        match(f"power_all_{peers}p_{map_name}", peers, 70, ["powers", "smoke"] if (peers, map_name) == (3, "hell") else ["powers"],
              {"map": map_id, "seats": peers + 1, "tower": peers - 1},
              host={"keys": ALL_KEYS, "ability": 4}, client={"keys": ALL_KEYS_LATE}, peer={str(peers - 1): SILENT},
              expect={"valid_presses": {str(i): 3 for i in range(peers - 1)}})
    # The same keys under a bot guard that shoots: shield, lock and camo against a live rifle.
    match(f"power_all_botguard_3p_{map_name}", 3, 70, ["powers"], {"map": map_id, "seats": 4, "tower": 3},
          host={"keys": ALL_KEYS, "ability": 4}, client={"keys": ALL_KEYS_LATE})
    # Powers a human guard and a ghost should not have, pressed anyway (no waiting for a valid moment).
    match(f"power_guard_presses_3p_{map_name}", 3, 45, ["powers", "roles"], {"map": map_id, "seats": 4, "tower": 1},
          peer={"1": {"keys": "1@6,3@12+2,5@18,e@>1", "keys-wait": False}})
for peers in (2, 3):
    hub(f"power_hub_{peers}p", peers, 150, ["powers", "hub"],
        {"maps": "bentham_ring", "matches": 1, "win": 8, "hub-wait": 50,
         "hub-keys": "1@4,2@10,3@16+2,4@21,5@27,e@>1,b@33+2,n@38+2,5@43,f@>1.2"},
        host={"prisoners": 3}, expect={"matches": 1})

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
for map_name, map_id in MAPS.items():
    for fault, flags in FAULTS.items():
        common = {"map": map_id, "seats": 4, "tower": 3}
        common.update(flags)
        match(f"fault_{fault}_3p_{map_name}", 3, 70, ["fault"], common,
              host={"keys": ALL_KEYS, "ability": 2}, client={"keys": ALL_KEYS_LATE})
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
