extends GutTest

## -----------------------------------------------------------------------
## Tests for Projectile.gd
## -----------------------------------------------------------------------
## Acceptance criteria (from the GitHub issue):
##   * Projectile entities can be fired by other entities.
##   * Movement is NOT instantaneous; they travel over time.
##   * Random variation in their flight path.
## -----------------------------------------------------------------------

const ProjectileScript = preload("res://Entities/Projectiles/Projectile.gd")

class FakeShooter extends Node2D:
	var player_id: int = 0

	func get_player_id() -> int:
		return player_id

class FakeTarget extends Node2D:
	var player_id: int = 1
	var damage_taken: int = 0
	var alive: bool = true

	func get_player_id() -> int:
		return player_id

	func take_damage(amount: int) -> void:
		damage_taken += amount
		if damage_taken >= 100:
			alive = false

	func is_alive() -> bool:
		return alive

var shooter: FakeShooter
var target: FakeTarget

func before_each() -> void:
	shooter = FakeShooter.new()
	shooter.global_position = Vector2(0, 0)
	add_child_autofree(shooter)

	target = FakeTarget.new()
	target.global_position = Vector2(200, 0)
	add_child_autofree(target)

func after_each() -> void:
	shooter = null
	target = null

# -----------------------------------------------------------------
# basic factory / setup
# -----------------------------------------------------------------
func test_create_returns_projectile_with_owner_player_id() -> void:
	shooter.player_id = 7
	var p := ProjectileScript.create(shooter, target, 5, 200.0, 1)
	add_child_autofree(p)
	assert_eq(p.owner_player_id, 7)

func test_create_with_no_jitter_aims_directly_at_target() -> void:
	# Disable randomness so we can pin the direction.
	var p := ProjectileScript.new()
	p.spread_radians = 0.0
	p.aim_jitter_pixels = 0.0
	p.setup(shooter, target, 5, 200.0, 1)
	add_child_autofree(p)
	# shooter at (0,0), target at (200,0) -> direction should be ~(1,0)
	var dir := p.get_direction()
	assert_almost_eq(dir.x, 1.0, 0.01)
	assert_almost_eq(dir.y, 0.0, 0.01)

func test_create_uses_target_vector2_when_no_node_provided() -> void:
	var p := ProjectileScript.new()
	p.spread_radians = 0.0
	p.aim_jitter_pixels = 0.0
	p.setup(shooter, Vector2(100, 0), 5, 200.0, 1)
	add_child_autofree(p)
	assert_null(p.get_target_node())
	assert_eq(p.get_aim_point(), Vector2(100, 0))

# -----------------------------------------------------------------
# non-instantaneous movement
# -----------------------------------------------------------------
func test_projectile_moves_over_time_not_instantaneously() -> void:
	var p := ProjectileScript.new()
	p.spread_radians = 0.0
	p.aim_jitter_pixels = 0.0
	p.setup(shooter, target, 5, 100.0, 1)
	add_child_autofree(p)

	var start_pos := p.global_position
	# One physics tick of 0.1s at 100 px/s = 10 px movement
	p._physics_process(0.1)
	var dist := start_pos.distance_to(p.global_position)
	# Must have moved roughly 10 px, NOT instantly arrived at the target (200 px away)
	assert_almost_eq(dist, 10.0, 0.5)
	assert_true(dist < 200.0, "projectile should not teleport to target")

func test_projectile_speed_scales_with_delta() -> void:
	var p := ProjectileScript.new()
	p.spread_radians = 0.0
	p.aim_jitter_pixels = 0.0
	p.setup(shooter, target, 5, 50.0, 1)
	add_child_autofree(p)

	var start_pos := p.global_position
	p._physics_process(1.0)
	# 50 px/s for 1.0s = 50 px
	var dist := start_pos.distance_to(p.global_position)
	assert_almost_eq(dist, 50.0, 1.0)

# -----------------------------------------------------------------
# randomness ("a bit random to satisfy Tijs")
# -----------------------------------------------------------------
func test_two_projectiles_with_different_seeds_have_different_directions() -> void:
	var p1 := ProjectileScript.new()
	p1.spread_radians = 0.3
	p1.aim_jitter_pixels = 20.0
	p1.setup(shooter, target, 5, 200.0, 1)
	add_child_autofree(p1)

	var p2 := ProjectileScript.new()
	p2.spread_radians = 0.3
	p2.aim_jitter_pixels = 20.0
	p2.setup(shooter, target, 5, 200.0, 999)
	add_child_autofree(p2)

	# Direction or aim point must differ between seeds.
	var dir_diff := p1.get_direction().distance_to(p2.get_direction())
	var aim_diff := p1.get_aim_point().distance_to(p2.get_aim_point())
	assert_true(dir_diff > 0.0001 or aim_diff > 0.0001,
		"projectiles with different seeds must produce different trajectories")

