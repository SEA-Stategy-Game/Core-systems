extends NavigationRegion2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func rebuild_nav():
	await get_tree().physics_frame
	bake_navigation_polygon()
