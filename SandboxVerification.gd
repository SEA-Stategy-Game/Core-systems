extends Node
class_name SandboxVerification

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
	
	var sense = gateway.sense()
	var units = sense.get_all_units()
	if units.is_empty():
		print("[ENTITY_NOT_FOUND] No units found to test.")
		get_tree().quit()
		return
		
	var test_unit_id: int = units[0]["id"]
	var start_pos: Vector2 = Vector2(units[0]["position"]["x"], units[0]["position"]["y"])
	var target_pos: Vector2 = start_pos + Vector2(100, 100)
	
	print("[SENSE_QUERY] Sending MOVE command to unit ", test_unit_id)
	gateway.move_unit(test_unit_id, target_pos)
	
	# Wait slightly for queue to process
	await get_tree().create_timer(0.2).timeout
	
	var status = sense.get_unit_status(test_unit_id)
	print("[DATA_SNAPSHOT] Unit status after move: is_idle = ", status["is_idle"])
	
	if status["is_idle"] == false:
		print("[SENSE_QUERY] Successfully verified unit is BUSY.")
	else:
		print("[DIAGNOSTIC_ERR] Unit is unexpectedly IDLE after command.")
		
func _on_unit_idled(unit_id: int) -> void:
	var sense = get_node("/root/ActionGateway").sense()
	var status = sense.get_unit_status(unit_id)
	print("[UNIT_IDLE] Unit ", unit_id, " emitted unit_idled signal.")
	print("[DATA_SNAPSHOT] Unit status: is_idle = ", status["is_idle"])
	if status["is_idle"] == true:
		print("[API_SUCCESS] Verified unit properly returned to IDLE state.")
		# Test complete
		get_tree().quit()
