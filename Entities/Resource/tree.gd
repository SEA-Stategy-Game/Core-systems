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

func on_finished_harvesting():
	Game.Wood += 1
	# Parent function to remove it
	super.on_finished_harvesting()
