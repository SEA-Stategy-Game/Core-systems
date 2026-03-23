extends GutTest

var entity_scene: PackedScene
var entity: Entity

func before_each() -> void:
	entity = Entity.new()
	entity.entity_id = 1
	entity.max_health = 100

func after_each() -> void:
	entity.queue_free()

# initialization tests
func test_entity_initializes_health_to_max() -> void:
	entity._ready()
	assert_eq(entity.current_health, entity.max_health)

func test_entity_is_added_to_units_group() -> void:
	entity._ready()
	assert_true(entity.is_in_group("units"))

func test_entity_selection_state_defaults_to_false() -> void:
	assert_false(entity.is_selected)

# damage tests
func test_take_damage_reduces_health() -> void:
	entity._ready()
	var initial_health = entity.current_health
	entity.take_damage(10)
	assert_eq(entity.current_health, initial_health - 10)

func test_take_damage_multiple_times() -> void:
	entity._ready()
	entity.take_damage(25)
	entity.take_damage(25)
	entity.take_damage(10)
	assert_eq(entity.current_health, 40)

func test_take_damage_cannot_exceed_max_health() -> void:
	entity._ready()
	var initial_health = entity.current_health
	entity.take_damage(150)
	assert_true(entity.current_health <= 0)

func test_die_is_called_when_health_reaches_zero() -> void:
	entity._ready()
	watch_signals(entity)
	entity.take_damage(100)
	assert_true(entity.is_queued_for_deletion())

func test_die_exact_zero() -> void:
	entity._ready()
	entity.take_damage(100)
	assert_true(entity.current_health <= 0)

# selection tests
func test_set_selected_true() -> void:
	entity._ready()
	entity.set_selected(true)
	assert_true(entity.is_selected)

func test_set_selected_false() -> void:
	entity._ready()
	entity.is_selected = true
	entity.set_selected(false)
	assert_false(entity.is_selected)
