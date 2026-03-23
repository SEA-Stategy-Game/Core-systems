## SenseAPI.gd
## -----------------------------------------------------------------------
## Read-only query interface for the AI Planning Team.
## Provides methods to inspect the current game state without mutating it.
##
## Usage:  var sense = SenseAPI.new(scene_tree)
##         var nearby = sense.get_resources_near(pos, 200.0)
## -----------------------------------------------------------------------
extends RefCounted
class_name SenseAPI

var _tree: SceneTree

func _init(scene_tree: SceneTree) -> void:
	_tree = scene_tree

# -----------------------------------------------------------------
# Unit queries
# -----------------------------------------------------------------

## Return a list of dictionaries describing every living unit.
func get_all_units() -> Array:
	var result: Array = []
	for unit in _tree.get_nodes_in_group("units"):
		if unit is CharacterBody2D:
			result.append(_unit_snapshot(unit))
	return result

## Return a snapshot of a single unit by its entity_id.
func get_unit(unit_id: int) -> Dictionary:
	for unit in _tree.get_nodes_in_group("units"):
		if unit is CharacterBody2D and _get_id(unit) == unit_id:
			return _unit_snapshot(unit)
	return {}

## Detailed snapshot including the current ActionState of the queue
func get_unit_status(unit_id: int) -> Dictionary:
	var data = get_unit(unit_id)
	if data.is_empty():
		return data
		
	# Enrich with ActionState
	for unit in _tree.get_nodes_in_group("units"):
		if unit is CharacterBody2D and _get_id(unit) == unit_id:
			if "command_queue" in unit and unit.command_queue != null:
				var cq = unit.command_queue
				if cq._current_action != null:
					var action_data = cq._current_action.serialize()
					data["current_action"] = action_data
					data["action_state"] = action_data.get("state", -1)
				else:
					data["current_action"] = null
					data["action_state"] = -1 # Treat as IDLE / null state
			break
	return data

## Return all units within `radius` of `origin`.
func get_units_near(origin: Vector2, radius: float) -> Array:
	var result: Array = []
	for unit in _tree.get_nodes_in_group("units"):
		if unit is CharacterBody2D:
			if unit.global_position.distance_to(origin) <= radius:
				result.append(_unit_snapshot(unit))
	return result

# -----------------------------------------------------------------
# Resource queries
# -----------------------------------------------------------------

## Return all MapResource nodes (trees, stones, etc.) in the scene.
func get_all_resources() -> Array:
	var result: Array = []
	var objects = _tree.get_root().get_node_or_null("World/Objects")
	if objects:
		for child in objects.get_children():
			result.append(_resource_snapshot(child))
	# Also check loose resources directly under World
	var world = _tree.get_root().get_node_or_null("World")
	if world:
		for child in world.get_children():
			if child is MapResource:
				result.append(_resource_snapshot(child))
	return result

## Return resources within `radius` of `origin`. Using distance_squared for O(N) performance.
func get_resources_near(origin: Vector2, radius: float) -> Array:
	var result: Array = []
	var r2 = radius * radius
	for res in get_all_resources():
		var pos = Vector2(res["position"]["x"], res["position"]["y"])
		if pos.distance_squared_to(origin) <= r2:
			result.append(res)
	return result

## Alias requested for AI team querying
func get_world_resources() -> Array:
	return get_all_resources()

# -----------------------------------------------------------------
# Building queries
# -----------------------------------------------------------------

## Return all buildings.
func get_all_buildings() -> Array:
	var result: Array = []
	var houses = _tree.get_root().get_node_or_null("World/Houses")
	if houses:
		for child in houses.get_children():
			result.append(_building_snapshot(child))
	return result

## Return buildings within `radius` of `origin`.
func get_buildings_near(origin: Vector2, radius: float) -> Array:
	var result: Array = []
	for bld in get_all_buildings():
		var pos = Vector2(bld["position"]["x"], bld["position"]["y"])
		if pos.distance_to(origin) <= radius:
			result.append(bld)
	return result

# -----------------------------------------------------------------
# Global game state
# -----------------------------------------------------------------

func get_resources_stockpile() -> Dictionary:
	return {
		"wood": Game.Wood,
		"stone": Game.Stone
	}

func get_tick_count() -> int:
	var tick_mgr = _tree.get_root().get_node_or_null("World/TickManager")
	if tick_mgr and "tick_count" in tick_mgr:
		return tick_mgr.tick_count
	return -1

func get_tick_data() -> int:
	return get_tick_count()

# -----------------------------------------------------------------
# Internal snapshot helpers
# -----------------------------------------------------------------

func _unit_snapshot(unit: Node) -> Dictionary:
	var is_idle = true
	if "is_idle" in unit:
		is_idle = unit.is_idle
		
	var data: Dictionary = {
		"id": _get_id(unit),
		"name": unit.name,
		"position": {"x": unit.global_position.x, "y": unit.global_position.y},
		"health": unit.current_health if "current_health" in unit else -1,
		"is_idle": is_idle
	}
	if "command_queue" in unit and unit.command_queue != null:
		data["is_idle"] = unit.command_queue.is_idle()
		data["pending_actions"] = unit.command_queue.pending_count()
	return data

func _resource_snapshot(node: Node) -> Dictionary:
	return {
		"id": _get_id(node),
		"name": node.name,
		"type": node.get_class(),
		"position": {"x": node.global_position.x, "y": node.global_position.y},
		"amount": node.amount if "amount" in node else -1,
		"time_remaining": node.currentTime if "currentTime" in node else -1
	}

func _building_snapshot(node: Node) -> Dictionary:
	return {
		"id": _get_id(node),
		"name": node.name,
		"type": node.get_class(),
		"position": {"x": node.global_position.x, "y": node.global_position.y}
	}

func _get_id(node: Node) -> int:
	if "entity_id" in node:
		return node.entity_id
	return node.get_instance_id()
