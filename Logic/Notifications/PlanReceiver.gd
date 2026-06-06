## Receives plan notifications from Planning, retrieves UnitPlans and drives
## sequential, looping plan execution for each unit via ActionGateway.
extends Node

const LISTEN_PORT  = 8085
@onready var PLANNING_URL: String = OS.get_environment("PLANNING_URL") if OS.has_environment("PLANNING_URL") else "http://127.0.0.1:5000"

const BUILDING_SCENES: Dictionary = {
	"Barracks": "res://Houses/Barracks.tscn",
}

## unit_id (String) -> { "steps": Array, "index": int }
var _store: Dictionary = {}

var _receiver_strategy: Node = null
var _sense: SenseAPI   = null

# ----------------------------------------------------------------
# Lifecycle
# ----------------------------------------------------------------

func _ready() -> void:
	var redis_flag = OS.get_environment("USE_REDIS")
	if redis_flag == "true" or redis_flag == "1":
		var RedisReceiver = load("res://Logic/Notifications/RedisNotificationReceiver.gd")
		_receiver_strategy = RedisReceiver.new()
		_receiver_strategy.name = "RedisNotificationReceiver"
	else:
		var HttpReceiver = load("res://Logic/Notifications/HttpNotificationReceiver.gd")
		_receiver_strategy = HttpReceiver.new()
		_receiver_strategy.name = "HttpNotificationReceiver"

	add_child(_receiver_strategy)
	_receiver_strategy.plan_notified.connect(_on_plan_notified)
	if _receiver_strategy.has_signal("game_state_requested"):
		_receiver_strategy.game_state_requested.connect(_serve_game_state)

	_sense = SenseAPI.new(get_tree())

	var gateway = get_node_or_null("/root/ActionGateway")
	if gateway:
		gateway.unit_idled.connect(_on_unit_idled)
		print("PlanReceiver: connected to ActionGateway.unit_idled signal")
	else:
		push_error("PlanReceiver: ActionGateway not found at startup")

func _on_plan_notified(game_id: String, player_id: String, unit_ids: Array) -> void:
	_fetch_and_store.call_deferred(game_id, player_id, unit_ids)

# ----------------------------------------------------------------
# Get UnitPlans from Planning and save in _store
# ----------------------------------------------------------------

func _fetch_and_store(game_id: String, player_id: String, unit_ids: Array) -> void:
	var ids_param = ",".join(unit_ids)
	var url = "%s/plan/%s/%s?unitIds=%s" % [PLANNING_URL, game_id, player_id, ids_param]
	print("PlanReceiver: fetching UnitPlans from %s" % url)

	var http = HTTPRequest.new()
	add_child(http)
	if http.request(url) != OK:
		push_error("PlanReceiver: HTTP request failed")
		http.queue_free()
		return

	var res = await http.request_completed
	http.queue_free()

	print("PlanReceiver: Planning responded with HTTP %d" % res[1])

	if res[1] != 200:
		push_warning("PlanReceiver: Planning returned %d - no plans assigned" % res[1])
		return

	var raw_body = res[3].get_string_from_utf8()
	print("PlanReceiver: response body: %s" % raw_body)

	var j = JSON.new()
	if j.parse(raw_body) != OK:
		push_error("PlanReceiver: failed to parse response from Planning")
		return

	var resp_body: Dictionary = j.get_data()
	var unit_plans: Array = resp_body.get("unit_plans", [])
	print("PlanReceiver: received %d UnitPlan(s)" % unit_plans.size())

	var valid_unit_ids: Array = []
	var gateway = get_node_or_null("/root/ActionGateway")
	if gateway:
		var player_units = gateway.get_player_units(int(player_id))
		valid_unit_ids = player_units.map(func(u): return str(u.get("id", "")))
		print("PlanReceiver: units in scene for player %s: %s" % [player_id, str(valid_unit_ids)])

	var keys_to_erase: Array = []
	for k in _store.keys():
		if _store[k].get("player_id", "") == player_id:
			keys_to_erase.append(k)
	for k in keys_to_erase:
		if gateway:
			var old_unit = gateway._find_unit_for_player(int(k), int(player_id))
			if old_unit and old_unit.get("command_queue") and old_unit.command_queue:
				old_unit.command_queue.clear()
		_store.erase(k)
	if not keys_to_erase.is_empty():
		print("PlanReceiver: cleared %d old store entries for player %s" % [keys_to_erase.size(), player_id])

	for up in unit_plans:
		var uid_str: String = str(up.get("unit_id", ""))
		
		if not uid_str in valid_unit_ids:
			print("PlanReceiver: unit_id='%s' does not belong to player %s - skipping" % [uid_str, player_id])
			continue
			
		var steps: Array    = up.get("steps", [])
		print("PlanReceiver: processing UnitPlan for unit_id='%s', %d steps" % [uid_str, steps.size()])

		if uid_str.is_empty() or steps.is_empty():
			push_warning("PlanReceiver: empty UnitPlan - skipping")
			continue

		_store[uid_str] = { "steps": steps, "index": 0, "player_id": player_id, "if_state": null }

		var uid_int = int(uid_str)
		if gateway:
			var unit = gateway._find_unit_for_player(uid_int, int(player_id))
			if unit == null:
				push_warning("PlanReceiver: no unit with entity_id=%d for player %s found in scene" % [uid_int, player_id])
				continue
			if unit.command_queue:
				unit.command_queue.clear()
		_execute_current_step(uid_int)

