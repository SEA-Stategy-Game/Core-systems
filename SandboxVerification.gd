extends Node
class_name SandboxVerification

## -----------------------------------------------------------------------
## Sandbox verification for:
##   1. Chop-and-return composite command (unit returns to Barracks)
##   2. Player ownership validation (cross-player command rejection)
##   3. Idle / busy unit monitoring
## -----------------------------------------------------------------------

var _test_unit_id: int = -1
var _test_start_pos: Vector2 = Vector2.ZERO
var _test_phase: String = "INIT"

func _ready() -> void:
	print("[TEST_RUNNING] SandboxVerification starting...")
	# Wait for systems to load
	await get_tree().create_timer(1.0).timeout
	
	var gateway = get_node_or_null("/root/ActionGateway")
	if gateway == null:
		print("[DIAGNOSTIC_ERR] Cannot find ActionGateway.")
		get_tree().quit()
		return
	
	gateway.unit_idled.connect(_on_unit_idled)
	gateway.task_completed.connect(_on_task_completed)
	
	var sense = gateway.sense()
	var units = sense.get_all_units()
	if units.is_empty():
		print("[ENTITY_NOT_FOUND] No units found to test.")
		get_tree().quit()
		return
	
	_test_unit_id = units[0]["id"]
	_test_start_pos = Vector2(units[0]["position"]["x"], units[0]["position"]["y"])
	
	# ---------------------------------------------------------------
	# TEST 1: Player Ownership Validation
	# ---------------------------------------------------------------
	print("")
	print("=== TEST 1: Player Ownership Validation ===")
	var target_pos: Vector2 = _test_start_pos + Vector2(100, 100)
	
	# Attempt to move unit 0 (player 0) with player_id = 1 -- should fail
	var result = gateway.move_unit(_test_unit_id, target_pos, 1)
	if result == false:
		print("[API_SUCCESS] Ownership check correctly rejected cross-player command.")
	else:
		print("[DIAGNOSTIC_ERR] Ownership check FAILED -- allowed cross-player command.")
	
	# Attempt with correct player_id = 0 -- should succeed
	result = gateway.move_unit(_test_unit_id, target_pos, 0)
	if result == true:
		print("[API_SUCCESS] Ownership check correctly allowed same-player command.")
	else:
		print("[DIAGNOSTIC_ERR] Ownership check FAILED -- rejected same-player command.")
	
	# Wait for movement to begin
	await get_tree().create_timer(0.5).timeout
	
	# ---------------------------------------------------------------
	# TEST 2: Idle / Busy Unit Monitoring
	# ---------------------------------------------------------------
	print("")
	print("=== TEST 2: Idle / Busy Unit Monitoring ===")
	var busy = sense.get_busy_units(0)
	var idle = sense.get_idle_units(0)
	print("[IDLE_REPORT] Busy units (player 0): ", busy)
	print("[IDLE_REPORT] Idle units (player 0): ", idle)
	
	# ---------------------------------------------------------------
	# TEST 3: Chop-and-Return Composite Command
	# ---------------------------------------------------------------
	print("")
	print("=== TEST 3: Chop-and-Return Composite Command ===")
	
	# Wait for movement test to finish
	await get_tree().create_timer(5.0).timeout
	
	# Find a tree to target
	var resources = sense.get_all_resources()
	if resources.is_empty():
		print("[ENTITY_NOT_FOUND] No resources found. Skipping chop-and-return test.")
		print("[TEST_COMPLETE] Sandbox verification finished (partial).")
		return
	
	var tree_id: int = resources[0]["id"]
	print("[SENSE_QUERY] Sending CHOP_AND_RETURN to unit ", _test_unit_id, " targeting resource ", tree_id)
	
	_test_phase = "CHOP_AND_RETURN"
	result = gateway.go_chop_tree_and_return(_test_unit_id, tree_id, 0)
	if result:
		print("[API_SUCCESS] Chop-and-return command enqueued successfully.")
	else:
		print("[DIAGNOSTIC_ERR] Failed to enqueue chop-and-return command.")
	
	# Verify unit is now busy
	await get_tree().create_timer(0.5).timeout
	var status = sense.get_unit_status(_test_unit_id)
	print("[DATA_SNAPSHOT] Unit status after chop-and-return: is_idle = ", status.get("is_idle", "N/A"))
	
	if status.get("is_idle", true) == false:
		print("[SENSE_QUERY] Successfully verified unit is BUSY during chop-and-return.")
	else:
		print("[DIAGNOSTIC_ERR] Unit is unexpectedly IDLE after chop-and-return command.")

func _on_task_completed(unit_id: int, action_data: Dictionary) -> void:
	print("[DATA_SNAPSHOT] Task completed for unit ", unit_id, ": ", action_data.get("type", "UNKNOWN"))

func _on_unit_idled(unit_id: int) -> void:
	if unit_id != _test_unit_id:
		return
	
	var sense = get_node("/root/ActionGateway").sense()
	var status = sense.get_unit_status(unit_id)
	print("[UNIT_IDLE] Unit ", unit_id, " emitted unit_idled signal.")
	print("[DATA_SNAPSHOT] Unit status: is_idle = ", status.get("is_idle", "N/A"))
	
	if _test_phase == "CHOP_AND_RETURN":
		# Verify the unit has returned near a barracks
		var barracks_nodes = get_tree().get_nodes_in_group("barracks")
		if barracks_nodes.size() > 0:
			var unit_node = null
			for u in get_tree().get_nodes_in_group("units"):
				if u is CharacterBody2D:
					var uid = u.entity_id if "entity_id" in u else u.get_instance_id()
					if uid == unit_id:
						unit_node = u
						break
			
			if unit_node:
				var closest_dist: float = INF
				for b in barracks_nodes:
					var d = unit_node.global_position.distance_to(b.global_position)
					if d < closest_dist:
						closest_dist = d
				
				print("[DATA_SNAPSHOT] Unit distance to nearest barracks: ", closest_dist)
				if closest_dist < 50.0:
					print("[API_SUCCESS] Unit successfully returned to barracks after chopping.")
				else:
					print("[DIAGNOSTIC_ERR] Unit did not return close enough to barracks. Distance: ", closest_dist)
		
		if status.get("is_idle", false) == true:
			print("[API_SUCCESS] Verified unit properly returned to IDLE state after chop-and-return.")
		else:
			print("[DIAGNOSTIC_ERR] Unit is not IDLE after chop-and-return completion.")
		
		print("")
		print("=== ALL TESTS COMPLETE ===")
		print("[TEST_COMPLETE] Sandbox verification finished.")
