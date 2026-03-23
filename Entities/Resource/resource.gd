extends Entity

class_name MapResource

# Init
@export var resource_name: String = "Resource"
@export var totalTime: float = 5.0

@onready var bar = $ProgressBar
@onready var timer = $ProgressBar/Timer

var amount: int = 1
var maxAmount: int = 1 
var currentTime: float
var units_harvesting: int = 0

func _ready() -> void:
	currentTime = totalTime
	if bar:
		bar.max_value = totalTime
		bar.value = currentTime

func harvest():
	if amount > 0:
		amount -= 1
		if amount <= 0:
			deplete()

func deplete():
	# Your depletion logic
	pass

func _on_harvest_area_body_entered(body: Node2D) -> void:
	# Checks if the body is a 'Unit' class
	if body is Unit: 
		units_harvesting += 1
		if timer and timer.is_stopped():
			timer.start()

func _on_harvest_area_body_exited(body: Node2D) -> void:
	if body is Unit:
		units_harvesting -= 1
		if units_harvesting <= 0 and timer:
			timer.stop()

func _on_timer_timeout() -> void:
	currentTime -= 1 * units_harvesting
	
	if bar:
		var tween = get_tree().create_tween()
		tween.tween_property(bar, "value", currentTime, 0.5)
	
	if currentTime <= 0:
		on_finished_harvesting()

func on_finished_harvesting():
	print(resource_name, " depleted!")
	queue_free()
