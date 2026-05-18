extends RefCounted
class_name UnitActionHarvest

const ACTION_STATE = IUnitAction.ActionState

var _state: int = ACTION_STATE.PENDING
var _target_node: Node2D = null
var _elapsed: float = 0.0
var _harvest_duration: float = 5.0
var _inventory_credited: bool = false

func setup(resource_node: Node2D) -> void:
	_target_node = resource_node
	if resource_node == null:
		return

	var total_time_value = resource_node.get("total_time")
	if total_time_value != null:
		_harvest_duration = float(total_time_value)
	elif resource_node.get("totalTime") != null:
		_harvest_duration = float(resource_node.get("totalTime"))

	var resource_name_value = resource_node.get("resource_name")
	var resource_name: String = ""
	if resource_name_value != null:
		resource_name = str(resource_name_value)

	if resource_name == "ressource_tree" or resource_node is TreeResource:
		_resource_type = "tree"
	elif resource_name == "ressource_stone" or resource_node is StoneResource:
		_resource_type = "stone"

func start(unit: CharacterBody2D, target: Node2D) -> void:
	_state = ACTION_STATE.RUNNING
	if target != null:
		_target_node = target

	if not is_instance_valid(_target_node):
		_state = ACTION_STATE.FAILED
		return
	if _target_node.has_method("is_alive") and not _target_node.is_alive():
		_state = ACTION_STATE.FAILED
		return

	if "total_time" in _target_node:
		_harvest_duration = float(_target_node.total_time)
	elif "totalTime" in _target_node:
		_harvest_duration = float(_target_node.totalTime)

	if unit.has_node("AnimationPlayer"):
		var anim: AnimationPlayer = unit.get_node("AnimationPlayer")
		if anim.has_animation("Chop"):
			anim.play("Chop")
		elif anim.has_animation("Work"):
			anim.play("Work")

	# Register the harvesting unit on the resource so its timer runs.
	if "units_harvesting" in _target_node:
		_target_node.units_harvesting += 1
		if _target_node.has_node("ProgressBar/Timer"):
			var timer = _target_node.get_node("ProgressBar/Timer")
			if timer.is_stopped():
				timer.start()

func tick(unit: CharacterBody2D, delta: float) -> int:
	if _state != ACTION_STATE.RUNNING:
		return _state

	if not is_instance_valid(_target_node):
		# Resource was freed this frame (depleted). Credit inventory now.
		_credit_inventory_if_needed(unit)
		_state = ACTION_STATE.COMPLETED
		if unit.has_node("AnimationPlayer"):
			unit.get_node("AnimationPlayer").stop()
		return _state

	if _target_node.has_method("is_alive") and not _target_node.is_alive():
		_credit_inventory_if_needed(unit)
		_state = ACTION_STATE.COMPLETED
		_cleanup(unit)
		return _state

	_elapsed += delta

	if _elapsed > _harvest_duration * 3.0:
		_state = ACTION_STATE.COMPLETED
		_cleanup(unit)

	return _state

func cancel(unit: CharacterBody2D) -> void:
	_state = ACTION_STATE.FAILED
	_cleanup(unit)

func serialize() -> Dictionary:
	var target_id: int = -1
	if is_instance_valid(_target_node) and "entity_id" in _target_node:
		target_id = _target_node.entity_id
	return {
		"type": "HARVEST",
		"target_id": target_id,
		"elapsed": _elapsed,
		"state": _state
	}

func _credit_inventory_if_needed(unit: CharacterBody2D) -> void:
	if _inventory_credited:
		return
	_inventory_credited = true

	var multiplayer_api := unit.get_tree().get_multiplayer()
	var peer: MultiplayerPeer = multiplayer_api.multiplayer_peer
	var is_authoritative: bool = (
		peer == null or
		peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED or
		multiplayer_api.is_server()
	)
	if not is_authoritative:
		return

	if is_instance_valid(_target_node):
		var resource_name_value = _target_node.get("resource_name")
		var resource_name: String = ""
		if resource_name_value != null:
			resource_name = str(resource_name_value)

		if _target_node is TreeResource or resource_name == "ressource_tree":
			Game.Wood += 1
			print("[RESOURCE_LOG] Inventory credited: Wood=", Game.Wood)
		elif _target_node is StoneResource or resource_name == "ressource_stone":
			Game.Stone += 1
			print("[RESOURCE_LOG] Inventory credited: Stone=", Game.Stone)
	else:
		if _resource_type == "tree":
			Game.Wood += 1
			print("[RESOURCE_LOG] Inventory credited (post-free): Wood=", Game.Wood)
		elif _resource_type == "stone":
			Game.Stone += 1
			print("[RESOURCE_LOG] Inventory credited (post-free): Stone=", Game.Stone)

func _cleanup(unit: CharacterBody2D) -> void:
	if is_instance_valid(_target_node):
		if "units_harvesting" in _target_node:
			_target_node.units_harvesting = maxi(0, _target_node.units_harvesting - 1)
			if _target_node.units_harvesting <= 0 and _target_node.has_node("ProgressBar/Timer"):
				_target_node.get_node("ProgressBar/Timer").stop()
	if unit.has_node("AnimationPlayer"):
		unit.get_node("AnimationPlayer").stop()

var _resource_type: String = ""

static func create(resource_node: Node2D) -> UnitActionHarvest:
	var action = UnitActionHarvest.new()
	action.setup(resource_node)
	return action