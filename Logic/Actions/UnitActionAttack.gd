## UnitActionAttack.gd
## -----------------------------------------------------------------------
## Concrete IUnitAction -- proximity-based combat using Area2D.
##
## The unit scans for hostile entities (different player_id) within its
## 'Range' Area2D. It applies damage to the closest target every cooldown
## interval. The action COMPLETES when no hostiles remain in range, 
## or if attacking a specific target and the target dies.
## -----------------------------------------------------------------------
extends RefCounted
class_name UnitActionAttack

const ActionState = IUnitAction.ActionState

var _state: int = ActionState.PENDING
var _attack_damage: int = 10
var _attack_cooldown: float = 1.0
var _cooldown_timer: float = 0.0
var _attacker_player_id: int = -1

## Optional: specific target to focus on. If null, auto-acquires closest.
var _target_node: Node2D = null

# -----------------------------------------------------------------
# IUnitAction contract
# -----------------------------------------------------------------

func start(unit: CharacterBody2D, target: Node2D) -> void:
	_state = ActionState.RUNNING
	_target_node = target

	# Read combat stats from the unit
	if "attack_damage" in unit:
		_attack_damage = unit.attack_damage
	if "attack_cooldown" in unit:
		_attack_cooldown = unit.attack_cooldown
	if "player_id" in unit:
		_attacker_player_id = unit.player_id

	_cooldown_timer = 0.0  # Allow immediate first attack
	print("[COMBAT_LOG] Unit ", _get_uid(unit), " entering combat state.")

func tick(unit: CharacterBody2D, delta: float) -> int:
	if _state != ActionState.RUNNING:
		return _state

	_cooldown_timer -= delta

	# If we have a specific target, check if it is still valid
	if is_instance_valid(_target_node):
		if _target_node.has_method("is_alive") and not _target_node.is_alive():
			print("[COMBAT_LOG] Target destroyed. Scanning for new hostiles.")
			_target_node = null

	# Auto-acquire closest hostile in Area2D range if none assigned
	if not is_instance_valid(_target_node) and unit.has_method("get_closest_hostile"):
		_target_node = unit.get_closest_hostile()

	# If no specific target and nothing in our Area2D, combat is complete
	if not is_instance_valid(_target_node):
		_state = ActionState.COMPLETED
		print("[COMBAT_LOG] Unit ", _get_uid(unit), " no hostiles. Exiting combat.")
		if unit.has_node("AnimationPlayer"):
			unit.get_node("AnimationPlayer").stop()
		return _state

	# Check if target is inside our Range Area2D
	var in_range = false
	if unit.has_method("get_hostiles_in_range"):
		var hostiles = unit.get_hostiles_in_range()
		if hostiles.has(_target_node):
			in_range = true

	# We fall back to a reasonable distance check if Area2D logic isn't fully ready
	# but primarily rely on the Area2D in_range flag
	var dist = unit.global_position.distance_to(_target_node.global_position)
	if not in_range:
		# Chase the target if it's out of Area2D range
		var direction = unit.global_position.direction_to(_target_node.global_position)
		var speed = unit.Speed if "Speed" in unit else 50
		unit.velocity = direction * speed
		unit.move_and_slide()
		
		# Play walk animation
		if unit.has_node("AnimationPlayer"):
			var anim: AnimationPlayer = unit.get_node("AnimationPlayer")
			if anim.has_animation("Walk Down") and not anim.is_playing():
				anim.play("Walk Down")
		return _state

	# In Area2D range -- stop and attack on cooldown
	unit.velocity = Vector2.ZERO

	if _cooldown_timer <= 0.0:
		_cooldown_timer = _attack_cooldown
		if _target_node.has_method("take_damage"):
			_target_node.take_damage(_attack_damage)
			print("[COMBAT_LOG] Unit ", _get_uid(unit), " dealt ", _attack_damage, " damage to target at ", _target_node.global_position)

			# Play attack animation if available
			if unit.has_node("AnimationPlayer"):
				var anim: AnimationPlayer = unit.get_node("AnimationPlayer")
				# If we don't have an attack animation, play work/chop as fallback
				if anim.has_animation("Attack"):
					anim.play("Attack")
				elif anim.has_animation("Work"):
					anim.play("Work")

	return _state

func cancel(unit: CharacterBody2D) -> void:
	_state = ActionState.FAILED
	unit.velocity = Vector2.ZERO
	if unit.has_node("AnimationPlayer"):
		unit.get_node("AnimationPlayer").stop()
	print("[COMBAT_LOG] Unit ", _get_uid(unit), " combat cancelled.")

func serialize() -> Dictionary:
	var target_id: int = -1
	if is_instance_valid(_target_node) and "entity_id" in _target_node:
		target_id = _target_node.entity_id
	return {
		"type": "ATTACK",
		"target_id": target_id,
		"attack_damage": _attack_damage,
		"state": _state
	}

# -----------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------

func _get_uid(unit: CharacterBody2D) -> int:
	return unit.entity_id if "entity_id" in unit else unit.get_instance_id()

# -----------------------------------------------------------------
# Factory
# -----------------------------------------------------------------

## Create an attack action that auto-targets the nearest hostile.
static func create_auto() -> UnitActionAttack:
	var action = UnitActionAttack.new()
	return action

## Create an attack action focused on a specific target node.
static func create_focused(target: Node2D) -> UnitActionAttack:
	var action = UnitActionAttack.new()
	action._target_node = target
	return action
