extends Node

signal tick_processed(count)

var tick_interval: float = 0.5 # 2 Ticks per second
var time_passed: float = 0.0
var tick_count: int = 0

func _process(delta):
	time_passed += delta
	if time_passed >= tick_interval:
		tick_count += 1
		time_passed = 0
		
		_process_simulation()
		tick_processed.emit(tick_count)

func _process_simulation():
	# CORE calls the AI's getPlan function
	print("--- TICK ", tick_count, " ---")
	
	# check all units and see if they have a new plan to pull
	var all_units = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		pass # Logic to call AI_Group.get_plan(unit)