func test_jitter_disabled_with_zero_spread_and_jitter() -> void:
	# When all randomness is disabled the projectile's aim must hit exactly
	# the target's position.
	var p := ProjectileScript.new()
	p.spread_radians = 0.0
	p.aim_jitter_pixels = 0.0
	p.setup(shooter, target, 5, 200.0, 1)
	add_child_autofree(p)
	assert_eq(p.get_aim_point(), target.global_position)

# -----------------------------------------------------------------
# hit / damage application
# -----------------------------------------------------------------
func test_apply_hit_damages_target_and_emits_signal() -> void:
	var p := ProjectileScript.new()
	p.spread_radians = 0.0
	p.aim_jitter_pixels = 0.0
	p.setup(shooter, target, 17, 200.0, 1)
	add_child_autofree(p)
	watch_signals(p)
	p._apply_hit(target)
	assert_eq(target.damage_taken, 17)
	assert_signal_emitted(p, "hit")

func test_friendly_fire_is_ignored() -> void:
	# Set target to same team as shooter -- projectile must not hit.
	target.player_id = 0
	shooter.player_id = 0
	var p := ProjectileScript.new()
	p.spread_radians = 0.0
	p.aim_jitter_pixels = 0.0
	p.setup(shooter, target, 10, 200.0, 1)
	add_child_autofree(p)
	p._try_hit(target)
	assert_eq(target.damage_taken, 0)

func test_does_not_hit_shooter() -> void:
	var p := ProjectileScript.new()
	p.spread_radians = 0.0
	p.aim_jitter_pixels = 0.0
	p.setup(shooter, target, 10, 200.0, 1)
	add_child_autofree(p)
	# Force-call the body-entered handler with the shooter itself.
	p._on_body_entered(shooter)
	# Shooter has no take_damage method anyway, but more importantly
	# the projectile must not be marked as hit.
	assert_false(p._has_hit)

func test_proximity_hit_when_close_to_target() -> void:
	var p := ProjectileScript.new()
	p.spread_radians = 0.0
	p.aim_jitter_pixels = 0.0
	# Low speed so we don't overshoot the 8 px hit radius in one tick.
	p.setup(shooter, target, 8, 10.0, 1)
	add_child_autofree(p)
	# Place the projectile right on top of the target and tick physics.
	p.global_position = target.global_position
	p._physics_process(0.016)
	assert_eq(target.damage_taken, 8)

# -----------------------------------------------------------------
# expiration
# -----------------------------------------------------------------
func test_expires_after_max_lifetime() -> void:
	var p := ProjectileScript.new()
	p.spread_radians = 0.0
	p.aim_jitter_pixels = 0.0
	p.max_lifetime = 0.05
	p.max_range = 10000.0
	p.setup(shooter, Vector2(1000, 0), 1, 50.0, 1)
	add_child_autofree(p)
	watch_signals(p)
	p._physics_process(0.1)
	assert_signal_emitted(p, "expired")

func test_expires_after_max_range() -> void:
	var p := ProjectileScript.new()
	p.spread_radians = 0.0
	p.aim_jitter_pixels = 0.0
	p.max_range = 5.0
	p.setup(shooter, Vector2(1000, 0), 1, 100.0, 1)
	add_child_autofree(p)
	watch_signals(p)
	p._physics_process(0.5)  # 50 px of travel
	assert_signal_emitted(p, "expired")

# -----------------------------------------------------------------
# Unit integration: fire_projectile()
# -----------------------------------------------------------------
const UnitScene = preload("res://Entities/Units/unit.tscn")

func test_unit_fire_projectile_spawns_projectile_node() -> void:
	var unit = UnitScene.instantiate() as Unit
	add_child_autofree(unit)
	unit.uses_projectiles = true
	unit.global_position = Vector2.ZERO

	var enemy := FakeTarget.new()
	enemy.global_position = Vector2(100, 0)
	add_child_autofree(enemy)

	var p = unit.fire_projectile(enemy)
	assert_not_null(p)
	assert_true(p is Projectile)
	assert_true(p.is_inside_tree(), "projectile should be in the scene tree")
	assert_eq(p.owner_player_id, unit.player_id)
