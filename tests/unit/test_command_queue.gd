extends GutTest

## -----------------------------------------------------------------------
## Unit tests for CommandQueue.gd
## -----------------------------------------------------------------------
## The CommandQueue is the per-unit FIFO that drives all AI actions.
## These tests run it in isolation with scripted fake actions, so we test
## what the queue decides (lifecycle, ordering, signals, capacity) -- not
## what the engine draws.
## -----------------------------------------------------------------------

const UNIT_ID := 77

## Scripted IUnitAction stand-in: completes (or fails) after a fixed
## number of ticks and records every lifecycle call.
class FakeAction extends RefCounted:
	var started: bool = false
	var cancelled: bool = false
	var tick_count: int = 0
	var ticks_until_done: int = 1
	var result_state: int = IUnitAction.ActionState.COMPLETED
	var label: String = "fake"

	func start(_unit: CharacterBody2D, _target: Node2D) -> void:
		started = true

	func tick(_unit: CharacterBody2D, _delta: float) -> int:
		tick_count += 1
		if tick_count >= ticks_until_done:
			return result_state
		return IUnitAction.ActionState.RUNNING

	func cancel(_unit: CharacterBody2D) -> void:
		cancelled = true

	func serialize() -> Dictionary:
		return {"type": label, "state": result_state}

## Deliberately does NOT implement the IUnitAction contract.
class NotAnAction extends RefCounted:
	var marker: bool = true

var cq: CommandQueue

func before_each() -> void:
	cq = CommandQueue.new()
	cq.setup(null, UNIT_ID)

func after_each() -> void:
	cq = null

func _make_action(ticks: int = 1, state: int = IUnitAction.ActionState.COMPLETED, label: String = "fake") -> FakeAction:
	var action := FakeAction.new()
	action.ticks_until_done = ticks
	action.result_state = state
	action.label = label
	return action

# --------------------
# enqueue validation
# --------------------
func test_enqueue_accepts_conforming_action() -> void:
	var ok := cq.enqueue(_make_action())

	assert_true(ok)
	assert_eq(cq.pending_count(), 1)

func test_enqueue_rejects_object_without_action_contract() -> void:
	var ok := cq.enqueue(NotAnAction.new())

	assert_false(ok)
	assert_eq(cq.pending_count(), 0)

func test_enqueue_rejects_null() -> void:
	var ok := cq.enqueue(null)

	assert_false(ok)
	assert_eq(cq.pending_count(), 0)

func test_enqueue_rejects_when_queue_is_full() -> void:
	for i in range(CommandQueue.MAX_QUEUE_SIZE):
		assert_true(cq.enqueue(_make_action()))

	var overflow_ok := cq.enqueue(_make_action())

	assert_false(overflow_ok)
	assert_eq(cq.pending_count(), CommandQueue.MAX_QUEUE_SIZE)

# --------------------
# idle state
# --------------------
func test_new_queue_is_idle() -> void:
	assert_true(cq.is_idle())

func test_queue_with_pending_action_is_not_idle() -> void:
	cq.enqueue(_make_action())

	assert_false(cq.is_idle())

func test_queue_with_running_action_is_not_idle() -> void:
	cq.enqueue(_make_action(3))

	cq.process_tick(0.1)

	# Popped into _current_action: pending is 0 but the queue is busy.
	assert_eq(cq.pending_count(), 0)
	assert_false(cq.is_idle())

# --------------------
# lifecycle processing
# --------------------
func test_process_tick_starts_and_ticks_the_first_action() -> void:
	var action := _make_action(2)
	cq.enqueue(action)

	cq.process_tick(0.1)

	assert_true(action.started)
	assert_eq(action.tick_count, 1)

func test_completed_action_emits_action_completed_with_unit_id() -> void:
	cq.enqueue(_make_action(1, IUnitAction.ActionState.COMPLETED, "move"))
	watch_signals(cq)

	cq.process_tick(0.1)

	assert_signal_emitted(cq, "action_completed")
	var params = get_signal_parameters(cq, "action_completed", 0)
	assert_eq(params[0], UNIT_ID)
	assert_eq(params[1]["type"], "move")

func test_failed_action_emits_action_failed() -> void:
	cq.enqueue(_make_action(1, IUnitAction.ActionState.FAILED, "harvest"))
	watch_signals(cq)

	cq.process_tick(0.1)

	assert_signal_emitted(cq, "action_failed")
	var params = get_signal_parameters(cq, "action_failed", 0)
	assert_eq(params[0], UNIT_ID)
	assert_true(cq.is_idle())

func test_queue_empty_emitted_after_last_action_completes() -> void:
	cq.enqueue(_make_action())
	watch_signals(cq)

	cq.process_tick(0.1)

	assert_signal_emitted_with_parameters(cq, "queue_empty", [UNIT_ID])

func test_process_tick_on_empty_queue_emits_queue_empty() -> void:
	watch_signals(cq)

	cq.process_tick(0.1)

	assert_signal_emitted_with_parameters(cq, "queue_empty", [UNIT_ID])

func test_actions_are_processed_in_fifo_order() -> void:
	var first := _make_action(1, IUnitAction.ActionState.COMPLETED, "first")
	var second := _make_action(1, IUnitAction.ActionState.COMPLETED, "second")
	cq.enqueue(first)
	cq.enqueue(second)

	cq.process_tick(0.1)

	assert_true(first.started)
	assert_false(second.started)

	cq.process_tick(0.1)

	assert_true(second.started)
	assert_true(cq.is_idle())

func test_failed_action_advances_to_next_action() -> void:
	var failing := _make_action(1, IUnitAction.ActionState.FAILED, "bad")
	var next := _make_action(1, IUnitAction.ActionState.COMPLETED, "good")
	cq.enqueue(failing)
	cq.enqueue(next)

	cq.process_tick(0.1)
	cq.process_tick(0.1)

	assert_true(next.started)
	assert_true(cq.is_idle())

func test_running_action_keeps_running_across_ticks() -> void:
	var action := _make_action(3)
	cq.enqueue(action)
	watch_signals(cq)

	cq.process_tick(0.1)
	cq.process_tick(0.1)

	assert_signal_not_emitted(cq, "action_completed")
	assert_eq(action.tick_count, 2)

	cq.process_tick(0.1)

	assert_signal_emitted(cq, "action_completed")

# --------------------
# clear / cancellation
# --------------------
func test_clear_cancels_running_action() -> void:
	var action := _make_action(5)
	cq.enqueue(action)
	cq.process_tick(0.1)

	cq.clear()

	assert_true(action.cancelled)
	assert_true(cq.is_idle())

func test_clear_drops_pending_actions() -> void:
	cq.enqueue(_make_action())
	cq.enqueue(_make_action())

	cq.clear()

	assert_eq(cq.pending_count(), 0)
	assert_true(cq.is_idle())

# --------------------
# persistence
# --------------------
func test_serialize_includes_current_and_pending_actions() -> void:
	cq.enqueue(_make_action(5, IUnitAction.ActionState.COMPLETED, "running"))
	cq.enqueue(_make_action(1, IUnitAction.ActionState.COMPLETED, "queued"))
	cq.process_tick(0.1)

	var data := cq.serialize()

	assert_eq(data.size(), 2)
	assert_eq(data[0]["type"], "running")
	assert_eq(data[1]["type"], "queued")

func test_serialize_of_idle_queue_is_empty() -> void:
	assert_eq(cq.serialize().size(), 0)
