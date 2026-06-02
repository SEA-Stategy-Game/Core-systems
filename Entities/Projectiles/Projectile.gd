extends Area2D
class_name Projectile

## -----------------------------------------------------------------------
## Projectile
## -----------------------------------------------------------------------
## A non-instantaneous projectile fired by an entity at a target.
##
## Acceptance criteria (from the GitHub issue):
##   * Created on demand so any entity can fire one.
##   * Movement is NOT instantaneous -- the projectile travels at an
##     adequate tempo across frames.
##   * Adds a touch of randomness ("make them a bit random to satisfy
##     Tijs") so a projectile is not perfectly accurate.
##
## On hit the projectile calls `take_damage()` on the target and frees
## itself. If the target dies / is freed mid-flight the projectile keeps
## travelling to the originally aimed-at point and then despawns.
## -----------------------------------------------------------------------

signal hit(target: Node)
signal missed()
signal expired()

@export var speed: float = 240.0             ## pixels per second
@export var damage: int = 5
@export var max_range: float = 600.0         ## auto-expire after this distance
@export var max_lifetime: float = 4.0        ## seconds before auto-despawn
@export var owner_player_id: int = -1        ## set by the firing entity
@export var spread_radians: float = 0.12     ## random launch angle jitter
@export var aim_jitter_pixels: float = 6.0   ## random target offset

var _target_node: Node2D = null
var _aim_point: Vector2 = Vector2.ZERO
var _start_point: Vector2 = Vector2.ZERO
var _direction: Vector2 = Vector2.RIGHT
var _has_hit: bool = false
var _lifetime: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _shooter: Node = null

# -----------------------------------------------------------------
# Setup -- called by the firing entity BEFORE add_child().
# -----------------------------------------------------------------
func setup(
	shooter: Node,
	target_or_point: Variant,
	projectile_damage: int = -1,
	projectile_speed: float = -1.0,
	rng_seed: int = 0
) -> void:
	_shooter = shooter
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()

	if projectile_damage >= 0:
		damage = projectile_damage
	if projectile_speed > 0.0:
		speed = projectile_speed

	if shooter != null:
		if "player_id" in shooter:
			owner_player_id = int(shooter.player_id)
		elif shooter.has_method("get_player_id"):
			owner_player_id = int(shooter.get_player_id())
		if shooter is Node2D:
			_start_point = shooter.global_position
			global_position = _start_point

	if target_or_point is Node2D:
		_target_node = target_or_point
		_aim_point = _target_node.global_position
	elif target_or_point is Vector2:
		_target_node = null
		_aim_point = target_or_point
	else:
		push_warning("[Projectile] setup() received unsupported target: ", target_or_point)
		_aim_point = global_position

	# Add random spread to the aim point so projectiles are "a bit random".
	if aim_jitter_pixels > 0.0:
		var jitter := Vector2(
			_rng.randf_range(-aim_jitter_pixels, aim_jitter_pixels),
			_rng.randf_range(-aim_jitter_pixels, aim_jitter_pixels)
		)
		_aim_point += jitter

	var base_dir := (_aim_point - _start_point)
	if base_dir.length_squared() < 0.0001:
		base_dir = Vector2.RIGHT
	base_dir = base_dir.normalized()

	# Apply random launch-angle jitter so successive shots fan out slightly.
	if spread_radians > 0.0:
		var angle := _rng.randf_range(-spread_radians, spread_radians)
		base_dir = base_dir.rotated(angle)

	_direction = base_dir
	rotation = _direction.angle()

# -----------------------------------------------------------------
# Physics
# -----------------------------------------------------------------
func _ready() -> void:
	add_to_group("projectiles")
	# Hook collision signal -- we use the Area2D body_entered.
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	if _has_hit:
		return

	_lifetime += delta
	if _lifetime >= max_lifetime:
		_expire()
		return

	# Move in our travel direction.
	var step := _direction * speed * delta
	global_position += step

	# Range check
	if _start_point.distance_to(global_position) >= max_range:
		_expire()
		return

	# Hit-check: explicit target case. If the projectile is close enough
	# to the original target -- and the target is still valid -- count
	# that as a hit. This is useful when no collider is configured.
	if is_instance_valid(_target_node):
		var hit_radius := 8.0
		if global_position.distance_to(_target_node.global_position) <= hit_radius:
			_apply_hit(_target_node)
			return
	else:
		# Static-point aim: when we've arrived at the aim point, despawn.
		if global_position.distance_to(_aim_point) <= 4.0:
			missed.emit()
			_expire()

# -----------------------------------------------------------------
# Collision handlers
# -----------------------------------------------------------------
func _on_body_entered(body: Node) -> void:
	_try_hit(body)

func _on_area_entered(area: Area2D) -> void:
	_try_hit(area)

func _try_hit(node: Node) -> void:
	if _has_hit or node == null:
		return
	if node == _shooter:
		return  # do not hit ourselves
	# Friendly-fire guard: skip same-team targets.
	if node.has_method("get_player_id"):
		var pid := int(node.get_player_id())
		if pid == owner_player_id and pid >= 0:
			return
	# Only hit damageables.
	if not node.has_method("take_damage"):
		return
	_apply_hit(node)

func _apply_hit(node: Node) -> void:
	_has_hit = true
	if node != null and node.has_method("take_damage"):
		node.take_damage(damage)
	hit.emit(node)
	_despawn()

func _expire() -> void:
	expired.emit()
	_despawn()

func _despawn() -> void:
	# Defer in case we are still inside a physics callback.
	if is_inside_tree():
		queue_free()

# -----------------------------------------------------------------
# Test / inspection helpers
# -----------------------------------------------------------------
func get_direction() -> Vector2:
	return _direction

func get_aim_point() -> Vector2:
	return _aim_point

func get_target_node() -> Node2D:
	return _target_node

func is_friendly_to(player_id: int) -> bool:
	return owner_player_id == player_id

# -----------------------------------------------------------------
# Factory
# -----------------------------------------------------------------
## Convenience factory -- creates a new Projectile, configures it, and
## returns it. Caller is responsible for adding it to the scene tree.
static func create(
	shooter: Node,
	target_or_point: Variant,
	projectile_damage: int = -1,
	projectile_speed: float = -1.0,
	rng_seed: int = 0
) -> Projectile:
	var p := Projectile.new()
	p.setup(shooter, target_or_point, projectile_damage, projectile_speed, rng_seed)
	return p
