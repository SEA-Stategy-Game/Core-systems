extends GutTest

const UnitScript = preload("res://Entities/Units/Unit.gd")

class TestMapResource extends MapResource:
	var deplete_called: bool = false
	var finished_called: bool = false

	func deplete() -> void:
		deplete_called = true

	func on_finished_harvesting() -> void:
		finished_called = true
		super.on_finished_harvesting()

var resource: TestMapResource

func before_each() -> void:
	resource = TestMapResource.new()

	var progress_bar := ProgressBar.new()
	progress_bar.name = "ProgressBar"

	var timer := Timer.new()
	timer.name = "Timer"
	progress_bar.add_child(timer)

	resource.add_child(progress_bar)

	resource.entity_id = 1
	resource.resource_name = "test resource"
	resource.totalTime = 10.0
	resource.amount = 2
	resource.maxAmount = 2

	add_child_autofree(resource)

func after_each() -> void:
	resource = null

# unit tests
func test_resource_initializes_current_time_from_total_time() -> void:
	assert_eq(resource.currentTime, resource.totalTime)

func test_resource_harvest_reduces_amount_by_one() -> void:
	resource.amount = 2
	resource.harvest()
	assert_eq(resource.amount, 1)

func test_resource_harvest_calls_deplete_at_zero() -> void:
	resource.amount = 1
	resource.harvest()
	assert_eq(resource.amount, 0)
	assert_true(resource.deplete_called)

func test_resource_harvest_does_not_change_when_already_zero() -> void:
	resource.amount = 0
	resource.harvest()
	assert_eq(resource.amount, 0)
	assert_false(resource.deplete_called)

func test_resource_timer_timeout_reduces_time_by_units_harvesting() -> void:
	resource.currentTime = 10.0
	resource.units_harvesting = 3
	resource._on_timer_timeout()
	assert_eq(resource.currentTime, 7.0)

func test_resource_timer_timeout_finishes_when_time_reaches_zero() -> void:
	resource.currentTime = 1.0
	resource.units_harvesting = 1
	resource._on_timer_timeout()
	assert_true(resource.finished_called)
	assert_true(resource.is_queued_for_deletion())

# integration tests
func test_unit_entering_harvest_area_increments_counter_and_starts_timer() -> void:
	var unit = UnitScript.new()
	assert_true(resource.timer.is_stopped())
	resource._on_harvest_area_body_entered(unit)
	assert_eq(resource.units_harvesting, 1)
	assert_false(resource.timer.is_stopped())

func test_unit_exiting_harvest_area_decrements_counter_and_stops_timer_at_zero() -> void:
	var unit = UnitScript.new()
	resource._on_harvest_area_body_entered(unit)
	assert_eq(resource.units_harvesting, 1)
	assert_false(resource.timer.is_stopped())
	resource._on_harvest_area_body_exited(unit)
	assert_eq(resource.units_harvesting, 0)
	assert_true(resource.timer.is_stopped())

func test_non_unit_body_does_not_affect_harvesting_counter() -> void:
	var body := Node2D.new()
	resource._on_harvest_area_body_entered(body)
	assert_eq(resource.units_harvesting, 0)
	resource._on_harvest_area_body_exited(body)
	assert_eq(resource.units_harvesting, 0)

# edge cases tets
func test_multiple_units_harvest_simultaneously() -> void:
	var unit_a = UnitScript.new()
	var unit_b = UnitScript.new()
	resource._on_harvest_area_body_entered(unit_a)
	resource._on_harvest_area_body_entered(unit_b)
	assert_eq(resource.units_harvesting, 2)

func test_timer_timeout_with_zero_harvesters_keeps_time_unchanged() -> void:
	resource.currentTime = 10.0
	resource.units_harvesting = 0
	resource._on_timer_timeout()
	assert_eq(resource.currentTime, 10.0)

func test_exit_without_prior_enter_can_go_negative_current_behavior() -> void:
	var unit = UnitScript.new()
	resource.units_harvesting = 0
	resource._on_harvest_area_body_exited(unit)
	assert_eq(resource.units_harvesting, -1)

func test_large_harvester_count_reduces_time_correctly() -> void:
	resource.currentTime = 100.0
	resource.units_harvesting = 25
	resource._on_timer_timeout()
	assert_eq(resource.currentTime, 75.0)