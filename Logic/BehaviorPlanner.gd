extends Node

## -----------------------------------------------------------------------
## BehaviorPlanner  (autoload)
##
## Lets the AI Planning team submit a REACTIVE plan: a list of
## (when, do) rules per unit.  Every TickManager tick the planner
## evaluates every rule and re-dispatches the highest-priority match
## via the ActionGateway.
##
##   set_behavior(unit_id, [
##       {"when": "enemy_within(100)", "do": "ATTACK_NEAREST", "priority": 100},
##       {"when": "wood > stone",      "do": "MINE_NEAREST",   "priority":  60},
##       {"when": "idle",              "do": "CHOP_NEAREST_AND_RETURN",
##        "priority": 10},
##   ], pid)
##
## A rule fires only when its predicate evaluates to true.  Among
## currently-true rules the highest `priority` wins.  Re-dispatching only
## happens when the chosen rule *changes* — so combat doesn't restart
## itself every tick, and chop doesn't restart while the worker is still
## walking back to base.
## -----------------------------------------------------------------------

## unit_id -> { "pid": int, "rules": Array[Dictionary],
##              "current_rule_idx": int, "last_action": String }
var _plans: Dictionary = {}

func _ready() -> void:
	call_deferred("_try_connect_tick_manager")

func _try_connect_tick_manager() -> void:
	var tm = get_node_or_null("/root/TickManager")
	if tm and tm.has_signal("tick_processed"):
		if not tm.tick_processed.is_connected(_on_tick):
			tm.tick_processed.connect(_on_tick)

# -----------------------------------------------------------------
# Public API
# -----------------------------------------------------------------

## Replace the rule list for `unit_id`.  Pass an empty array to clear.
## Returns false if `pid` doesn't own the unit.
func set_behavior(unit_id: int, rules: Array, pid: int = -1) -> bool:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null:
		return false
	var unit = gw._find_unit(unit_id) if gw.has_method("_find_unit") else null
	if unit == null:
		push_warning("BehaviorPlanner.set_behavior: unit %d not found." % unit_id)
		return false
	if pid >= 0 and "player_id" in unit and int(unit.player_id) != pid:
		print("[OWNERSHIP_ERR] Player ", pid, " tried to set behavior on unit ",
			unit_id, " owned by player ", unit.player_id)
		return false
	if rules.is_empty():
		_plans.erase(unit_id)
		print("[BEHAVIOR] Cleared plan for unit ", unit_id)
		return true
	_plans[unit_id] = {
		"pid": int(unit.player_id) if "player_id" in unit else pid,
		"rules": rules.duplicate(true),
		"current_rule_idx": -1,
		"last_action": ""
	}
	print("[BEHAVIOR] Registered ", rules.size(), " rule(s) for unit ", unit_id,
		" (player ", _plans[unit_id]["pid"], ")")
	# Immediate first evaluation so the AI doesn't wait a tick.
	_evaluate_unit(unit_id)
	return true

func clear_behavior(unit_id: int) -> void:
	if _plans.has(unit_id):
		_plans.erase(unit_id)
		print("[BEHAVIOR] Cleared plan for unit ", unit_id)

func has_behavior(unit_id: int) -> bool:
	return _plans.has(unit_id)

# -----------------------------------------------------------------
# Tick evaluation
# -----------------------------------------------------------------

func _on_tick(_count: int) -> void:
	# Snapshot keys so erase-during-iter is safe.
	for unit_id in _plans.keys().duplicate():
		_evaluate_unit(unit_id)

