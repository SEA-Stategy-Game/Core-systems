class_name TreeResource
extends MapResource

func _ready() -> void:
	super()
	
	amount = 1 
	total_time = 5.0
	current_time = total_time
	
	if bar:
		bar.max_value = total_time
		bar.value = current_time
		
	resource_name = "ressource_tree"

func on_finished_harvesting():
	Game.Wood += 1
	# Parent function to remove it
	super.on_finished_harvesting()
