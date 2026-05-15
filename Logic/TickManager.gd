extends Node

signal tick(tick: int)
signal tick_processed(count: int)
signal authoritative_state_ready(state: Dictionary)

@export var tick_interval: float = 0.25
@export var run_without_network: bool = true

var time_passed: float = 0.0
var current_tick: int = 0

func is_ready() -> bool:
	return true

func _process(delta: float) -> void:
	var should_tick := run_without_network

	if multiplayer.multiplayer_peer != null:
		should_tick = multiplayer.is_server()

	if not should_tick:
		return

	time_passed += delta
	if time_passed < tick_interval:
		return

	time_passed = 0.0
	current_tick += 1
	_process_tick()

func _process_tick() -> void:
	var snapshot := _build_authoritative_snapshot()
	tick.emit(current_tick)
	tick_processed.emit(current_tick)
	authoritative_state_ready.emit(snapshot)

func _build_authoritative_snapshot() -> Dictionary:
	var snapshot := {
		"tick": current_tick,
		"timestamp": Time.get_unix_time_from_system(),
		"units": [],
		"resources": [],
		"buildings": [],
		"scenario": {}
	}

	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit):
			continue
		if unit.get("entity_id") == null:
			continue

		snapshot["units"].append({
			"entity_id": unit.get("entity_id"),
			"player_id": unit.get("player_id"),
			"position": {
				"x": unit.global_position.x,
				"y": unit.global_position.y
			},
			"health": unit.get("current_health"),
			"idle": unit.get("is_idle")
		})

	for resource in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(resource):
			continue
		if resource.get("entity_id") == null:
			continue

		snapshot["resources"].append({
			"entity_id": resource.get("entity_id"),
			"resource_name": resource.get("resource_name"),
			"position": {
				"x": resource.global_position.x,
				"y": resource.global_position.y
			},
			"amount": resource.get("amount")
		})

	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building):
			continue
		if building.get("entity_id") == null:
			continue

		snapshot["buildings"].append({
			"entity_id": building.get("entity_id"),
			"player_id": building.get("player_id"),
			"position": {
				"x": building.global_position.x,
				"y": building.global_position.y
			},
			"health": building.get("current_health")
		})

	var scenario = get_node_or_null("/root/World/ScenarioController")
	if scenario != null and scenario.has_method("serialize_state"):
		snapshot["scenario"] = scenario.serialize_state()

	return snapshot