func _evaluate_unit(unit_id: int) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null:
		return
	var plan = _plans.get(unit_id, null)
	if plan == null:
		return
	var unit = gw._find_unit(unit_id) if gw.has_method("_find_unit") else null
	if unit == null:
		# Unit gone — drop the plan.
		_plans.erase(unit_id)
		return

	var ctx = _build_context(unit, plan["pid"])
	var rules: Array = plan["rules"]

	# Find the highest-priority rule whose predicate is true.
	var best_idx := -1
	var best_priority := -INF
	for i in range(rules.size()):
		var r: Dictionary = rules[i]
		if not _eval_predicate(String(r.get("when", "")), unit, ctx):
			continue
		var p: float = float(r.get("priority", 0))
		if p > best_priority:
			best_priority = p
			best_idx = i

	if best_idx == -1:
		return  # No rule matches this tick.

	var chosen: Dictionary = rules[best_idx]
	var action: String = String(chosen.get("do", ""))
	if action.is_empty() or action == "NONE":
		return

	# Re-dispatch only when the rule changes — otherwise we'd reset combat
	# every single tick.
	if best_idx == int(plan.get("current_rule_idx", -1)) \
			and action == String(plan.get("last_action", "")):
		return

	# A new rule wins.  Clear the unit's command queue so the new action
	# can take over immediately, then dispatch.
	if "command_queue" in unit and unit.command_queue != null:
		unit.command_queue.clear()

	plan["current_rule_idx"] = best_idx
	plan["last_action"] = action
	_dispatch(gw, unit_id, plan["pid"], action, chosen.get("args", {}))
	print("[BEHAVIOR] Unit ", unit_id, " → '", action, "' (rule ", best_idx,
		", priority ", best_priority, ")")

# -----------------------------------------------------------------
# Context + predicate evaluation
# -----------------------------------------------------------------

func _build_context(unit: Node2D, pid: int) -> Dictionary:
	var ctx := {
		"wood":  Game.get_player_wood(pid),
		"stone": Game.get_player_stone(pid),
		"hp":    int(unit.current_health) if "current_health" in unit else 0,
		"max_hp": int(unit.max_health) if "max_health" in unit else 1,
		"is_idle": _is_unit_idle(unit),
		"position": unit.global_position,
		"pid": pid,
	}
	ctx["hp_pct"] = (float(ctx["hp"]) / float(max(1, ctx["max_hp"])))
	# Compute nearest hostile distance once (expensive-ish).
	ctx["enemy_dist"] = _nearest_hostile_distance(unit, pid)
	return ctx

func _is_unit_idle(unit: Node2D) -> bool:
	if "command_queue" in unit and unit.command_queue != null:
		return unit.command_queue.is_idle()
	if "is_idle" in unit:
		return bool(unit.is_idle)
	return true

func _nearest_hostile_distance(unit: Node2D, pid: int) -> float:
	var best := INF
	var pool: Array = []
	pool.append_array(get_tree().get_nodes_in_group("units"))
	pool.append_array(get_tree().get_nodes_in_group("buildings"))
	pool.append_array(get_tree().get_nodes_in_group("barracks"))
	for c in pool:
		if c == unit or not is_instance_valid(c):
			continue
		if not c.has_method("get_player_id"):
			continue
		var c_pid: int = int(c.get_player_id())
		if c_pid == pid or c_pid == -1:
			continue
		if c.has_method("is_alive") and not c.is_alive():
			continue
		var d = unit.global_position.distance_to(c.global_position)
		if d < best:
			best = d
	return best

