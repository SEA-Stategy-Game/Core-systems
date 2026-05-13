extends GutTest

## -----------------------------------------------------------------------
## Unit tests for UnitActionFire.gd
## -----------------------------------------------------------------------
## Uses a fake ranged unit that records fire_projectile() calls, so the
## firing state machine (single shot, auto-repeat, cooldown, target death)
## is tested without spawning real Projectile scenes -- those have their
## own tests in test_projectile.gd.
## -----------------------------------------------------------------------

class FakeRangedUnit extends CharacterBody2D:
	var attack_cooldown: float = 1.0
	var shots: Array = []
	var hostiles_in_range: Array = []

	func get_hostiles_in_range() -> Array:
		return hostiles_in_range

	func fire_projectile(target) -> void:
		shots.append(target)

class FakeTarget extends Node2D:
	var alive: bool = true

	func is_alive() -> bool:
		return alive

var unit: FakeRangedUnit
var target: FakeTarget

func before_each() -> void:
	unit = FakeRangedUnit.new()
	add_child_autofree(unit)
	unit.global_position = Vector2.ZERO

	target = FakeTarget.new()
	add_child_autofree(target)
	target.global_position = Vector2(100, 0)
	unit.hostiles_in_range = [target]

func after_each() -> void:
	unit = null
	target = null

# ----------
# lifecycle
# ----------
func test_single_shot_fires_once_and_completes() -> void:
	var action := UnitActionFire.create_single(target)
	action.start(unit, target)

	var state: int = action.tick(unit, 0.016)

	assert_eq(unit.shots.size(), 1)
	assert_eq(unit.shots[0], target)
	assert_eq(state, IUnitAction.ActionState.COMPLETED)

func test_auto_fire_keeps_shooting_while_target_lives() -> void:
	var action := UnitActionFire.create_auto(target)
	action.start(unit, target)

	action.tick(unit, 0.016)  # first shot
	var state: int = action.tick(unit, 1.05)  # cooldown elapsed -> second shot

	assert_eq(unit.shots.size(), 2)
	assert_eq(state, IUnitAction.ActionState.RUNNING)

func test_cooldown_gates_successive_shots() -> void:
	var action := UnitActionFire.create_auto(target)
	action.start(unit, target)
	action.tick(unit, 0.016)  # first shot, cooldown re-armed

	action.tick(unit, 0.1)  # cooldown still running

	assert_eq(unit.shots.size(), 1)

func test_completes_when_target_dies() -> void:
	var action := UnitActionFire.create_auto(target)
	action.start(unit, target)
	action.tick(unit, 0.016)

	target.alive = false
	var state: int = action.tick(unit, 1.05)

	assert_eq(state, IUnitAction.ActionState.COMPLETED)
	assert_eq(unit.shots.size(), 1)

func test_completes_when_target_is_freed() -> void:
	var action := UnitActionFire.create_auto(target)
	action.start(unit, target)
	unit.hostiles_in_range = []
	target.free()

	var state: int = action.tick(unit, 0.016)

	assert_eq(state, IUnitAction.ActionState.COMPLETED)

func test_moves_toward_target_when_out_of_range_without_firing() -> void:
	unit.hostiles_in_range = []
	var action := UnitActionFire.create_auto(target)
	action.start(unit, target)

	var state: int = action.tick(unit, 0.016)

	assert_eq(state, IUnitAction.ActionState.RUNNING)
	assert_eq(unit.shots.size(), 0)
	assert_gt(unit.velocity.x, 0.0)  # heading toward the target at (100, 0)

func test_cancel_fails_the_action_and_stops_the_unit() -> void:
	var action := UnitActionFire.create_auto(target)
	action.start(unit, target)
	unit.velocity = Vector2(5, 0)

	action.cancel(unit)

	assert_eq(action._state, IUnitAction.ActionState.FAILED)
	assert_eq(unit.velocity, Vector2.ZERO)

# --------------
# serialization
# --------------
func test_serialize_reports_shots_fired_and_state() -> void:
	var action := UnitActionFire.create_single(target)
	action.start(unit, target)
	action.tick(unit, 0.016)

	var data := action.serialize()

	assert_eq(data["type"], "FIRE")
	assert_eq(data["shots_fired"], 1)
	assert_eq(data["state"], IUnitAction.ActionState.COMPLETED)
