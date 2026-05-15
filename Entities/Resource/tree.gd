class_name TreeResource
extends MapResource

# Init
func _ready() -> void:
	# Parent Init
	super()
	amount = 1 
	totalTime = 5.0
	currentTime = totalTime
	bar.max_value = totalTime
	bar.value = currentTime
	resource_name = "ressource_tree"

func damage_tree(damage: float):
	currentTime -= damage

	if currentTime < 0:
		currentTime = 0

	bar.value = currentTime

	if currentTime <= 0:
		on_finished_harvesting()

func on_finished_harvesting():
	amount = 0
	Game.Wood += 1
	# Parent function to remove it
	super.on_finished_harvesting()