# ----------------------------------------------------------------
# Step execution and looping
# ----------------------------------------------------------------

func _on_unit_idled(unit_id: int) -> void:
	var uid_str = str(unit_id)
	if not _store.has(uid_str):
		return
	var entry    = _store[uid_str]
	var if_state = entry.get("if_state", null)

	if if_state != null:
		var branch: Array = if_state["branch"]
		var next_bi: int  = if_state["branch_index"] + 1
		if next_bi < branch.size():
			if_state["branch_index"] = next_bi
			print("PlanReceiver: unit %d idle in if-branch — step %d" % [unit_id, next_bi])
			_dispatch_step(unit_id, branch[next_bi])
		else:
			entry["if_state"] = null
			entry["index"] = (entry["index"] + 1) % entry["steps"].size()
			print("PlanReceiver: unit %d idle — if-branch done, top-level step %d" % [unit_id, entry["index"]])
			_execute_current_step(unit_id)
	else:
		entry["index"] = (entry["index"] + 1) % entry["steps"].size()
		print("PlanReceiver: unit %d idle — advancing to step %d" % [unit_id, entry["index"]])
		_execute_current_step(unit_id)

func _execute_current_step(unit_id: int) -> void:
	var uid_str = str(unit_id)
	if not _store.has(uid_str):
		return
	var entry = _store[uid_str]
	var step  = entry["steps"][entry["index"]]
	_execute_step_by_type(unit_id, step)

func _dispatch_step(unit_id: int, step: Dictionary) -> void:
	var gateway = get_node_or_null("/root/ActionGateway")
	if not gateway:
		push_error("PlanReceiver: ActionGateway not found")
		return

	var action_type: String = step.get("action_type", "")
	var params: Dictionary  = step.get("parameters", {})
	print("PlanReceiver: dispatching step for unit %d: action_type=%s params=%s" % [unit_id, action_type, str(params)])

	var dispatched := false

	match action_type:
		"MoveTo":
			var pos = Vector2(float(params.get("x", 0)), float(params.get("y", 0)))
			dispatched = gateway.move_unit(unit_id, pos)
		"Attack":
			var mode = params.get("mode", "nearest")
			if mode == "move":
				var pos = Vector2(float(params.get("x", 0)), float(params.get("y", 0)))
				dispatched = gateway.attack_move(unit_id, pos)
			elif mode == "target":
				var tid = int(params.get("target_id", -1))
				dispatched = gateway.attack_target(unit_id, tid)
			else:
				dispatched = gateway.attack_nearest_enemy(unit_id)
		"Harvest":
			var resource_type: String = params.get("resource_type", "")
			var mode: String          = params.get("mode", "")
			if resource_type == "tree" and mode == "return":
				dispatched = gateway.go_chop_nearest_tree_and_return(unit_id)
			elif resource_type == "tree":
				dispatched = gateway.go_chop_nearest_tree(unit_id)
			elif resource_type == "stone":
				dispatched = gateway.go_mine_nearest_stone(unit_id)
			else:
				var tid = int(params.get("target_id", -1))
				dispatched = gateway.go_chop_tree(unit_id, tid)
		"Construct":
			var alias: String      = params.get("scene", "")
			var scene_path: String = BUILDING_SCENES.get(alias, alias)
			var pos = Vector2(float(params.get("x", 0)), float(params.get("y", 0)))
			var duration = float(params.get("duration", 10.0))
			if scene_path.is_empty():
				push_warning("PlanReceiver: unknown building '%s'" % alias)
			else:
				dispatched = gateway.go_construct(unit_id, scene_path, pos, duration)
		_:
			push_warning("PlanReceiver: unknown action_type '%s'" % action_type)

	if not dispatched:
		print("PlanReceiver: unit %d — '%s' could not be dispatched, skipping to next step" % [unit_id, action_type])
		_on_unit_idled.call_deferred(unit_id)

# ----------------------------------------------------------------
# Conditional execution
# ----------------------------------------------------------------

func _execute_step_by_type(unit_id: int, step: Dictionary) -> void:
	if step.get("step_type", "action") == "conditional":
		_execute_if_step(unit_id, step)
	else:
		_dispatch_step(unit_id, step)

