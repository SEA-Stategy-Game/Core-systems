extends RefCounted
class_name IStaticMapObject

## -----------------------------------------------------------------------
## Interface contract for static map objects (trees, stones, etc.).
## Updated to include IDamageable-compatible methods so combat logic
## can target environment objects uniformly.
## -----------------------------------------------------------------------

func getId() -> int:
	# Not implemented
	return -1

func getPosition() -> Vector2:
	# Not implemented
	return Vector2.ZERO

func takeDamage(dmg: int) -> void:
	# Not implemented
	pass

func getPlayerId() -> int:
	# Environment objects default to -1 (neutral)
	return -1

static func is_implemented_by(obj: Variant) -> bool:
	if obj == null:
		return false

	return obj.has_method("getId") \
		and (obj.has_method("getPosition")) \
		and obj.has_method("takeDamage")
