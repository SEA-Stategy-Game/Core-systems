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

## -----------------------------------------------------------------------
## Ranged attack / projectile configuration
## -----------------------------------------------------------------------
@export var uses_projectiles: bool = false       ## If true, attacks fire projectiles instead of melee.
@export var projectile_speed: float = 240.0
@export var projectile_damage: int = -1          ## -1 = use attack_damage
@export var projectile_spread_radians: float = 0.12
@export var projectile_aim_jitter_pixels: float = 6.0

var current_health: int

@onready var box = get_node("HitBox")
@onready var anim = get_node("AnimationPlayer")
@onready var attack_range_area: Area2D = get_node_or_null("Range")
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar")
@onready var tile_map: TileMapLayer = get_node("/root/World/NavigationRegion2D/TileMapLayer")

## -----------------------------------------------------------------------
## Movement (manual player control -- right-click)
## -----------------------------------------------------------------------
var follow_cursor: bool = false
var speed: int = 3000
var is_animated: bool = false

## -----------------------------------------------------------------------
## Pathfinding
## -----------------------------------------------------------------------
var current_path_index: int = 0
@onready var sprite = $Arthax # For shader, could be removed

## -----------------------------------------------------------------------
## AI Command Queue
## -----------------------------------------------------------------------
var command_queue: CommandQueue = null
var is_idle: bool = true

## -----------------------------------------------------------------------
## Equipment & derived stats
## -----------------------------------------------------------------------
@export var vision_range_tiles: int = 6   ## Read by FogOfWar
var equipped: Array[Equipment] = []

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
	_refresh_health_bar()

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
		
	$NavigationAgent2D.waypoint_reached.connect(_on_waypoint_reached)
	$NavigationAgent2D.navigation_finished.connect(func(): current_path_index = 0)

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

func get_local_movement_speed() -> float:
	var tile = tile_map.get_tile_at_world_pos(global_position)
	if tile == null:
		return speed
	return speed * tile.get_movement_multiplier()

# -----------------------------------------------------------------
# IDamageable contract
# -----------------------------------------------------------------

func take_damage(amount: int) -> void:
	# Armor from equipment reduces incoming damage (always at least 1 lands).
	var armor = get_total_armor()
	var net = max(1, amount - armor)
	current_health -= net
	if armor > 0:
		print("[COMBAT_LOG] Unit ", entity_id, " (player ", player_id, ") took ", net,
			" damage (raw ", amount, " - armor ", armor, "). HP: ", current_health, "/", max_health)
	else:
		print("[COMBAT_LOG] Unit ", entity_id, " (player ", player_id, ") took ", net,
			" damage. HP: ", current_health, "/", max_health)
	_refresh_health_bar()

	# Visual feedback: flash red!
	var sprite = get_node_or_null("Arthax") # The Sprite2D name in unit.tscn
	if not sprite:
		sprite = get_node_or_null("Sprite2D")
	if sprite:
		if sprite.material:
			sprite.material = sprite.material.duplicate(true)
		var tween = get_tree().create_tween()
		sprite.modulate = Color(1, 0, 0) # Red
		tween.tween_property(sprite, "modulate", Color(1, 1, 1), 0.2) # Back to normal

	if current_health <= 0:
		die()

func _refresh_health_bar() -> void:
	if health_bar == null:
		return
	health_bar.max_value = max_health
	health_bar.value = clamp(current_health, 0, max_health)
	# Hide when totally full so the world isn't littered with bars.
	health_bar.visible = current_health < max_health

# -----------------------------------------------------------------
# Equipment
# -----------------------------------------------------------------

## Attach an Equipment object to this unit, summing its bonuses in.
func equip(item: Equipment) -> bool:
	if item == null:
		return false
	equipped.append(item)
	item.apply_to(self)
	return true

## Remove a previously-equipped Equipment object.
func unequip(item: Equipment) -> bool:
	var idx = equipped.find(item)
	if idx < 0:
		return false
	equipped.remove_at(idx)
	item.remove_from(self)
	return true

## Sum of armor across all equipped items.
func get_total_armor() -> int:
	var total = 0
	for e in equipped:
		if is_instance_valid(e):
			total += e.armor
	return total

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
			set_target(get_global_mouse_position())
			set_anim(velocity.length_squared() > 100)
			
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
	if $NavigationAgent2D.is_navigation_finished():
		return
	pathfind_and_move(delta)
	# Below is used for Godto RVO avoidance but this data is not caught by the server so it is commented out
	#$NavigationAgent2D.set_velocity(desired_velocity)

