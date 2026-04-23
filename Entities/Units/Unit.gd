extends CharacterBody2D

class_name Unit

## -----------------------------------------------------------------------
## Exported / inspector properties
## -----------------------------------------------------------------------
@export var selected: bool = false
@export var entity_id: int = -1        ## Unique ID for AI lookups
@export var player_id: int = 0         ## Owner player for multiplayer
@export var max_health: int = 100
@export var attack_damage: int = 10    ## Damage per combat tick
@export var attack_cooldown: float = 1.0  ## Seconds between attacks

var current_health: int

@onready var box = get_node("HitBox")
@onready var anim = get_node("AnimationPlayer")
@onready var attack_range_area: Area2D = get_node_or_null("Range")

## -----------------------------------------------------------------------
## Movement (manual player control -- right-click)
## -----------------------------------------------------------------------
var follow_cursor: bool = false
var speed: int = 2000

## -----------------------------------------------------------------------
## Pathfinding
## -----------------------------------------------------------------------
# @export var Goal: Node = null

## -----------------------------------------------------------------------
## AI Command Queue
## -----------------------------------------------------------------------
var command_queue: CommandQueue = null
var is_idle: bool = true

## -----------------------------------------------------------------------
## Combat state -- tracked bodies inside the Range Area2D
## -----------------------------------------------------------------------
var _bodies_in_range: Array = []       ## All bodies currently inside Range
var _attack_timer: float = 0.0

signal ai_action_completed(unit_id: int, action_data: Dictionary)
signal ai_action_failed(unit_id: int, action_data: Dictionary)
signal unit_idled(unit_id: int)

# -----------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------

func _ready() -> void:
	current_health = max_health
	add_to_group("units", true)
	set_selected(selected)

	# Initialise the command queue
	command_queue = CommandQueue.new()
	var uid: int = entity_id if entity_id >= 0 else get_instance_id()
	command_queue.setup(self, uid)
	command_queue.action_completed.connect(_on_cq_action_completed)
	command_queue.action_failed.connect(_on_cq_action_failed)
	command_queue.queue_empty.connect(_on_cq_queue_empty)

	# Wire up the Range Area2D signals for combat detection
	if attack_range_area:
		attack_range_area.body_entered.connect(_on_range_body_entered)
		attack_range_area.body_exited.connect(_on_range_body_exited)

func set_selected(value) -> void:
	selected = value
	if box:
		box.visible = value

# -----------------------------------------------------------------
# Range Area2D signal handlers
# -----------------------------------------------------------------

func _on_range_body_entered(body: Node2D) -> void:
	if body == self:
		return  # Ignore self
	if body.has_method("get_player_id"):
		_bodies_in_range.append(body)

func _on_range_body_exited(body: Node2D) -> void:
	_bodies_in_range.erase(body)

## Return all hostile bodies currently inside the Range Area2D.
func get_hostiles_in_range() -> Array:
	var hostiles: Array = []
	for body in _bodies_in_range:
		if not is_instance_valid(body):
			continue
		if not body.has_method("get_player_id"):
			continue
		if body.get_player_id() == player_id:
			continue  # Friendly
		if body.get_player_id() == -1:
			continue  # Neutral (resources) -- skip unless explicitly attacked
		if body.has_method("is_alive") and not body.is_alive():
			continue
		hostiles.append(body)
	return hostiles

## Return the closest hostile body in range, or null.
func get_closest_hostile() -> Node2D:
	var hostiles = get_hostiles_in_range()
	var closest: Node2D = null
	var closest_dist: float = INF
	for h in hostiles:
		var d = global_position.distance_to(h.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = h
	return closest

# -----------------------------------------------------------------
# IDamageable contract
# -----------------------------------------------------------------

func take_damage(amount: int) -> void:
	current_health -= amount
	print("[COMBAT_LOG] Unit ", entity_id, " (player ", player_id, ") took ", amount, " damage. HP: ", current_health, "/", max_health)
	
	# Visual feedback: flash red!
	var sprite = get_node_or_null("Arthax") # The Sprite2D name in unit.tscn
	if not sprite:
		sprite = get_node_or_null("Sprite2D")
	if sprite:
		var tween = get_tree().create_tween()
		sprite.modulate = Color(1, 0, 0) # Red
		tween.tween_property(sprite, "modulate", Color(1, 1, 1), 0.2) # Back to normal

	if current_health <= 0:
		die()

func get_current_health() -> int:
	return current_health

func is_alive() -> bool:
	return current_health > 0

func get_player_id() -> int:
	return player_id

func die() -> void:
	print("[COMBAT_LOG] Unit ", entity_id, " (player ", player_id, ") destroyed.")
	if command_queue:
		command_queue.clear()
	queue_free()

# -----------------------------------------------------------------
# Player input  (manual right-click movement -- kept for human play)
# -----------------------------------------------------------------

func _input(event) -> void:
	if event.is_action_pressed("RightClick"):
		if selected:
			# Manual move clears any AI queue so the player takes over
			if command_queue:
				command_queue.clear()
			$NavigationAgent2D.target_position = get_global_mouse_position()
			if anim:
				anim.play("Walk Down")

# -----------------------------------------------------------------
# Physics / tick processing
# -----------------------------------------------------------------

func _physics_process(delta) -> void:
	# Clean up stale references from _bodies_in_range
	_bodies_in_range = _bodies_in_range.filter(func(b): return is_instance_valid(b))

	# AUTO-AGGRO: If the AI queue is totally idle and a hostile is in range, attack it automatically!
	if command_queue and command_queue.is_idle():
		var closest = get_closest_hostile()
		if closest != null:
			command_queue.enqueue(UnitActionAttack.create_focused(closest))

	# 1. If the AI command queue has work, let it drive the unit.
	if command_queue and not command_queue.is_idle():
		if is_idle:
			is_idle = false
		command_queue.process_tick(delta)
		return  # AI commands take priority -- skip manual logic

	# 2. Otherwise, fall back to manual right-click movement.
	if $NavigationAgent2D.is_target_reached():
		if anim:
			anim.stop()
		return

	var nav_point_direction = to_local($NavigationAgent2D.get_next_path_position()).normalized()
	velocity = nav_point_direction * speed * delta
	move_and_slide()
	
	# velocity = global_position.direction_to(target) * speed
	# if global_position.distance_to(target) > 10:
	# 	move_and_slide()
	# else:
	# 	if anim:
	# 		anim.stop()
	

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

func _on_timer_timeout() -> void:
	# if $NavigationAgent2D.target_position != Goal.global_position:
	# 	$NavigationAgent2D.target_position = Goal.global_position'
	print("Test")
	$PathfindingUpdateTimer.start()


func _on_navigation_agent_2d_velocity_computed(safe_velocity: Vector2) -> void:
	# position += safe_velocity * get_physics_process_delta_time()
	pass # Replace with function body.
