extends Node

## -----------------------------------------------------------------------
## TickManager -- authoritative simulation tick.
## All AI-triggered actions are synchronised to this tick to maintain
## the server-side "Source of Truth".
## -----------------------------------------------------------------------


signal tick_processed(count: int)

var tick_interval: float = 0.5   # 2 ticks per second
var time_passed: float = 0.0
var tick_count: int = 0

## Auto-save interval (in ticks).  0 = disabled.
var auto_save_interval: int = 60  # 60 = Every 30 seconds at 2 tps

## Heartbeat stuff
@export var heartbeat_interval: int = 10
var room_id: String = ""
var room_manager_url: String = "http://localhost:8080"
var http_client: HTTPRequest

## Get the auto-save interval in actual seconds
func get_auto_save_interval_seconds() -> float:
	return tick_interval * auto_save_interval

func _ready() -> void:
	http_client = HTTPRequest.new()
	add_child(http_client)
	room_id = OS.get_environment("ROOM_ID")
	var env_url = OS.get_environment("ROOM_MANAGER_URL")
	if env_url != "":
		room_manager_url = env_url
	
	## This bit is needed for the heartbeat funct
	if room_id == "":
		room_id = "testgame"
		print("ROOM_ID not found, defaulting to: ", room_id)
	
	var env_auto_save = OS.get_environment("AUTO_SAVE_INTERVAL") 
	if env_auto_save != "":
		var parsed_auto_save = env_auto_save.to_int()
		if parsed_auto_save >= 0:
			auto_save_interval = parsed_auto_save
			print("[TickManager] auto_save_interval set to ", auto_save_interval, " via environment variable.")

func _process(delta: float) -> void:
	time_passed += delta
	if time_passed >= tick_interval:
		tick_count += 1
		time_passed = 0.0

		_process_simulation()
		tick_processed.emit(tick_count)

func _process_simulation() -> void:
	print("--- TICK ", tick_count, " ---")

	# 1. Pull the AI team's latest plan via the ActionGateway.
	#    ActionGateway handles plan -> CommandQueue translation internally.
	if Engine.has_singleton("ActionGateway"):
		pass  # Singletons registered via project.godot
	var gateway = get_node_or_null("/root/ActionGateway")
	if gateway and gateway.has_method("pull_and_execute"):
		gateway.pull_and_execute()

	# 2. Command queues are ticked per-unit in Unit._physics_process,
	#    which runs every physics frame (not just on tick boundaries).
	#    The tick boundary is used here only for plan polling and
	#    bookkeeping.
	
	# 2.5. Heartbeat stuff
	if tick_count % heartbeat_interval == 0:
		_send_heartbeat()

	# 3. Periodic auto-save of AI task state.
	if auto_save_interval > 0 and tick_count % auto_save_interval == 0:
		if gateway and gateway.has_method("save_task_state"):
			gateway.save_task_state()
	
	# 4. Broadcast the state to any connected peers.  Guard against the
	#    Networking autoload not being present (e.g. solo-play builds).
	var net = get_node_or_null("/root/Networking")
	if net != null and net.has_method("broadcast_state"):
		net.broadcast_state(tick_count)

# Heartbeat funct, as seen above this only sends at a certain interval
# Most of the code is in the GRM repo.
func _send_heartbeat() -> void:
	## this really isn't needed if I'm being honest, but it's here!
	if room_id == "":
		print("--- Skipping heartbeat: No ROOM_ID set ---")
		return
	
	if http_client.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return 
		
	var url = "%s/rooms/%s/heartbeat" % [room_manager_url, room_id]
	var headers = ["Content-Type: application/json"]
	
	var error = http_client.request(url, headers, HTTPClient.METHOD_POST)
	if error != OK:
		print("--- Failed to initiate heartbeat request. ---")
	else: print("--- Sent heartbeat ---")
