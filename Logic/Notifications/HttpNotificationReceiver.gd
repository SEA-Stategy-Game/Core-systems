extends Node

signal plan_notified(game_id: String, player_id: String, unit_ids: Array)
signal game_state_requested(peer: StreamPeerTCP)

const LISTEN_PORT = 8085
var _server: TCPServer = TCPServer.new()

func _ready() -> void:
	if _server.listen(LISTEN_PORT, "127.0.0.1") != OK:
		push_error("HttpNotificationReceiver: failed to listen on port %d" % LISTEN_PORT)
		return
	print("HttpNotificationReceiver: listening on port %d" % LISTEN_PORT)

func _process(_delta: float) -> void:
	if _server.is_connection_available():
		_handle_connection(_server.take_connection())

func _handle_connection(peer: StreamPeerTCP) -> void:
	print("HttpNotificationReceiver: incoming connection")
	var raw = ""
	var deadline = Time.get_ticks_msec() + 2000

	while Time.get_ticks_msec() < deadline:
		var n = peer.get_available_bytes()
		if n > 0:
			raw += peer.get_string(n)
			if "\r\n\r\n" in raw:
				break
		OS.delay_msec(1)

	if not "\r\n\r\n" in raw:
		push_warning("HttpNotificationReceiver: timeout - no headers received")
		_respond(peer, 400)
		return

	var first_line: String = raw.split("\r\n")[0]
	if first_line.begins_with("GET /game-state"):
		game_state_requested.emit(peer)
		return

	var content_length = 0
	for line in raw.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			content_length = int(line.split(":")[1].strip_edges())
			break

	var header_end = raw.find("\r\n\r\n") + 4
	var body_so_far = raw.length() - header_end
	deadline = Time.get_ticks_msec() + 1000
	while body_so_far < content_length and Time.get_ticks_msec() < deadline:
		var n = peer.get_available_bytes()
		if n > 0:
			raw += peer.get_string(n)
			body_so_far = raw.length() - header_end
		OS.delay_msec(1)

	var body_text = raw.substr(header_end)
	print("HttpNotificationReceiver: body received: %s" % body_text)

	var json = JSON.new()
	if json.parse(body_text) != OK:
		push_warning("HttpNotificationReceiver: JSON parse error in body: '%s'" % body_text)
		_respond(peer, 400)
		return

	var body: Dictionary = json.get_data()
	var game_id: String   = body.get("game_id", "")
	var player_id: String = body.get("player_id", "")
	var unit_ids: Array   = body.get("unit_ids", [])

	print("HttpNotificationReceiver: notification - game=%s player=%s units=%s" % [game_id, player_id, str(unit_ids)])

	if game_id.is_empty() or player_id.is_empty() or unit_ids.is_empty():
		push_warning("HttpNotificationReceiver: missing fields in notification")
		_respond(peer, 422)
		return

	_respond(peer, 200)
	peer.disconnect_from_host()
	
	plan_notified.emit(game_id, player_id, unit_ids)

func _respond(peer: StreamPeerTCP, code: int) -> void:
	var msg = "OK" if code == 200 else "Error"
	peer.put_data(
		("HTTP/1.1 %d %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" % [code, msg])
		.to_utf8_buffer()
	)
