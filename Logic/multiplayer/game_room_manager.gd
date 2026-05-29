extends Node

const BASE_URL = "http://localhost:8080"

func _ready():
	pass

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
