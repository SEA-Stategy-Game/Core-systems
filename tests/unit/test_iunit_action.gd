extends GutTest

## -----------------------------------------------------------------------
## Unit tests for IUnitAction.gd
## -----------------------------------------------------------------------
## GDScript has no formal interfaces, so the CommandQueue relies on the
## duck-typing validator is_implemented_by().  These tests pin down that
## contract and verify every concrete action in Logic/Actions satisfies it.
## -----------------------------------------------------------------------

class FullContract extends RefCounted:
	func start(_unit: CharacterBody2D, _target: Node2D) -> void:
		pass

	func tick(_unit: CharacterBody2D, _delta: float) -> int:
		return IUnitAction.ActionState.COMPLETED

	func cancel(_unit: CharacterBody2D) -> void:
		pass

	func serialize() -> Dictionary:
		return {}

class MissingTick extends RefCounted:
	func start(_unit: CharacterBody2D, _target: Node2D) -> void:
		pass

	func cancel(_unit: CharacterBody2D) -> void:
		pass

	func serialize() -> Dictionary:
		return {}

class MissingSerialize extends RefCounted:
	func start(_unit: CharacterBody2D, _target: Node2D) -> void:
		pass

	func tick(_unit: CharacterBody2D, _delta: float) -> int:
		return IUnitAction.ActionState.COMPLETED

	func cancel(_unit: CharacterBody2D) -> void:
		pass

# ---------------------
# duck-typing validator
# ---------------------
func test_is_implemented_by_returns_false_for_null() -> void:
	assert_false(IUnitAction.is_implemented_by(null))

func test_is_implemented_by_returns_true_for_full_contract() -> void:
	assert_true(IUnitAction.is_implemented_by(FullContract.new()))

func test_is_implemented_by_returns_false_when_tick_is_missing() -> void:
	assert_false(IUnitAction.is_implemented_by(MissingTick.new()))

func test_is_implemented_by_returns_false_when_serialize_is_missing() -> void:
	assert_false(IUnitAction.is_implemented_by(MissingSerialize.new()))

# -----------------------------
# concrete actions conformance
# -----------------------------
func test_unit_action_move_implements_contract() -> void:
	assert_true(IUnitAction.is_implemented_by(UnitActionMove.create(Vector2.ZERO)))

func test_unit_action_harvest_implements_contract() -> void:
	assert_true(IUnitAction.is_implemented_by(UnitActionHarvest.create(null)))

func test_unit_action_attack_implements_contract() -> void:
	assert_true(IUnitAction.is_implemented_by(UnitActionAttack.create_auto()))

func test_unit_action_construct_implements_contract() -> void:
	assert_true(IUnitAction.is_implemented_by(UnitActionConstruct.create("", Vector2.ZERO)))

func test_unit_action_explode_implements_contract() -> void:
	assert_true(IUnitAction.is_implemented_by(UnitActionExplode.create(Vector2.ZERO)))

func test_unit_action_fire_implements_contract() -> void:
	assert_true(IUnitAction.is_implemented_by(UnitActionFire.create_single(null)))

# ---------------------
# abstract base safety
# ---------------------
func test_base_tick_returns_failed_so_a_bad_action_cannot_hang_the_queue() -> void:
	var base := IUnitAction.new()

	var state := base.tick(null, 0.1)

	assert_eq(state, IUnitAction.ActionState.FAILED)
