# AI Planning Group — Integration TL;DR

Everything the AI side needs to drive the Core. Three transport options, one
imperative API, one reactive API, one state feed back.

---

## Connect

We host an **ENet server on `127.0.0.1:12345`** the moment the game starts
(Networking autoload, [Logic/multiplayer/network.gd](../Logic/multiplayer/network.gd)).
Host peer id is always `1`. The AI peer connects as a client and calls
`Networking.rpc_id(1, "<name>", …)`.

For RPC routing to work both peers need a node at `/root/Networking` with
**matching `@rpc` signatures**. Easiest: ship a stub script with the same
function names + parameter types and autoload it as `Networking` on the AI
side.

We *also* run an HTTP listener on `127.0.0.1:8085`
([Logic/PlanReceiver.gd](../Logic/PlanReceiver.gd)) for plan-push
notifications — see `Path B` below.

---

## Two layers of commands

### 1. Imperative — "do this once"

One RPC per command. Fire-and-forget; ownership is checked. All take the
acting `unit_id` (use `entity_id`, not Godot's `get_instance_id`) and the
requesting `pid` last.

| RPC | What it does |
|---|---|
| `ai_move_unit(uid, x, y, pid)` | Pathfind to (x, y) |
| `ai_attack_move(uid, x, y, pid)` | Move to (x, y), auto-engage hostiles found on the way |
| `ai_chop_nearest_tree(uid, pid)` | Closest tree → harvest |
| `ai_chop_nearest_and_return(uid, pid)` | Closest tree → harvest → walk back to base, idle |
| `ai_mine_nearest_stone(uid, pid)` | Closest stone → harvest |
| `ai_attack_nearest(uid, pid)` | Closest hostile → chase + attack (gets +25 % initiative bonus) |
| `ai_construct(uid, scene_path, x, y, dur, pid)` | Walk to (x, y), build the scene (e.g. `"res://Houses/Barracks.tscn"`) |
| `ai_explode_at(uid, x, y, radius, dmg, pid)` | AoE strike at (x, y) with linear falloff |
| `ai_chop_tree(uid, tree_id, pid)` | Specific tree by `entity_id` |
| `ai_mine_stone(uid, stone_id, pid)` | Specific stone by `entity_id` |
| `ai_attack_target(uid, target_id, pid)` | Specific target by `entity_id` |
| `ai_execute_plan(plan_dict)` | A batch — see schema below |

### 2. Reactive — "keep doing this until X changes"

One call per unit, rules are persistent and re-evaluated **every tick**
(2 Hz). The planner ([Logic/BehaviorPlanner.gd](../Logic/BehaviorPlanner.gd))
picks the highest-priority rule whose predicate is currently true and
dispatches it. Re-dispatching only happens when the *chosen rule changes* —
combat won't restart itself every tick.

```gdscript
Networking.rpc_id(1, "ai_set_behavior", unit_id, [
    {"when": "enemy_within(100)", "do": "ATTACK_NEAREST",          "priority": 100},
    {"when": "wood > stone",      "do": "MINE_NEAREST",            "priority":  60},
    {"when": "stone > wood",      "do": "CHOP_NEAREST_AND_RETURN", "priority":  60},
    {"when": "idle",              "do": "CHOP_NEAREST_AND_RETURN", "priority":  10},
], pid)

Networking.rpc_id(1, "ai_clear_behavior", unit_id, pid)
```

#### Predicates
| Syntax | Meaning |
|---|---|
| `true` / `always` | Always true (use as fallback) |
| `idle` / `busy` | Unit has no current action / has one |
| `enemy_within(<dist>)` | Closest hostile is ≤ dist px |
| `no_enemy_within(<dist>)` | … is > dist px |
| `wood > stone`, `stone > wood` | Player stockpile comparison |
| `wood >= <n>`, `stone < <n>`, `hp <= <n>`, `max_hp == <n>`, … | Threshold checks on `wood` / `stone` / `hp` / `max_hp` using `>`, `<`, `>=`, `<=`, `==` |
| `hp_below(<frac>)` / `hp_above(<frac>)` | HP as a fraction of max (0.0 – 1.0) |

#### Actions (the rule's `do` field)
`MOVE`, `ATTACK_MOVE`, `CHOP_NEAREST`, `CHOP_NEAREST_AND_RETURN`,
`MINE_NEAREST`, `ATTACK_NEAREST`, `CONSTRUCT`, `EXPLODE`, `NONE`.

`args` (optional dict) carries action-specific parameters when needed —
same shape as the plan dict below:
- `MOVE` / `ATTACK_MOVE` → `{"target": {"x": n, "y": n}}`
- `CONSTRUCT` → `{"scene": "...", "x": n, "y": n, "duration": n}`
- `EXPLODE` → `{"target": {"x": n, "y": n}, "radius": n, "damage": n}`

---

## The plan dict (`ai_execute_plan`)

Carries both imperative `commands` and reactive `behaviors` in one shot.
Behaviors arm *before* commands fire.

```jsonc
{
  "plan_id": "ai-1",
  "player_id": 0,
  "commands": [
    {"unit_id": 1, "action": "MOVE",         "target": {"x": 600, "y": 400}},
    {"unit_id": 1, "action": "CHOP_NEAREST"},
    {"unit_id": 2, "action": "MINE_NEAREST"},
    {"unit_id": 3, "action": "ATTACK_NEAREST"},
    {"unit_id": 1, "action": "CONSTRUCT",
                   "scene": "res://Houses/Barracks.tscn",
                   "position": {"x": 700, "y": 500}, "duration": 10},
    {"unit_id": 1, "action": "EXPLODE",
                   "target": {"x": 500, "y": 300},
                   "radius": 90, "damage": 25}
  ],
  "behaviors": [
    {"unit_id": 1, "rules": [
      {"when": "enemy_within(120)", "do": "ATTACK_NEAREST",          "priority": 100},
      {"when": "wood > stone",      "do": "MINE_NEAREST",            "priority":  60},
      {"when": "idle",              "do": "CHOP_NEAREST_AND_RETURN", "priority":  10}
    ]}
  ]
}
```

Send via `Networking.rpc_id(1, "ai_execute_plan", plan)`.

Plan-string action vocabulary inside `commands`:
`MOVE`, `HARVEST`, `CHOP_AND_RETURN`, `CONSTRUCT`, `ATTACK`, `ATTACK_MOVE`,
`CHOP_NEAREST`, `MINE_NEAREST`, `ATTACK_NEAREST`, `CHOP_NEAREST_AND_RETURN`,
`EXPLODE`.

---

## State flowing back to the AI

### Push every tick (2 Hz)
Host calls `rpc("receive_state", gzip_compressed_json)` to all peers. After
decompress + JSON parse:

```jsonc
{
  "current_tick": 47,
  "units": [
    {"meta_values": {"entity_id": 1, "max_health": 100, "player_id": 0,
                     "position": {"x": 433, "y": 499}},
     "path": [...],   // packed Vector2 array of upcoming waypoints
     "speed": 3000}
  ],
  "modified_objects": [
    {"meta_values": {...}, "destroyed": true, "amount_left": 0}
  ]
}
```

### Static map on demand
AI peer calls `rpc_id(1, "on_static_state_requested")`. Host replies with
`receive_static_state(gzip_compressed_json)` containing `units`, `objects`
(resources), and `map` (tiles + terrain types: `PLAINS`, `FOREST`, `HILLS`,
`WATER`).

### Signals (relayed by ActionGateway)
Connect on the host if you're in-process; over the wire they're not yet
relayed — the state push is the canonical feedback channel.
- `task_completed(unit_id, action_data)` — a single action finished OK
- `task_failed(unit_id, action_data)` — action could not complete
- `unit_idled(unit_id)` — queue drained, unit is free
- `plan_execution_finished(plan_id)` — all commands in a plan dispatched

---

## Path B — HTTP plan-push

Useful if the planner is an out-of-process service (Python, etc).

1. AI POSTs to `http://127.0.0.1:8085`:
   ```json
   {"game_id": "g1", "player_id": "0", "unit_ids": ["1", "2"]}
   ```
2. Host responds `200 OK` then **calls the AI back** at
   `http://127.0.0.1:5000/plan/g1/0?unitIds=1,2` (planner endpoint).
3. AI returns:
   ```json
   {"unit_plans": [
     {"unit_id": "1", "steps": [
       {"action_type": "MoveTo",  "parameters": {"x": 600, "y": 400}},
       {"action_type": "Harvest", "parameters": {"resource_type": "tree"}}
     ]}
   ]}
   ```
4. Host loops the steps: when a unit emits `unit_idled` it advances to the
   next step and dispatches it through ActionGateway. So you can ship a
   compact step list and we'll auto-cycle.

Supported `action_type` values on the HTTP path: `MoveTo`, `Harvest`
(optionally `{"resource_type": "tree" | "stone"}`), `Construct`.

---

## Gotchas

| Symptom | Almost always means |
|---|---|
| `[OWNERSHIP_ERR] Player X attempted to command unit Y owned by player Z` | `pid` doesn't match the unit's `player_id`. Use the `player_id` we send in the state push. |
| Connected fine but RPC has no effect on the host | Node-path mismatch. Both peers need a node at `/root/Networking` with `@rpc` decorators whose names + parameter types match exactly. |
| `Unit -1 not found` | You're sending `get_instance_id()`. Use `entity_id` from the state push. |
| Plan accepted but nothing moves | Action-string typo. Allowed values listed above; anything else logs `Unknown action 'X'`. |
| Unit just paces at the shoreline | That was a bug in earlier builds. Fixed since `47d2978` — chase uses the NavigationAgent and bails out with `target unreachable` if there's no land path. |
| Reactive rule fires every tick but unit makes no progress | The unit owns its action queue. The planner only re-dispatches on rule *change*, but the rule it dispatches still executes normally. If the action itself is failing, watch for `[CMD_FAILED]` / `[COMBAT_LOG] … no hostiles` in the host console. |

---

## Smoke test (10 seconds)

On the host (Godot editor) with the game running:

```gdscript
# in any Output / debugger eval slot
ActionGateway.set_behavior_plan(1, [
    {"when": "enemy_within(100)", "do": "ATTACK_NEAREST",          "priority": 100},
    {"when": "wood > stone",      "do": "MINE_NEAREST",            "priority":  60},
    {"when": "idle",              "do": "CHOP_NEAREST_AND_RETURN", "priority":  10},
], 0)
```

Watch the console for `[BEHAVIOR] Unit 1 → '<action>' (rule N, priority M)`
lines each time the planner re-decides. Open the F1 Debug Window to confirm
HP, stockpile, current action, etc.

---

## Quick reference — file map

| Purpose | File |
|---|---|
| Imperative gateway | [Logic/ActionGateway.gd](../Logic/ActionGateway.gd) |
| Reactive planner | [Logic/BehaviorPlanner.gd](../Logic/BehaviorPlanner.gd) |
| Server / RPCs | [Logic/multiplayer/network.gd](../Logic/multiplayer/network.gd) |
| HTTP plan-push | [Logic/PlanReceiver.gd](../Logic/PlanReceiver.gd) |
| Read-only world state | [Logic/SenseAPI.gd](../Logic/SenseAPI.gd) |
| Tick driver (2 Hz) | [Logic/TickManager.gd](../Logic/TickManager.gd) |
| Fog of war (per-player) | [Entities/Map/FogOfWar.gd](../Entities/Map/FogOfWar.gd) — autoloaded as `FogManager` |
