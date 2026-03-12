extends MapResource

# Init
func _ready() -> void:
	# Parent Init
	super()
	amount = 3
	totalTime = 10.0
	currentTime = totalTime
	
	bar.max_value = totalTime
	bar.value = currentTime

func on_finished_harvesting():
	Game.Stone += 1
	# Parent function to remove it
	super.on_finished_harvesting()
