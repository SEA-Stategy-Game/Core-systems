extends GutTest

## -----------------------------------------------------------------------
## Unit tests for UnitActionAttack.gd
## -----------------------------------------------------------------------
## Combat decisions tested in isolation: stat pickup, cooldown gating,
## the player-initiative damage bonus, and completion when no hostiles
## remain.  Chasing across a navmesh is engine territory and is covered
## by the acceptance tests instead.
## -----------------------------------------------------------------------

const UNIT_SCENE = preload("res://Entities/Units/character_body_2dtets.tscn")

## Hostile stand-in within melee fallback range.  Deliberately NOT in the
## "units" group so the action's global fallback scan finds no further
## hostiles once this one dies.
class FakeTarget extends Node2D:
	var entity_id: int = 880
	var player_id: int = 1
	var hp: int = 100

	func get_player_id() -> int:
		return player_id

	func take_damage(amount: int) -> void:
		hp -= amount

	func is_alive() -> bool:
		return hp > 0

var unit: Unit
var target: FakeTarget

func before_each() -> void:
	unit = UNIT_SCENE.instantiate() as Unit
	add_child_autofree(unit)
	unit.global_position = Vector2.ZERO

	target = FakeTarget.new()
	add_child_autofree(target)
	# Within UnitActionAttack.FALLBACK_MELEE_DIST so no chasing is needed.
	target.global_position = Vector2(10, 0)

func after_each() -> void:
	unit = null
	target = null

# ----------
# factories
# ----------
func test_create_focused_stores_target_and_initiative_bonus() -> void:
	var action := UnitActionAttack.create_focused(target, 1.25)

	assert_eq(action._target_node, target)
	assert_eq(action._initiative_bonus, 1.25)

func test_create_auto_defaults_to_no_initiative_bonus() -> void:
	var action := UnitActionAttack.create_auto()

	assert_null(action._target_node)
	assert_eq(action._initiative_bonus, 1.0)

# ----------
# lifecycle
# ----------
func test_start_reads_combat_stats_from_the_unit() -> void:
	unit.attack_damage = 20
	unit.attack_cooldown = 2.0
	unit.player_id = 3
	var action := UnitActionAttack.create_focused(target)

	action.start(unit, target)

	assert_eq(action._state, IUnitAction.ActionState.RUNNING)
	assert_eq(action._attack_damage, 20)
	assert_eq(action._attack_cooldown, 2.0)
	assert_eq(action._attacker_player_id, 3)

func test_first_tick_in_range_applies_damage_with_initiative_bonus() -> void:
	var action := UnitActionAttack.create_focused(target, 1.5)
	action.start(unit, target)

	action.tick(unit, 0.016)

	# base 10 damage x 1.5 initiative = 15
	assert_eq(target.hp, 85)

func test_damage_is_gated_by_the_attack_cooldown() -> void:
	var action := UnitActionAttack.create_focused(target, 1.5)
	action.start(unit, target)
	action.tick(unit, 0.016)  # first hit, cooldown re-armed

	action.tick(unit, 0.1)  # cooldown still running

	assert_eq(target.hp, 85)

func test_second_hit_lands_after_cooldown_elapses() -> void:
	var action := UnitActionAttack.create_focused(target, 1.5)
	action.start(unit, target)
	action.tick(unit, 0.016)  # first hit

	action.tick(unit, 1.05)  # cooldown (1.0s) has elapsed

	assert_eq(target.hp, 70)

func test_action_completes_after_target_dies_and_no_hostiles_remain() -> void:
	target.hp = 10
	var action := UnitActionAttack.create_focused(target, 1.5)
	action.start(unit, target)
	action.tick(unit, 0.016)  # kills the target (15 damage)
	assert_false(target.is_alive())

	var state: int = action.tick(unit, 0.016)

	assert_eq(state, IUnitAction.ActionState.COMPLETED)

func test_auto_attack_completes_immediately_when_no_hostiles_exist() -> void:
	var action := UnitActionAttack.create_auto()
	target.free()  # remove the only hostile
	action.start(unit, null)

	var state: int = action.tick(unit, 0.016)

	assert_eq(state, IUnitAction.ActionState.COMPLETED)

func test_cancel_fails_the_action_and_stops_the_unit() -> void:
	var action := UnitActionAttack.create_focused(target)
	action.start(unit, target)
	unit.velocity = Vector2(5, 5)

	action.cancel(unit)

	assert_eq(action._state, IUnitAction.ActionState.FAILED)
	assert_eq(unit.velocity, Vector2.ZERO)

# --------------
# serialization
# --------------
func test_serialize_reports_combat_parameters() -> void:
	var action := UnitActionAttack.create_focused(target, 1.25)
	action.start(unit, target)

	var data := action.serialize()

	assert_eq(data["type"], "ATTACK")
	assert_eq(data["target_id"], 880)
	assert_eq(data["attack_damage"], 10)
	assert_eq(data["initiative_bonus"], 1.25)
	assert_eq(data["state"], IUnitAction.ActionState.RUNNING)
