extends Node

const BASE_URL = "http://localhost:8080"

func _ready():
	GlobalSignals.game_room_ready.connect(_on_game_room_ready)
	GlobalSignals.game_room_running.connect(_on_game_room_running)
	GlobalSignals.game_room_ended.connect(_on_game_room_ended)
	GlobalSignals.game_room_crashed.connect(_on_game_room_crashed)

func _set_room_status(status: String, winner: String = ""):
	var room_id = Game.game_room_id
			
	var url = BASE_URL + "/rooms/" + room_id + "/status"
	
	var http_status = HTTPRequest.new()
	add_child(http_status)
	
	http_status.request_completed.connect(func(result, response_code, headers, body):
		if response_code == 200 or response_code == 201:
			print("Successfully set room ", room_id, " status to ", status)
		else:
			print("Failed to set room status. Code: ", response_code)
		http_status.queue_free()
	)
	
	var data = {"status": status}
	if winner != "":
		data["winner"] = winner
		
	var json_data = JSON.stringify(data)
	var custom_headers = ["Content-Type: application/json"]
	
	var err = http_status.request(url, custom_headers, HTTPClient.METHOD_POST, json_data)
	if err != OK:
		printerr("Could not initiate Set Status request.")
		http_status.queue_free()

func _on_game_room_ready():
	if Game.game_room_id == "testgame":
		_register_manual_game()
	else:
		_set_room_status("ready")

func _register_manual_game():
	var url = BASE_URL + "/rooms"
	
	var http_register = HTTPRequest.new()
	add_child(http_register)
	
	http_register.request_completed.connect(func(result, response_code, headers, body):
		if response_code == 200 or response_code == 201:
			print("Successfully registered manual room testgame")
			# Now set status to ready
			_set_room_status("ready")
		else:
			print("Failed to register manual room. Code: ", response_code)
		http_register.queue_free()
	)
	
	var port = Networking.server_port
			
	var data = {
		"roomId": Game.game_room_id,
		"address": "127.0.0.1",
		"port": port,
		"maxNumberOfPlayer": Networking.MAX_PLAYERS
	}
	
	var json_data = JSON.stringify(data)
	var custom_headers = ["Content-Type: application/json"]
	
	var err = http_register.request(url, custom_headers, HTTPClient.METHOD_POST, json_data)
	if err != OK:
		printerr("Could not initiate Register Manual Game request.")
		http_register.queue_free()

func _on_game_room_running():
	_set_room_status("running")

func _on_game_room_ended(winner_local_id: int):
	var winner_uuid = PlayerManager.get_uuid_for_local_id(winner_local_id)
	_set_room_status("ended", winner_uuid)

func _on_game_room_crashed():
	_set_room_status("crashed")

func join_player_to_room(room_id: String, player_id: String):
	var url = BASE_URL + "/rooms/" + room_id + "/players/" + player_id + "/join"
	
	# Create a temporary HTTPRequest node for this specific call
	var http_join = HTTPRequest.new()
	add_child(http_join)
	
	# Connect to a local lambda or function to clean up the node after completion
	http_join.request_completed.connect(func(result, response_code, headers, body):
		if response_code == 200 or response_code == 201:
			print("Successfully joined player ", player_id, " to ", room_id, " in GameRoomManager.")
		else:
			print("Failed to join player to GameRoomManager. Code: ", response_code)
		http_join.queue_free() # Clean up the node
	)
	
	var err = http_join.request(url, [], HTTPClient.METHOD_POST)
	if err != OK:
		printerr("Could not initiate Join Room request.")
		http_join.queue_free()
