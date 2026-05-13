extends Entity

class_name Building

## -----------------------------------------------------------------------
## Base class for all buildings.  Inherits IDamageable from Entity.
## The player_id is inherited from Entity and identifies the owner.
## -----------------------------------------------------------------------

## Building-specific state
@export var building_name: String = "Building"

func _ready() -> void:
	super()
	add_to_group("buildings")
	# Buildings should not be in the "units" group -- remove if Entity added it
	if is_in_group("units"):
		remove_from_group("units")