func _execute_if_step(unit_id: int, step: Dictionary) -> void:
	var uid_str       = str(unit_id)
	var entry         = _store[uid_str]
	var player_id_int = int(entry.get("player_id", "-1"))
	var condition     = step.get("parameters", {}).get("condition", "")
	var result        = _eval_condition(condition, unit_id, player_id_int)
	print("PlanReceiver: unit %d — if '%s' → %s" % [unit_id, condition, str(result)])

	var branch: Array = step.get("body", []) if result else step.get("else_body", [])
	if branch.is_empty():
		entry["index"] = (entry["index"] + 1) % entry["steps"].size()
		_execute_current_step(unit_id)
		return

	entry["if_state"] = { "branch": branch, "branch_index": 0 }
	_dispatch_step(unit_id, branch[0])

func _eval_condition(condition: String, unit_id: int, player_id_int: int) -> bool:
	if _sense == null:
		_sense = SenseAPI.new(get_tree())
	var cond       = condition.strip_edges()
	var cond_lower = cond.to_lower()
	var gateway    = get_node_or_null("/root/ActionGateway")

	if cond_lower == "always":
		return true

	if cond_lower == "idle" or cond_lower == "busy":
		var snap = _sense.get_unit(unit_id)
		var is_idle = snap.get("is_idle", true)
		return is_idle if cond_lower == "idle" else not is_idle

	if cond_lower.begins_with("enemywithin ") or cond_lower.begins_with("noenemywithin "):
		var unit_node = gateway._find_unit_for_player(unit_id, player_id_int) if gateway else null
		if unit_node == null:
			return false
		var prefix_len = 12 if cond_lower.begins_with("enemywithin ") else 14
		var dist = float(cond.substr(prefix_len))
		var found = false
		for u in _sense.get_units_near(unit_node.global_position, dist):
			if int(u.get("player_id", -1)) != player_id_int and int(u.get("id", -1)) != unit_id:
				found = true
				break
		return found if cond_lower.begins_with("enemywithin") else not found

	if cond_lower.begins_with("hpbelow ") or cond_lower.begins_with("hpabove "):
		var snap   = _sense.get_unit(unit_id)
		var hp     = float(snap.get("health",     100))
		var max_hp = float(snap.get("max_health", 100))
		if max_hp <= 0:
			return false
		var threshold = float(cond.split(" ")[1])
		return (hp / max_hp) < threshold if cond_lower.begins_with("hpbelow") \
										 else (hp / max_hp) > threshold

	var stockpile = _sense.get_resources_stockpile()
	var wood  = int(stockpile.get("wood",  0))
	var stone = int(stockpile.get("stone", 0))

	if cond_lower == "wood > stone":  return wood > stone
	if cond_lower == "stone > wood":  return stone > wood
	if cond_lower == "wood >= stone": return wood >= stone
	if cond_lower == "stone >= wood": return stone >= wood

	var re = RegEx.new()
	re.compile("^(wood|stone)\\s*(>=|<=|>|<|==)\\s*(\\d+)$")
	var m = re.search(cond_lower)
	if m:
		var cur = float(wood if m.get_string(1) == "wood" else stone)
		var val = float(m.get_string(3))
		match m.get_string(2):
			">":  return cur > val
			"<":  return cur < val
			">=": return cur >= val
			"<=": return cur <= val
			"==": return cur == val

	push_warning("PlanReceiver: unrecognised condition '%s' — defaulting to false" % condition)
	return false

func _find_nearest_resource_by_type(resource_type: String, origin: Vector2) -> Node:
	var target_name = "ressource_" + resource_type.to_lower()
	var best: Node = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("resources"):
		if "resource_name" in node and node.resource_name == target_name:
			var d = origin.distance_squared_to(node.global_position)
			if d < best_dist:
				best_dist = d
				best = node
	return best

# ----------------------------------------------------------------
# Game-state endpoint — served to Planning backend for entity validation
# ----------------------------------------------------------------

func _serve_game_state(peer: StreamPeerTCP) -> void:
	if _sense == null:
		_sense = SenseAPI.new(get_tree())
	var units_arr: Array = []
	var res_arr:   Array = []
	for u in _sense.get_all_units():
		units_arr.append({"id": str(u.get("id", u.get("entity_id", -1)))})
	for r in _sense.get_world_resources():
		res_arr.append({"id": str(r.get("id", r.get("entity_id", -1)))})
	var body = JSON.stringify({"units": units_arr, "resources": res_arr})
	var resp = ("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" +
				"Content-Length: %d\r\nConnection: close\r\n\r\n%s") % [body.length(), body]
	peer.put_data(resp.to_utf8_buffer())
	peer.disconnect_from_host()