## Supported predicate syntax (case-sensitive):
##   "true"  /  "always"               — always fires (use as fallback)
##   "idle"                            — unit has no active action
##   "busy"                            — unit currently has an action
##   "enemy_within(<dist>)"            — closest hostile is closer than dist
##   "no_enemy_within(<dist>)"         — nothing hostile within dist
##   "wood > stone"  / "stone > wood"  — compare current player's stockpile
##   "wood >= <n>"  / "wood < <n>"     — stockpile threshold (same for stone)
##   "hp_below(<pct>)"                 — current_health / max_health < pct
##   "hp_above(<pct>)"
func _eval_predicate(expr: String, _unit: Node2D, ctx: Dictionary) -> bool:
	var s := expr.strip_edges()
	if s.is_empty():
		return false
	var lower := s.to_lower()

	if lower == "true" or lower == "always":
		return true
	if lower == "idle":
		return bool(ctx["is_idle"])
	if lower == "busy":
		return not bool(ctx["is_idle"])
	if lower == "wood > stone":
		return int(ctx["wood"]) > int(ctx["stone"])
	if lower == "stone > wood":
		return int(ctx["stone"]) > int(ctx["wood"])

	# Function-call style:  name(arg)
	if s.contains("(") and s.ends_with(")"):
		var paren = s.find("(")
		var name = s.substr(0, paren).strip_edges().to_lower()
		var arg_str = s.substr(paren + 1, s.length() - paren - 2).strip_edges()
		var arg = float(arg_str)
		match name:
			"enemy_within":      return float(ctx["enemy_dist"]) <= arg
			"no_enemy_within":   return float(ctx["enemy_dist"]) > arg
			"hp_below":          return float(ctx["hp_pct"]) < arg
			"hp_above":          return float(ctx["hp_pct"]) > arg
		push_warning("BehaviorPlanner: unknown predicate function '%s'" % name)
		return false

	# Comparison style:  <field> <op> <int>
	for op in [">=", "<=", "==", ">", "<"]:
		var idx = s.find(op)
		if idx > 0:
			var lhs = s.substr(0, idx).strip_edges().to_lower()
			var rhs = s.substr(idx + op.length()).strip_edges()
			var rhs_n = int(rhs) if rhs.is_valid_int() else int(float(rhs))
			var lhs_v: int = 0
			match lhs:
				"wood":     lhs_v = int(ctx["wood"])
				"stone":    lhs_v = int(ctx["stone"])
				"hp":       lhs_v = int(ctx["hp"])
				"max_hp":   lhs_v = int(ctx["max_hp"])
				_:
					push_warning("BehaviorPlanner: unknown lhs '%s'" % lhs)
					return false
			match op:
				">":  return lhs_v >  rhs_n
				"<":  return lhs_v <  rhs_n
				">=": return lhs_v >= rhs_n
				"<=": return lhs_v <= rhs_n
				"==": return lhs_v == rhs_n
			return false

	push_warning("BehaviorPlanner: could not parse predicate '%s'" % s)
	return false

# -----------------------------------------------------------------
# Action dispatch
# -----------------------------------------------------------------

func _dispatch(gw: Node, unit_id: int, pid: int, action: String, args: Variant) -> void:
	var a: Dictionary = args if args is Dictionary else {}
	match action:
		"MOVE":
			var t = a.get("target", {})
			gw.move_unit(unit_id, Vector2(t.get("x", 0), t.get("y", 0)), pid)
		"ATTACK_MOVE":
			var t = a.get("target", {})
			gw.attack_move(unit_id, Vector2(t.get("x", 0), t.get("y", 0)), pid)
		"CHOP_NEAREST":
			gw.go_chop_nearest_tree(unit_id, pid)
		"CHOP_NEAREST_AND_RETURN":
			gw.go_chop_nearest_tree_and_return(unit_id, pid)
		"MINE_NEAREST":
			gw.go_mine_nearest_stone(unit_id, pid)
		"ATTACK_NEAREST":
			gw.attack_nearest_enemy(unit_id, pid)
		"CONSTRUCT":
			gw.go_construct(
				unit_id,
				String(a.get("scene", "res://Houses/Barracks.tscn")),
				Vector2(a.get("x", 0), a.get("y", 0)),
				float(a.get("duration", 10.0)),
				pid
			)
		"EXPLODE":
			var t = a.get("target", {})
			gw.explode_at(
				unit_id,
				Vector2(t.get("x", 0), t.get("y", 0)),
				float(a.get("radius", 64.0)),
				int(a.get("damage", 25)),
				pid
			)
		"NONE":
			pass
		_:
			push_warning("BehaviorPlanner: unknown action '%s'" % action)
