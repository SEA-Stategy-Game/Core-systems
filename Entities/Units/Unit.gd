extends CharacterBody2D

class_name Unit

## -----------------------------------------------------------------------
## Exported / inspector properties
## -----------------------------------------------------------------------
@export var selected: bool = false
@export var entity_id: int = -1   # Unique ID for AI lookups

@onready var box = get_node("HitBox")
@onready var anim = get_node("AnimationPlayer")

## -----------------------------------------------------------------------
## Movement (manual player control -- right-click)
## -----------------------------------------------------------------------
@onready var target: Vector2 = global_position
var follow_cursor: bool = false
var Speed: int = 50

## -----------------------------------------------------------------------
## AI Command Queue
## -----------------------------------------------------------------------
var command_queue: CommandQueue = null
var is_idle: bool = true

signal ai_action_completed(unit_id: int, action_data: Dictionary)
signal ai_action_failed(unit_id: int, action_data: Dictionary)
signal unit_idled(unit_id: int)

# -----------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------

func _ready() -> void:
	add_to_group("units", true)
	set_selected(selected)

	# Initialise the command queue
	command_queue = CommandQueue.new()
	var uid: int = entity_id if entity_id >= 0 else get_instance_id()
	command_queue.setup(self, uid)
	command_queue.action_completed.connect(_on_cq_action_completed)
	command_queue.action_failed.connect(_on_cq_action_failed)
	command_queue.queue_empty.connect(_on_cq_queue_empty)

func set_selected(value) -> void:
	selected = value
	if box:
		box.visible = value

# -----------------------------------------------------------------
# Player input  (manual right-click movement -- kept for human play)
# -----------------------------------------------------------------

func _input(event) -> void:
	if event.is_action_pressed("RightClick"):
		if selected:
			# Manual move clears any AI queue so the player takes over
			if command_queue:
				command_queue.clear()
			target = get_global_mouse_position()
			if anim:
				anim.play("Walk Down")

# -----------------------------------------------------------------
# Physics / tick processing
# -----------------------------------------------------------------

func _physics_process(delta) -> void:
	# 1. If the AI command queue has work, let it drive the unit.
	if command_queue and not command_queue.is_idle():
		if is_idle:
			is_idle = false
		command_queue.process_tick(delta)
		return  # AI commands take priority -- skip manual logic

	# 2. Otherwise, fall back to manual right-click movement.
	velocity = global_position.direction_to(target) * Speed
	if global_position.distance_to(target) > 10:
		move_and_slide()
	else:
		if anim:
			anim.stop()

# -----------------------------------------------------------------
# Signal relays
# -----------------------------------------------------------------

func _on_cq_action_completed(uid: int, data: Dictionary) -> void:
	ai_action_completed.emit(uid, data)

func _on_cq_action_failed(uid: int, data: Dictionary) -> void:
	ai_action_failed.emit(uid, data)

func _on_cq_queue_empty(uid: int) -> void:
	if not is_idle:
		is_idle = true
		unit_idled.emit(uid)
