extends Node
@export var server_gateway: Node 

func _ready():
	# We only want the Server (Host) to run the scenario logic
	if multiplayer.is_server():
		# Small delay to ensure the server is fully started
		get_tree().create_timer(1.0).timeout.connect(setup_scenario)

func setup_scenario():
	if not multiplayer.is_server(): return
	var saved_state = TaskSerializer.load_state()
	TaskSerializer.restore_queues(get_tree(), saved_state)
	
	server_gateway.spawn_unit(1, Vector2(150, 150), 101) # Player 1 Unit