## Sets the target on the unit for pathfinding and resets the current_path_index
func set_target(target) -> void:
	$NavigationAgent2D.target_position = target
	current_path_index = 0;

## Moves the unit based on the pathfinding algorithm. Snaps the unit back into a navigateble area if it is out-of-bounds
## Speed is scaled by the terrain multiplier of the tile the unit is standing on
## (PLAINS 1.10, FOREST 0.75, HILLS 0.6, WATER 0.0).
func pathfind_and_move(delta) -> void:
	var nav_point_direction = to_local($NavigationAgent2D.get_next_path_position()).normalized()
	var effective_speed = float(speed)
	if tile_map and tile_map.has_method("get_tile_at_world_pos"):
		var tile = tile_map.get_tile_at_world_pos(global_position)
		if tile != null and tile.has_method("get_movement_multiplier"):
			effective_speed *= tile.get_movement_multiplier()
	velocity = nav_point_direction * effective_speed * delta
	move_and_slide()
	global_position = NavigationServer2D.map_get_closest_point(
		$NavigationAgent2D.get_navigation_map(), global_position)

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

# -----------------------------------------------------------------
# Projectile firing
# -----------------------------------------------------------------

## Spawn a Projectile aimed at `target` (a Node2D) or at a Vector2 point.
## The projectile is added to the world (under the unit's parent) so it
## survives the unit dying / being freed mid-flight.
func fire_projectile(target) -> Projectile:
	var dmg: int = projectile_damage if projectile_damage >= 0 else attack_damage
	var projectile := Projectile.create(self, target, dmg, projectile_speed)
	projectile.spread_radians = projectile_spread_radians
	projectile.aim_jitter_pixels = projectile_aim_jitter_pixels

	var spawn_parent: Node = get_parent()
	if spawn_parent == null:
		spawn_parent = self
	spawn_parent.add_child(projectile)
	projectile.global_position = global_position
	return projectile
	
# Small function to set animation. I don't know if starting animation is expensive.
# Otherwise just remove and set directly
func set_anim(flag) -> void:
	if flag and not is_animated:	
		anim.play("Walk Down")
		is_animated = true
	if not flag and is_animated:
		anim.stop()
		is_animated = false

func point_to_line_dist(line_start : Vector2, line_end : Vector2, point_position : Vector2) -> float:
	var line_direction = (line_start - line_end).normalized()
	var vector_to_object = point_position - line_start
	var distance = line_direction.dot(vector_to_object)
	return distance

func recalculate_path() -> void:
	$NavigationAgent2D.target_position = $NavigationAgent2D.target_position
	
func _on_waypoint_reached(details: Dictionary) -> void:
	current_path_index += 1
	
func trigger_white_flash() -> void:
	var mat = sprite.material as ShaderMaterial
	mat.set_shader_parameter("active", true)
	await get_tree().create_timer(0.4).timeout
	mat.set_shader_parameter("active", false)

func get_navigation_path_segment(amount_of_segments: int) -> PackedVector2Array:
	var path = $NavigationAgent2D.get_current_navigation_path()
	if $NavigationAgent2D.is_navigation_finished() or current_path_index >= path.size():
		return PackedVector2Array()
	var end_index = min(current_path_index + amount_of_segments, path.size())
	return path.slice(current_path_index, end_index)
	
## Deprecated function, used for setting avoidance navigation (using Godots RVO)
# Called when avoidance on the navigation agaent is set and NavigationAgent2D.set_velocity(desired_velocity) is called
func _on_navigation_agent_2d_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	if not $NavigationAgent2D.is_navigation_finished():
		set_anim(safe_velocity.length_squared() > 100)
		# Snap back to navmesh
		global_position = NavigationServer2D.map_get_closest_point(
			$NavigationAgent2D.get_navigation_map(), global_position)
		
		# If the unit gets too far off path due to Godots RVO Avoidance system, we recalculate the path
		if (current_path_index < $NavigationAgent2D.get_current_navigation_path().size()-1 &&
			point_to_line_dist(
				$NavigationAgent2D.get_current_navigation_path()[current_path_index-1],
				$NavigationAgent2D.get_current_navigation_path()[current_path_index],
				global_position
			) > 40):
			# White flash to indicate that this happens
			# trigger_white_flash()
			recalculate_path()
	else:
		set_anim(false)
		velocity = Vector2.ZERO
		move_and_slide()
		# Makes units able to walk into each other os that they can finish pathfinding and does not stall on each other
		#$NavigationAgent2D.avoidance_enabled = false
