extends Node

const BASE_URL = "http://localhost:8080"

func _ready():
	GlobalSignals.game_room_ready.connect(_on_game_room_ready)
	GlobalSignals.game_room_running.connect(_on_game_room_running)
	GlobalSignals.game_room_ended.connect(_on_game_room_ended)
	GlobalSignals.game_room_crashed.connect(_on_game_room_crashed)

func _set_room_status(status: String, winner: String = "", reason: String = ""):
	# During shutdown (_exit_tree), the scene tree is being dismantled. Node-based
	# asynchronous operations like HTTPRequest will fail. For the final "crashed" status
	# on exit, we must use a blocking, low-level HTTPClient.
	if status == "crashed":
		_send_blocking_shutdown_status(status, reason)
		return

	var http_request = HTTPRequest.new()
	add_child(http_request)

	var room_id = Game.game_room_id

	var url = BASE_URL + "/rooms/" + room_id + "/status"

	http_request.request_completed.connect(func(result, response_code, headers, body):
		if response_code == 200 or response_code == 201:
			print("Successfully set room ", room_id, " status to ", status)
		else:
			print("Failed to set room status. Code: ", response_code)
		http_request.queue_free()
	, CONNECT_ONE_SHOT)

	var data = {"status": status}
	if winner != "":
		data["winner"] = winner
	if reason != "":
		data["statusReason"] = reason

	var json_data = JSON.stringify(data)
	var custom_headers = ["Content-Type: application/json"]

	var err = http_request.request(url, custom_headers, HTTPClient.METHOD_POST, json_data)
	if err != OK:
		printerr("Could not initiate Set Status request.")
		http_request.queue_free()


func _on_game_room_ready():
	if Game.game_room_id.begins_with("test"):
		_register_manual_game()
	else:
		_set_room_status("ready")

func _register_manual_game():
	var http_request = HTTPRequest.new()
	add_child(http_request)

	var url = BASE_URL + "/rooms"

	http_request.request_completed.connect(func(result, response_code, headers, body):
		if response_code == 200 or response_code == 201:
			print("Successfully registered manual room testgame")
			# Now set status to ready
			_set_room_status("ready")
		else:
			print("Failed to register manual room. Code: ", response_code)
		http_request.queue_free()
	, CONNECT_ONE_SHOT)

	var port = Networking.server_port

	var data = {
		"roomId": Game.game_room_id,
		"address": "127.0.0.1",
		"port": port,
		"maxNumberOfPlayer": Networking.MAX_PLAYERS
	}

	var json_data = JSON.stringify(data)
	var custom_headers = ["Content-Type: application/json"]

	var err = http_request.request(url, custom_headers, HTTPClient.METHOD_POST, json_data)
	if err != OK:
		printerr("Could not initiate Register Manual Game request.")
		http_request.queue_free()

func _on_game_room_running():
	_set_room_status("running")

func _on_game_room_ended(winner_local_id: int, reason: String):
	var winner_uuid = ""
	if winner_local_id != -1:
		winner_uuid = PlayerManager.get_uuid_for_local_id(winner_local_id)
	_set_room_status("ended", winner_uuid, reason)

func _on_game_room_crashed(reason: String):
	_set_room_status("crashed", "", reason)

func join_player_to_room(room_id: String, player_id: String):
	var http_request = HTTPRequest.new()
	add_child(http_request)

	var url = BASE_URL + "/rooms/" + room_id + "/players/" + player_id + "/join"

	http_request.request_completed.connect(func(result, response_code, headers, body):
		if response_code == 200 or response_code == 201:
			print("Successfully joined player ", player_id, " to ", room_id, " in GameRoomManager.")
		else:
			print("Failed to join player to GameRoomManager. Code: ", response_code)
		http_request.queue_free()
	, CONNECT_ONE_SHOT)

	var err = http_request.request(url, [], HTTPClient.METHOD_POST)
	if err != OK:
		printerr("Could not initiate Join Room request.")
		http_request.queue_free()
		
func _send_blocking_shutdown_status(status: String, reason: String):
	# This function uses the low-level HTTPClient to send a final, blocking status update.
	# It is required because when the game engine is shutting down (in _exit_tree),
	# the normal scene tree is being dismantled, and Node-based asynchronous operations
	# like HTTPRequest will fail. This synchronous method ensures the message is sent
	# before the application process terminates.
	print("[SHUTDOWN] Sending blocking status update: ", status)
	var http_client = HTTPClient.new()

	# Manually parse BASE_URL to get host, port, and SSL status
	var use_ssl = BASE_URL.begins_with("https")
	var stripped_url = BASE_URL.trim_prefix("http://").trim_prefix("https://")
	var host = stripped_url
	var port = 80 if not use_ssl else 443
	if ":" in stripped_url:
		host = stripped_url.get_slice(":", 0)
		port = stripped_url.get_slice(":", 1).to_int()

	var tls_options = TLSOptions.client() if use_ssl else null
	var err = http_client.connect_to_host(host, port, tls_options)
	if err != OK:
		printerr("[SHUTDOWN] HTTPClient connect_to_host failed to start.")
		return

	# Block and wait for connection to establish, with a timeout
	var start_time = Time.get_ticks_msec()
	while http_client.get_status() == HTTPClient.STATUS_CONNECTING or http_client.get_status() == HTTPClient.STATUS_RESOLVING:
		http_client.poll()
		OS.delay_msec(10) # Prevent busy-waiting which can starve the connection thread
		if Time.get_ticks_msec() - start_time > 2000: # 2-second timeout
			printerr("[SHUTDOWN] HTTPClient connection timed out.")
			return

	if http_client.get_status() != HTTPClient.STATUS_CONNECTED:
		printerr("[SHUTDOWN] HTTPClient failed to connect. Status: ", http_client.get_status())
		return

	var room_id = Game.game_room_id
	var url_path = "/rooms/" + room_id + "/status"
	var data = {"status": status, "statusReason": reason}
	var json_data = JSON.stringify(data)
	
	# The Host header is required by many web servers.
	var host_header_value = host
	if (use_ssl and port != 443) or (not use_ssl and port != 80):
		host_header_value += ":" + str(port)
	var headers = ["Content-Type: application/json", "Host: " + host_header_value]

	err = http_client.request(HTTPClient.METHOD_POST, url_path, headers, json_data)
	if err != OK:
		printerr("[SHUTDOWN] HTTPClient request failed to start.")
		return

	# The request is now in flight. We must poll and wait for the request to complete,
	# otherwise the application will terminate before the OS has a chance to send the data.
	start_time = Time.get_ticks_msec()
	while http_client.get_status() != HTTPClient.STATUS_DISCONNECTED and http_client.get_status() != HTTPClient.STATUS_CONNECTION_ERROR:
		http_client.poll()
		# has_response() is true once the headers are received.
		if http_client.has_response():
			print("[SHUTDOWN] Server responded with code: ", http_client.get_response_code())
			# We can break now, the message was received and processed.
			break
		if Time.get_ticks_msec() - start_time > 2000: # 2-second timeout for the whole operation
			printerr("[SHUTDOWN] HTTPClient request timed out while waiting for response.")
			break
		OS.delay_msec(10) # Prevent busy-waiting

	print("[SHUTDOWN] Blocking status update request sent.")
