extends GutTest

const INITIAL_HEALTH = 100
const DAMAGE_AMOUNT = 25
const OVERKILL_DAMAGE = 150

var entity: Entity

func before_each():
	entity = Entity.new()
	entity.entity_id = 1
	entity.max_health = INITIAL_HEALTH
	entity.current_health = entity.max_health

func after_each():
	if entity and not entity.is_queued_for_deletion():
		entity.queue_free()

# initialization tests
func test_entity_initializes_with_default_max_health():
	var new_entity = Entity.new()
	new_entity.max_health = 100
	new_entity._ready()
	assert_eq(new_entity.max_health, 100)


func test_entity_initializes_with_custom_max_health():
	entity.max_health = 200
	entity._ready()
	assert_eq(entity.current_health, 200)


func test_entity_ready_sets_current_health_to_max_health():
	entity.max_health = 150
	entity._ready()
	assert_eq(entity.current_health, entity.max_health)


func test_entity_added_to_units_group_on_ready():
	entity._ready()
	assert_has(entity.get_groups(), "units")


func test_entity_is_not_selected_by_default():
	assert_false(entity.is_selected)

# health tests
func test_take_damage_reduces_current_health():
	entity._ready()
	var initial_health = entity.current_health
	entity.take_damage(DAMAGE_AMOUNT)
	assert_eq(entity.current_health, initial_health - DAMAGE_AMOUNT)


func test_take_damage_with_zero_damage():
	entity._ready()
	var initial_health = entity.current_health
	entity.take_damage(0)
	assert_eq(entity.current_health, initial_health)


func test_take_damage_multiple_times():
	entity._ready()
	entity.take_damage(10)
	entity.take_damage(15)
	entity.take_damage(20)
	assert_eq(entity.current_health, INITIAL_HEALTH - 45)


func test_take_damage_triggers_die_when_health_reaches_zero():
	entity._ready()
	entity.take_damage(INITIAL_HEALTH)
	assert_true(entity.is_queued_for_deletion())


func test_take_damage_triggers_die_when_health_goes_below_zero():
	entity._ready()
	entity.take_damage(OVERKILL_DAMAGE)
	assert_true(entity.is_queued_for_deletion())

# selection tests
func test_set_selected_true_marks_entity_as_selected():
	entity.set_selected(true)
	assert_true(entity.is_selected)

func test_set_selected_false_unmarks_entity_as_selected():
	entity.is_selected = true
	entity.set_selected(false)
	assert_false(entity.is_selected)

func test_set_selected_toggles_selection_state():
	assert_false(entity.is_selected)
	entity.set_selected(true)
	assert_true(entity.is_selected)
	entity.set_selected(false)
	assert_false(entity.is_selected)

func test_set_selected_without_selection_box_does_not_crash():
	entity.set_selected(true)
	assert_true(entity.is_selected)
	entity.set_selected(false)
	assert_false(entity.is_selected)

# edge cases
func test_entity_with_very_high_max_health():
	entity.max_health = 999999
	entity._ready()
	assert_eq(entity.current_health, 999999)
	entity.take_damage(500000)
	assert_eq(entity.current_health, 499999)

func test_entity_with_one_max_health():
	entity.max_health = 1
	entity._ready()
	assert_eq(entity.current_health, 1)
	entity.take_damage(1)
	assert_true(entity.is_queued_for_deletion())

func test_multiple_damage_calls_after_death():
	entity._ready()
	entity.take_damage(INITIAL_HEALTH)
	assert_true(entity.is_queued_for_deletion())
	entity.take_damage(10)
	assert_true(entity.is_queued_for_deletion())

func test_entity_id_is_preserved():
	entity.entity_id = 42
	entity._ready()
	entity.take_damage(50)
	entity.set_selected(true)
	assert_eq(entity.entity_id, 42)

# state consistency tests
func test_entity_maintains_state_after_selection_toggle():
	entity._ready()
	entity.take_damage(25)
	var health_before = entity.current_health
	entity.set_selected(true)
	entity.set_selected(false)
	assert_eq(entity.current_health, health_before)

# integration scenarios tests
func test_combat_scenario():
	entity._ready()
	assert_eq(entity.current_health, INITIAL_HEALTH)
	entity.take_damage(20)
	assert_eq(entity.current_health, 80)
	entity.take_damage(30)
	assert_eq(entity.current_health, 50)
	entity.take_damage(0)
	assert_eq(entity.current_health, 50)
	entity.take_damage(40)
	assert_eq(entity.current_health, 10)
	entity.take_damage(0)
	assert_eq(entity.current_health, 10)
	entity.take_damage(15)  # Final blow (overkill)
	assert_true(entity.is_queued_for_deletion())


func test_entity_state_snapshot():
	entity._ready()
	var initial_state = {
		"health": entity.current_health,
		"selected": entity.is_selected,
		"id": entity.entity_id
	}
	entity.take_damage(25)
	entity.set_selected(true)
	var final_state = {
		"health": entity.current_health,
		"selected": entity.is_selected,
		"id": entity.entity_id
	}
	assert_eq(final_state.health, initial_state.health - 25)
	assert_eq(final_state.selected, true)
	assert_eq(final_state.id, initial_state.id)
