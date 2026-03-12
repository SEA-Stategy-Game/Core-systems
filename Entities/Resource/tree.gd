extends MapResource

var totalTime = 5
var currentTime
var units = 0

@onready var bar = $ProgressBar
@onready var timer = $ProgressBar/Timer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	currentTime = totalTime
	bar.max_value = totalTime


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	# bar.value = currentTime
	if currentTime <= 0:
		treeChopped()
	


func _on_chop_tree_body_entered(body: Node2D) -> void:
	if "Unit" in body.name: # Change 'unit' to for example 'axe'
		units += 1
		startChopping()


func _on_chop_tree_body_exited(body: Node2D) -> void:
	if "Unit" in body.name:
		units -= 1
		if units <= 0:
			timer.stop()


func _on_timer_timeout() -> void:
	currentTime -= 1*units
	# tweens are used for animations
	var tween = get_tree().create_tween()
	# this is asking what are we animating to 
	tween.tween_property(bar, "value", currentTime, 0.5).set_trans(Tween.TRANS_LINEAR)
	
	
func treeChopped():
	Game.Wood += 1
	queue_free()

func startChopping():
	timer.start()
