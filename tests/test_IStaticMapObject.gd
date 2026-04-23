extends GutTest

class ValidStaticMapObject extends RefCounted:
	func getId() -> int:
		return 11

	func getPosition() -> Vector2:
		return Vector2(4, 8)

	func takeDamage(_dmg: int) -> void:
		pass

class MissingDamageMethod extends RefCounted:
	func getId() -> int:
		return 22

	func getPosition() -> Vector2:
		return Vector2(1, 2)

class SnakeCaseDamageMethodOnly extends RefCounted:
	func getId() -> int:
		return 33

	func getPosition() -> Vector2:
		return Vector2(3, 3)

	func take_damage(_dmg: int) -> void:
		pass

# --------------------
# default contract API
# --------------------
func test_default_getid_returns_negative_one() -> void:
	var contract := IStaticMapObject.new()
	assert_eq(contract.getId(), -1)

func test_default_getPosition_returns_zero_vector() -> void:
	var contract := IStaticMapObject.new()
	assert_eq(contract.getPosition(), Vector2.ZERO)

func test_default_takeDamage_is_callable() -> void:
	var contract := IStaticMapObject.new()
	contract.takeDamage(10)
	assert_true(true)

# ---------------------
# duck-typing validator
# ---------------------
func test_is_implemented_by_returns_false_for_null() -> void:
	assert_false(IStaticMapObject.is_implemented_by(null))

func test_is_implemented_by_returns_true_for_valid_object() -> void:
	var obj = ValidStaticMapObject.new()
	assert_true(IStaticMapObject.is_implemented_by(obj))

func test_is_implemented_by_returns_false_when_takedamage_missing() -> void:
	var obj := MissingDamageMethod.new()
	assert_false(IStaticMapObject.is_implemented_by(obj))

func test_is_implemented_by_returns_false_for_snake_case_take_damage_only() -> void:
	var obj := SnakeCaseDamageMethodOnly.new()
	assert_false(IStaticMapObject.is_implemented_by(obj))
