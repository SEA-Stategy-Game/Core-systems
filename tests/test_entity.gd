extends GutTest

func test_entity_initializes_health_to_max() -> void:
	var entity = Entity.new()
	entity.max_health = 150
	entity.current_health = entity.max_health
	assert_eq(entity.current_health, 150)
	entity.free()

func test_entity_default_max_health_is_100() -> void:
	var entity = Entity.new()
	assert_eq(entity.max_health, 100)
	entity.free()
