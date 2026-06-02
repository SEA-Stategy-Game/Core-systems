## TaskSerializer.gd
## -----------------------------------------------------------------------
## Handles saving and loading of AI-triggered task state between sessions.
## Uses Godot's FileAccess to write JSON to user:// directory.
## -----------------------------------------------------------------------
extends RefCounted
class_name TaskSerializer

# -----------------------------------------------------------------
# Save
# -----------------------------------------------------------------

static var _strategy: IStateSerializer = null

static func _get_strategy() -> IStateSerializer:
	if _strategy == null:
		var redis_flag = OS.get_environment("USE_REDIS")
		if redis_flag == "true" or redis_flag == "1":
			_strategy = load("res://Logic/StateSerializer/RedisStatePersistence.gd").new()
		else:
			_strategy = load("res://Logic/StateSerializer/LocalStatePersistence.gd").new()
			
	return _strategy

## Serialise the command queues of all units and the global state
## into a JSON file.
static func save_state(scene_tree: SceneTree) -> bool:
	var state: Dictionary = {
		"timestamp": Time.get_unix_time_from_system(),
		"resources": Game.player_resources,
		"units": []
	}

	for unit in scene_tree.get_nodes_in_group("units"):
		if unit is CharacterBody2D and "command_queue" in unit and unit.command_queue != null:
			var unit_data: Dictionary = {
				"id": unit.entity_id if "entity_id" in unit else unit.get_instance_id(),
				"position": {"x": unit.global_position.x, "y": unit.global_position.y},
				"queue": unit.command_queue.serialize()
			}
			state["units"].append(unit_data)

	return _get_strategy().save_state(state, scene_tree)

# -----------------------------------------------------------------
# Load
# -----------------------------------------------------------------

## Load previously saved task state.  Returns the parsed Dictionary
## or an empty Dictionary on failure.
static func load_state() -> Dictionary:
	return _get_strategy().load_state()

# -----------------------------------------------------------------
# Restore helpers
# -----------------------------------------------------------------

## Reconstruct command queues from a previously loaded state dict.
## Call this after units have been instantiated in the scene tree.
static func restore_queues(scene_tree: SceneTree, state: Dictionary) -> void:
	if state.is_empty():
		return

	# Restore global resources
	if "player_resources" in state:
		Game.player_resources = state["player_resources"]

	# Restore per-unit queues
	if "units" not in state:
		return

	for unit_data in state["units"]:
		# For each saved action, we re-create the action object and enqueue.
		# Full reconstruction requires matching unit IDs to scene nodes,
		# which depends on the game's entity ID assignment scheme.
		if "queue" in unit_data:
			for action_dict in unit_data["queue"]:
				_rebuild_action(scene_tree, unit_data, action_dict)

static func _rebuild_action(_scene_tree: SceneTree, _unit_data: Dictionary, action_dict: Dictionary) -> void:
	var action_type: String = action_dict.get("type", "")
	match action_type:
		"MOVE":
			var pos = action_dict.get("target_position", {})
			var _action = UnitActionMove.create(
				Vector2(pos.get("x", 0), pos.get("y", 0))
			)
			# Enqueue into the matching unit's command_queue
			# (requires entity_id lookup -- left as TODO for full integration)
		"HARVEST":
			pass  # Resource node lookup by ID required
		"CONSTRUCT":
			var pos = action_dict.get("build_position", {})
			var _action = UnitActionConstruct.create(
				action_dict.get("building_scene", ""),
				Vector2(pos.get("x", 0), pos.get("y", 0)),
				action_dict.get("duration", 10.0)
			)
		_:
			push_warning("TaskSerializer: Unknown action type: ", action_type)
