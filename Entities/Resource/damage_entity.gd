extends Area2D

@export var click_damage := 1.0

@onready var tree = get_parent()

func _ready():
	input_pickable = true

func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			print("TREE CLICKED")

			tree.damage_tree(click_damage)
