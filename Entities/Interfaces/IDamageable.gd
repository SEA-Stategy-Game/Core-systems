## IDamageable.gd
## -----------------------------------------------------------------------
## Interface contract for any game object that can receive damage.
## Trees, Units, Buildings -- anything that has HP implements this.
##
## GDScript does not have formal interfaces; this RefCounted class acts
## as a compile-time reference AND provides a duck-typing validator.
## -----------------------------------------------------------------------
extends RefCounted
class_name IDamageable

## Return the current health of the object.
func get_current_health() -> int:
	push_error("IDamageable.get_current_health() is abstract -- override in subclass.")
	return -1

## Return true if the object is still alive (health > 0).
func is_alive() -> bool:
	push_error("IDamageable.is_alive() is abstract -- override in subclass.")
	return false

## Apply damage to the object.  Implementations must clamp and handle death.
func take_damage(amount: int) -> void:
	push_error("IDamageable.take_damage() is abstract -- override in subclass.")

## Get the player who owns this object (-1 = neutral / environment).
func get_player_id() -> int:
	push_error("IDamageable.get_player_id() is abstract -- override in subclass.")
	return -1

# -----------------------------------------------------------------
# Duck-typing validator
# -----------------------------------------------------------------
static func is_implemented_by(obj: Variant) -> bool:
	if obj == null:
		return false
	return (
		obj.has_method("get_current_health")
		and obj.has_method("is_alive")
		and obj.has_method("take_damage")
		and obj.has_method("get_player_id")
	)
