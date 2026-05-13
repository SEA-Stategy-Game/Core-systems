extends GutTest

## -----------------------------------------------------------------------
## Unit tests for UnitActionExplode.gd
## -----------------------------------------------------------------------
## AoE damage rules: full damage at the centre, linear falloff to the
## radius edge, nothing outside, friendlies skipped, neutrals (resources)
## damaged.  The action must finish in a single tick.
## -----------------------------------------------------------------------

const UNIT_SCENE = preload("res://Entities/Units/character_body_2dtets.tscn")

const RADIUS := 64.0
const DAMAGE := 25

class FakeVictim extends Node2D:
	var player_id: int = 1
	var damage_taken: int = 0

	func get_player_id() -> int:
		return player_id

	func take_damage(amount: int) -> void:
		damage_taken += amount

var unit: Unit

func before_each() -> void:
	unit = UNIT_SCENE.instantiate() as Unit
	add_child_autofree(unit)
	unit.global_position = Vector2(300, 300)  # outside its own blast radius

func after_each() -> void:
	unit = null

func _make_victim(pos: Vector2, pid: int = 1, group: String = "units") -> FakeVictim:
	var victim := FakeVictim.new()
	victim.player_id = pid
	victim.add_to_group(group)
	add_child_autofree(victim)
	victim.global_position = pos
	return victim

# ----------
# lifecycle
# ----------
func test_explosion_completes_in_a_single_tick() -> void:
	var action := UnitActionExplode.create(Vector2.ZERO, RADIUS, DAMAGE)
	action.start(unit, null)

	var state: int = action.tick(unit, 0.016)

	assert_eq(state, IUnitAction.ActionState.COMPLETED)

func test_create_self_centres_blast_on_the_unit() -> void:
	var action := UnitActionExplode.create_self(RADIUS, DAMAGE)

	action.start(unit, null)

	assert_eq(action._center, unit.global_position)

func test_cancel_fails_the_action() -> void:
	var action := UnitActionExplode.create(Vector2.ZERO, RADIUS, DAMAGE)
	action.start(unit, null)

	action.cancel(unit)

	assert_eq(action._state, IUnitAction.ActionState.FAILED)

# ----------
# damage rules
# ----------
func test_hostile_at_centre_takes_full_damage() -> void:
	var victim := _make_victim(Vector2.ZERO)
	var action := UnitActionExplode.create(Vector2.ZERO, RADIUS, DAMAGE)
	action.start(unit, null)

	action.tick(unit, 0.016)

	assert_eq(victim.damage_taken, DAMAGE)

func test_damage_falls_off_linearly_with_distance() -> void:
	# Halfway to the edge: scale = lerp(1.0, 0.6, 0.5) = 0.8 -> 20 damage.
	var victim := _make_victim(Vector2(RADIUS / 2.0, 0))
	var action := UnitActionExplode.create(Vector2.ZERO, RADIUS, DAMAGE)
	action.start(unit, null)

	action.tick(unit, 0.016)

	assert_eq(victim.damage_taken, 20)

func test_hostile_at_radius_edge_takes_falloff_damage() -> void:
	# At the edge: scale = 0.6 -> 15 damage.
	var victim := _make_victim(Vector2(RADIUS, 0))
	var action := UnitActionExplode.create(Vector2.ZERO, RADIUS, DAMAGE)
	action.start(unit, null)

	action.tick(unit, 0.016)

	assert_eq(victim.damage_taken, 15)

func test_hostile_outside_radius_is_unharmed() -> void:
	var victim := _make_victim(Vector2(RADIUS + 10.0, 0))
	var action := UnitActionExplode.create(Vector2.ZERO, RADIUS, DAMAGE)
	action.start(unit, null)

	action.tick(unit, 0.016)

	assert_eq(victim.damage_taken, 0)

func test_friendly_inside_radius_is_skipped() -> void:
	var friendly := _make_victim(Vector2.ZERO, unit.player_id)
	var action := UnitActionExplode.create(Vector2.ZERO, RADIUS, DAMAGE)
	action.start(unit, null)

	action.tick(unit, 0.016)

	assert_eq(friendly.damage_taken, 0)

func test_neutral_resource_inside_radius_is_damaged() -> void:
	var neutral := _make_victim(Vector2.ZERO, -1, "resources")
	var action := UnitActionExplode.create(Vector2.ZERO, RADIUS, DAMAGE)
	action.start(unit, null)

	action.tick(unit, 0.016)

	assert_eq(neutral.damage_taken, DAMAGE)

# --------------
# serialization
# --------------
func test_serialize_reports_blast_parameters() -> void:
	var action := UnitActionExplode.create(Vector2(5, 6), RADIUS, DAMAGE)

	var data := action.serialize()

	assert_eq(data["type"], "EXPLODE")
	assert_eq(data["center"]["x"], 5.0)
	assert_eq(data["center"]["y"], 6.0)
	assert_eq(data["radius"], RADIUS)
	assert_eq(data["damage"], DAMAGE)
