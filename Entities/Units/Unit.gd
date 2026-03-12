extends CharacterBody2D

@export var selected = false
@onready var box = get_node("HitBox")
@onready var anim = get_node("AnimationPlayer")

@onready var target = position
var follow_cursor = false
var Speed = 50


func _ready():
	add_to_group("units", true)
	set_selected(selected)
func set_selected(value):
	selected = value
	box.visible = value

func _input(event):
	if event.is_action_pressed("RightClick"):
		if selected:
			target = get_global_mouse_position()
			anim.play("Walk Down")
		
		
func _physics_process(delta):
	velocity = position.direction_to(target) * Speed
	if position.distance_to(target) > 10:
		move_and_slide()
	else:
		anim.stop()
