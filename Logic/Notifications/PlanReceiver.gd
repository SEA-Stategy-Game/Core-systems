## Receives plan notifications from Planning, retrieves UnitPlans and drives
## sequential, looping plan execution for each unit via ActionGateway.
extends Node

const PLANNING_URL = "http://127.0.0.1:5000"

## unit_id (String) -> { "steps": Array, "index": int }
var _store: Dictionary = {}

var _receiver_strategy: Node = null

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

		_store[uid_str] = { "steps": steps, "index": 0 }

		var uid_int = int(uid_str)
		if gateway:
			var unit = gateway._find_unit(uid_int)
			if unit == null:
				push_warning("PlanReceiver: no unit with entity_id=%d found in scene" % uid_int)
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
	var entry = _store[uid_str]
	entry["index"] = (entry["index"] + 1) % entry["steps"].size()
	print("PlanReceiver: unit %d idle - advancing to step %d" % [unit_id, entry["index"]])
	_execute_current_step(unit_id)

func _execute_current_step(unit_id: int) -> void:
	var uid_str = str(unit_id)
	if not _store.has(uid_str):
		return
	var entry = _store[uid_str]
	var step  = entry["steps"][entry["index"]]
	_dispatch_step(unit_id, step)

func _dispatch_step(unit_id: int, step: Dictionary) -> void:
	var gateway = get_node_or_null("/root/ActionGateway")
	if not gateway:
		push_error("PlanReceiver: ActionGateway not found")
		return

	var action_type: String  = step.get("action_type", "")
	var params: Dictionary   = step.get("parameters", {})
	print("PlanReceiver: dispatching step for unit %d: action_type=%s params=%s" % [unit_id, action_type, str(params)])

	match action_type:
		"MoveTo":
			var pos = Vector2(float(params.get("x", 0)), float(params.get("y", 0)))
			gateway.move_unit(unit_id, pos)
		"Harvest":
			var resource_type: String = params.get("resource_type", "")
			if resource_type != "":
				var unit_node = gateway._find_unit(unit_id)
				if unit_node == null:
					return
				var nearest = _find_nearest_resource_by_type(resource_type, unit_node.global_position)
				if nearest == null:
					push_warning("PlanReceiver: no %s found near unit %d" % [resource_type, unit_id])
					return
				print("PlanReceiver: found nearest %s, enqueuing move+harvest" % resource_type)
				var cq = unit_node.get("command_queue")
				if cq:
					cq.enqueue(UnitActionMove.create_to_node(nearest))
					cq.enqueue(UnitActionHarvest.create(nearest))
			else:
				var tid = int(params.get("target_id", -1))
				gateway.go_chop_tree(unit_id, tid)
		"Construct":
			gateway.go_construct(
				unit_id,
				params.get("scene", ""),
				Vector2(float(params.get("x", 0)), float(params.get("y", 0))),
				float(params.get("duration", 10.0))
			)
		_:
			push_warning("PlanReceiver: unknown action_type '%s'" % action_type)

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
