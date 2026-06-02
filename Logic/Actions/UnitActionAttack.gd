## UnitActionAttack.gd
## -----------------------------------------------------------------------
## Concrete IUnitAction -- proximity-based combat using Area2D.
##
## The unit scans for hostile entities (different player_id) within its
## 'Range' Area2D. It applies damage to the closest target every cooldown
## interval. The action COMPLETES when no hostiles remain in range,
## or if attacking a specific target and the target dies.
##
## Initiative bonus: when a player explicitly *commands* an attack via the
## ActionGateway (ATTACK / ATTACK_NEAREST / ATTACK_MOVE), they get a small
## damage multiplier. Auto-aggro (a unit defending itself when an enemy
## walks into its Range) uses 1.0x.
## -----------------------------------------------------------------------
extends RefCounted
class_name UnitActionAttack

const ActionState = IUnitAction.ActionState

## Pixel distance at which we treat a target as "engaged" even if the Range
## Area2D hasn't fired body_entered (defensive against layer mismatch).
const FALLBACK_MELEE_DIST: float = 18.0

## Default chase speed for the in-action melee approach (px/s).
## Matches the unit's regular pathfind movement so chase doesn't look like
## a teleport.
const CHASE_SPEED: float = 50.0

var _state: int = ActionState.PENDING
var _attack_damage: int = 10
var _attack_cooldown: float = 1.0
var _cooldown_timer: float = 0.0
var _attacker_player_id: int = -1
var _initiative_bonus: float = 1.0

## Optional: specific target to focus on. If null, auto-acquires closest.
var _target_node: Node2D = null

# -----------------------------------------------------------------
# IUnitAction contract
# -----------------------------------------------------------------

func start(unit: CharacterBody2D, target: Node2D) -> void:
	_state = ActionState.RUNNING
	if target != null:
		_target_node = target

	# Read combat stats from the unit
	if "attack_damage" in unit:
		_attack_damage = unit.attack_damage
	if "attack_cooldown" in unit:
		_attack_cooldown = unit.attack_cooldown
	if "player_id" in unit:
		_attacker_player_id = unit.player_id

	_cooldown_timer = 0.0  # Allow immediate first attack
	print("[COMBAT_LOG] Unit ", _get_uid(unit), " entering combat (initiative x",
		_initiative_bonus, ").")

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

	# Range check: primary via Range Area2D, fallback to a flat distance.
	var in_range := false
	if unit.has_method("get_hostiles_in_range"):
		var hostiles = unit.get_hostiles_in_range()
		if hostiles.has(_target_node):
			in_range = true
	var dist = unit.global_position.distance_to(_target_node.global_position)
	if not in_range and dist <= FALLBACK_MELEE_DIST:
		in_range = true

	if not in_range:
		# Chase the target.
		var direction = unit.global_position.direction_to(_target_node.global_position)
		unit.velocity = direction * CHASE_SPEED
		unit.move_and_slide()

		# Keep the chaser on the navmesh so it can't walk through water tiles.
		var nav_agent = unit.get_node_or_null("NavigationAgent2D")
		if nav_agent != null:
			unit.global_position = NavigationServer2D.map_get_closest_point(
				nav_agent.get_navigation_map(), unit.global_position)

		# Play walk animation
		if unit.has_node("AnimationPlayer"):
			var anim: AnimationPlayer = unit.get_node("AnimationPlayer")
			if anim.has_animation("Walk Down") and not anim.is_playing():
				anim.play("Walk Down")
		return _state

	# In range -- stop and attack on cooldown
	unit.velocity = Vector2.ZERO

	if _cooldown_timer <= 0.0:
		_cooldown_timer = _attack_cooldown
		# Ranged units fire projectiles instead of applying melee damage.
		var fired_projectile: bool = false
		if "uses_projectiles" in unit and unit.uses_projectiles and unit.has_method("fire_projectile"):
			unit.fire_projectile(_target_node)
			fired_projectile = true
			print("[COMBAT_LOG] Unit ", _get_uid(unit), " fired a projectile at target at ", _target_node.global_position)

		if not fired_projectile and _target_node.has_method("take_damage"):
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
		if _target_node.has_method("take_damage"):
			var dmg = int(round(float(_attack_damage) * _initiative_bonus))
			_target_node.take_damage(dmg)
			print("[COMBAT_LOG] Unit ", _get_uid(unit), " hit target for ", dmg,
				" (base ", _attack_damage, " x", _initiative_bonus, ").")

			# Play attack animation if available
			if unit.has_node("AnimationPlayer"):
				var anim: AnimationPlayer = unit.get_node("AnimationPlayer")
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
		"initiative_bonus": _initiative_bonus,
		"state": _state
	}

# -----------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------

func _get_uid(unit: CharacterBody2D) -> int:
	return unit.entity_id if "entity_id" in unit else unit.get_instance_id()

# -----------------------------------------------------------------
# Factories
# -----------------------------------------------------------------

## Auto-target nearest hostile.  initiative_bonus defaults to 1.0 (defence).
static func create_auto(initiative_bonus: float = 1.0) -> UnitActionAttack:
	var action = UnitActionAttack.new()
	action._initiative_bonus = initiative_bonus
	return action

## Focused attack on a specific target.  Pass a > 1.0 bonus when the player
## explicitly commanded this attack via the ActionGateway.
static func create_focused(target: Node2D, initiative_bonus: float = 1.0) -> UnitActionAttack:
	var action = UnitActionAttack.new()
	action._target_node = target
	action._initiative_bonus = initiative_bonus
	return action
