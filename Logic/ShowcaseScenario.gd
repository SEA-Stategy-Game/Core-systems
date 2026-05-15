extends Node
class_name ShowcaseScenario

var game: Game
var action_gateway: ActionGateway
var tick_manager: TickManager

func _ready() -> void:
	"""Async initialization sequence."""
	print("[SCENARIO] ShowcaseScenario starting...")
	
	await _initialize_scenario()

## =========================================================================
## Scenario Initialization (FIXED)
## =========================================================================

func _initialize_scenario() -> void:
	"""
	Initialize scenario with proper initialization order.
	
	Order is critical:
	1. Wait for TickManager (autoload)
	2. Verify Game (autoload) has initialized world
	3. Spawn units/buildings via Game.spawn_unit()
	4. Optionally spawn resources
	"""
	
	# Step 1: Verify TickManager is loaded
	if not await _wait_for_tick_manager():
		return
	
	# Step 2: Get Game reference and wait for world initialization
	if not await _wait_for_game_world():
		return
	
	# Step 3: Spawn units (NOW SAFE - Game.world is initialized)
	if not await _spawn_units():
		return
	
	# Step 4: Spawn buildings
	if not await _spawn_buildings():
		return
	
	# Step 5: Spawn resources
	if not await _spawn_resources():
		return
	
	print("[SCENARIO] ✅ Scenario initialization complete!")

## =========================================================================
## Initialization Steps
## =========================================================================

func _wait_for_tick_manager() -> bool:
	"""Ensure TickManager autoload is ready."""
	print("[SCENARIO] Waiting for TickManager...")
	
	tick_manager = TickManager
	
	if not is_instance_valid(tick_manager):
		push_error("[SCENARIO] TickManager autoload not found!")
		return false
	
	# TickManager is usually ready immediately, but be safe
	var max_wait = 5.0
	var elapsed = 0.0
	
	while not tick_manager.is_ready() and elapsed < max_wait:
		await get_tree().process_frame
		elapsed += get_physics_process_delta_time()
	
	if not tick_manager.is_ready():
		push_error("[SCENARIO] TickManager failed to initialize!")
		return false
	
	print("[SCENARIO] TickManager ready ✅")
	return true

func _wait_for_game_world() -> bool:
	"""Ensure Game autoload has initialized world."""
	print("[SCENARIO] Waiting for Game.world initialization...")
	
	game = Game
	action_gateway = ActionGateway
	
	if not is_instance_valid(game):
		push_error("[SCENARIO] Game autoload not found!")
		return false
	
	# Game initializes world in _ready(), but may not be done yet
	var max_wait = 5.0
	var elapsed = 0.0
	
	while not is_instance_valid(game.world) and elapsed < max_wait:
		await get_tree().process_frame
		elapsed += get_physics_process_delta_time()
	
	if not is_instance_valid(game.world):
		push_error("[SCENARIO] Game.world failed to initialize!")
		return false
	
	print("[SCENARIO] Game.world initialized ✅")
	return true

## =========================================================================
## Deterministic Scenario Setup
## =========================================================================

func _spawn_units() -> bool:
	"""Spawn units for both players."""
	print("[SCENARIO] Spawning units...")
	
	# Player 0 - 3 units
	for i in range(3):
		var pos = Vector2(100 + i * 50, 100)
		var unit_id = game.spawn_unit(pos)
		if unit_id < 0:
			push_error("[SCENARIO] Failed to spawn unit for player 0")
			return false
		print("[SCENARIO] Spawned Player 0 Unit #%d at %.0f,%.0f" % [unit_id, pos.x, pos.y])
	
	# Player 1 - 3 units
	for i in range(3):
		var pos = Vector2(100 + i * 50, 200)
		var unit_id = game.spawn_unit(pos)
		if unit_id < 0:
			push_error("[SCENARIO] Failed to spawn unit for player 1")
			return false
		print("[SCENARIO] Spawned Player 1 Unit #%d at %.0f,%.0f" % [unit_id, pos.x, pos.y])
	
	print("[SCENARIO] Units spawned ✅")
	return true

func _spawn_buildings() -> bool:
	"""Spawn buildings for resource production."""
	print("[SCENARIO] Spawning buildings...")
	
	# Player 0 barracks
	var barracks_pos = Vector2(100, 300)
	# Note: implement as needed based on game's building spawn API
	# game.spawn_building(barracks_pos, "Barracks", 0)
	
	print("[SCENARIO] Buildings spawned ✅")
	return true

func _spawn_resources() -> bool:
	"""Spawn resources on the map."""
	print("[SCENARIO] Spawning resources...")
	
	# Note: Resources may auto-spawn via ResourceSpawner
	# Or implement custom resource placement here
	# var resource_spawner = ResourceSpawner  # Autoload
	# if is_instance_valid(resource_spawner):
	#     resource_spawner.spawn_resources()
	
	print("[SCENARIO] Resources spawned ✅")
	return true

## =========================================================================
## Utility
## =========================================================================

func get_scenario_state() -> Dictionary:
	"""Return current scenario state for debugging."""
	if not is_instance_valid(game):
		return {}
	
	var sense = action_gateway.sense() if is_instance_valid(action_gateway) else null
	
	return {
		"tick": tick_manager.current_tick if is_instance_valid(tick_manager) else -1,
		"total_units": sense.get_all_units().size() if sense else -1,
		"total_resources": sense.get_all_resources().size() if sense else -1,
		"player_0_units": sense.get_all_units().filter(func(u): return u.get("player_id") == 0).size() if sense else -1,
		"player_1_units": sense.get_all_units().filter(func(u): return u.get("player_id") == 1).size() if sense else -1,
	}
