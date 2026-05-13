extends GutTest

## -----------------------------------------------------------------------
## Unit tests for SenseAPI.gd
## -----------------------------------------------------------------------
## The SenseAPI is the read-only facade the AI Planning team queries.
## These tests verify it reports snapshots (dictionaries), filters by
## player / radius, and never returns live node references.
## -----------------------------------------------------------------------

const UNIT_SCENE = preload("res://Entities/Units/character_body_2dtets.tscn")

const UNIT_A_ID := 9301
const UNIT_B_ID := 9302

## Never-ending fake action used to make a unit "busy".
class RunningAction extends RefCounted:
	func start(_unit: CharacterBody2D, _target: Node2D) -> void:
		pass

	func tick(_unit: CharacterBody2D, _delta: float) -> int:
		return IUnitAction.ActionState.RUNNING

	func cancel(_unit: CharacterBody2D) -> void:
		pass

	func serialize() -> Dictionary:
		return {"type": "running", "state": IUnitAction.ActionState.RUNNING}

class FakeResource extends Node2D:
	var entity_id: int = -1
	var amount: int = 1
	var currentTime: float = 5.0

class FakeBuilding extends Node2D:
	var entity_id: int = -1
	var player_id: int = 0
	var current_health: int = 100

var sense: SenseAPI
var unit_a: Unit
var unit_b: Unit
var world: Node2D
var objects: Node2D
var houses: Node2D

func before_each() -> void:
	_reset_game_stockpiles()

	sense = SenseAPI.new(get_tree())

	# Scene fixture mirroring the production World layout that the
	# SenseAPI navigates (World/Objects for resources, World/Houses
	# for buildings).
	world = Node2D.new()
	world.name = "World"
	objects = Node2D.new()
	objects.name = "Objects"
	world.add_child(objects)
	houses = Node2D.new()
	houses.name = "Houses"
	world.add_child(houses)
	get_tree().root.add_child(world)

	unit_a = _make_unit(UNIT_A_ID, 0, Vector2(0, 0))
	unit_b = _make_unit(UNIT_B_ID, 1, Vector2(100, 0))

func after_each() -> void:
	if is_instance_valid(world):
		world.free()
	world = null
	sense = null
	unit_a = null
	unit_b = null
	_reset_game_stockpiles()

func _reset_game_stockpiles() -> void:
	Game.player_resources.clear()
	Game.Wood = 0
	Game.Stone = 0

func _make_unit(eid: int, pid: int, pos: Vector2) -> Unit:
	var u := UNIT_SCENE.instantiate() as Unit
	u.entity_id = eid
	u.player_id = pid
	add_child_autofree(u)
	u.global_position = pos
	return u

func _make_resource(eid: int, pos: Vector2) -> FakeResource:
	var r := FakeResource.new()
	r.entity_id = eid
	objects.add_child(r)
	r.global_position = pos
	return r

func _make_building(eid: int, pid: int, pos: Vector2) -> FakeBuilding:
	var b := FakeBuilding.new()
	b.entity_id = eid
	b.player_id = pid
	houses.add_child(b)
	b.global_position = pos
	return b

func _ids(snapshots: Array) -> Array:
	return snapshots.map(func(s): return s["id"])

# --------------
# unit queries
# --------------
func test_get_all_units_returns_one_snapshot_per_unit() -> void:
	var result := sense.get_all_units()

	assert_eq(result.size(), 2)
	assert_has(_ids(result), UNIT_A_ID)
	assert_has(_ids(result), UNIT_B_ID)

func test_unit_snapshot_contains_state_not_node_references() -> void:
	var snapshot: Dictionary = sense.get_unit(UNIT_A_ID)

	assert_eq(snapshot["id"], UNIT_A_ID)
	assert_eq(snapshot["player_id"], 0)
	assert_eq(snapshot["health"], unit_a.current_health)
	assert_eq(snapshot["position"]["x"], 0.0)
	assert_true(snapshot["is_idle"])
	assert_eq(snapshot["pending_actions"], 0)

func test_get_player_units_filters_by_owner() -> void:
	var result := sense.get_player_units(0)

	assert_eq(_ids(result), [UNIT_A_ID])

func test_get_unit_returns_empty_dictionary_for_unknown_id() -> void:
	assert_eq(sense.get_unit(123456), {})

func test_get_units_near_filters_by_radius() -> void:
	var result := sense.get_units_near(Vector2.ZERO, 50.0)

	assert_eq(_ids(result), [UNIT_A_ID])

func test_get_idle_and_busy_units_reflect_the_command_queue() -> void:
	unit_a.command_queue.enqueue(RunningAction.new())

	assert_eq(sense.get_idle_units(0), [])
	assert_eq(sense.get_busy_units(0), [UNIT_A_ID])
	assert_eq(sense.get_idle_units(1), [UNIT_B_ID])
	assert_eq(sense.get_busy_units(1), [])

func test_get_unit_status_exposes_the_running_action_state() -> void:
	unit_a.command_queue.enqueue(RunningAction.new())
	unit_a.command_queue.process_tick(0.016)

	var status: Dictionary = sense.get_unit_status(UNIT_A_ID)

	assert_eq(status["action_state"], IUnitAction.ActionState.RUNNING)
	assert_eq(status["current_action"]["type"], "running")

func test_get_unit_status_reports_null_action_when_idle() -> void:
	var status: Dictionary = sense.get_unit_status(UNIT_B_ID)

	assert_null(status["current_action"])
	assert_eq(status["action_state"], -1)

# ------------------
# resource queries
# ------------------
func test_get_all_resources_lists_world_objects() -> void:
	_make_resource(501, Vector2(10, 10))
	_make_resource(502, Vector2(400, 400))

	var result := sense.get_all_resources()

	assert_eq(result.size(), 2)
	assert_has(_ids(result), 501)
	assert_has(_ids(result), 502)

func test_get_resources_near_filters_by_radius() -> void:
	_make_resource(501, Vector2(10, 10))
	_make_resource(502, Vector2(400, 400))

	var result := sense.get_resources_near(Vector2.ZERO, 100.0)

	assert_eq(_ids(result), [501])

# ------------------
# building queries
# ------------------
func test_get_all_buildings_lists_world_houses() -> void:
	_make_building(601, 0, Vector2(50, 50))

	var result := sense.get_all_buildings()

	assert_eq(_ids(result), [601])
	assert_eq(result[0]["player_id"], 0)

func test_get_buildings_near_filters_by_radius() -> void:
	_make_building(601, 0, Vector2(50, 50))
	_make_building(602, 1, Vector2(900, 900))

	var result := sense.get_buildings_near(Vector2.ZERO, 100.0)

	assert_eq(_ids(result), [601])

# ------------------
# global game state
# ------------------
func test_get_resources_stockpile_mirrors_player_zero() -> void:
	Game.add_resource(0, "wood", 3)
	Game.add_resource(0, "stone", 1)

	var stockpile := sense.get_resources_stockpile()

	assert_eq(stockpile["wood"], 3)
	assert_eq(stockpile["stone"], 1)

func test_get_tick_count_defaults_when_no_world_tick_manager() -> void:
	assert_eq(sense.get_tick_count(), -1)
