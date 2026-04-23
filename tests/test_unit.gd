extends GutTest

const UNIT_SCENE = preload("res://Entities/Units/character_body_2d.tscn")

class RunningAction extends RefCounted:
	var started: bool = false
	var ticked: bool = false

	func start(_unit: CharacterBody2D, _target: Node2D) -> void:
		started = true

	func tick(_unit: CharacterBody2D, _delta: float) -> int:
		ticked = true
		return IUnitAction.ActionState.RUNNING

	func cancel(_unit: CharacterBody2D) -> void:
		pass

	func serialize() -> Dictionary:
		return {"type": "running"}

var unit: Unit

func before_each() -> void:
	unit = UNIT_SCENE.instantiate() as Unit
	add_child_autofree(unit)

func after_each() -> void:
	unit = null

# --------------------
# initialization tests
# --------------------
func test_ready_initializes_command_queue() -> void:
	assert_not_null(unit.command_queue)

func test_ready_adds_unit_to_units_group() -> void:
	assert_has(unit.get_groups(), "units")

func test_ready_uses_entity_id_when_non_negative() -> void:
	var u := UNIT_SCENE.instantiate() as Unit
	u.entity_id = 42
	add_child_autofree(u)

	assert_eq(u.command_queue._unit_id, 42)

func test_ready_falls_back_to_instance_id_when_entity_id_is_negative() -> void:
	var u := UNIT_SCENE.instantiate() as Unit
	u.entity_id = -1
	add_child_autofree(u)

	assert_eq(u.command_queue._unit_id, u.get_instance_id())

# ----------------
# selection tests
# ----------------
func test_set_selected_true_sets_property_and_hitbox_visible() -> void:
	unit.set_selected(true)

	assert_true(unit.selected)
	assert_true(unit.box.visible)

func test_set_selected_false_sets_property_and_hitbox_hidden() -> void:
	unit.set_selected(true)
	unit.set_selected(false)

	assert_false(unit.selected)
	assert_false(unit.box.visible)

# ------------------------
# physics / command tests
# ------------------------
func test_physics_process_manual_branch_sets_velocity_towards_target() -> void:
	unit.command_queue.clear()
	unit.global_position = Vector2.ZERO
	unit.target = Vector2(100, 0)

	unit._physics_process(0.016)

	assert_eq(unit.velocity, Vector2(unit.Speed, 0))

func test_physics_process_stops_animation_when_at_target() -> void:
	unit.command_queue.clear()
	unit.target = unit.global_position
	unit.anim.play("Walk Down")

	unit._physics_process(0.016)

	assert_false(unit.anim.is_playing())

func test_physics_process_prioritizes_ai_queue_over_manual_movement() -> void:
	var action := RunningAction.new()
	unit.global_position = Vector2.ZERO
	unit.target = Vector2(100, 0)
	unit.velocity = Vector2.ZERO

	var enqueue_ok := unit.command_queue.enqueue(action)
	assert_true(enqueue_ok)

	unit._physics_process(0.016)

	assert_false(unit.is_idle)
	assert_true(action.started)
	assert_true(action.ticked)
	assert_eq(unit.velocity, Vector2.ZERO)

# --------------
# signal relays
# --------------
func test_on_cq_action_completed_relays_signal() -> void:
	watch_signals(unit)
	var payload := {"kind": "move"}

	unit._on_cq_action_completed(7, payload)

	assert_signal_emitted_with_parameters(unit, "ai_action_completed", [7, payload])

func test_on_cq_action_failed_relays_signal() -> void:
	watch_signals(unit)
	var payload := {"kind": "harvest"}

	unit._on_cq_action_failed(9, payload)

	assert_signal_emitted_with_parameters(unit, "ai_action_failed", [9, payload])

func test_on_cq_queue_empty_sets_idle_and_emits_unit_idled_when_transitioning() -> void:
	unit.is_idle = false
	watch_signals(unit)

	unit._on_cq_queue_empty(5)

	assert_true(unit.is_idle)
	assert_signal_emitted_with_parameters(unit, "unit_idled", [5])
