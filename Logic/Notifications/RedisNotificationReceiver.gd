extends Node

signal plan_notified(game_id: String, player_id: String, unit_ids: Array)

var _redis_peer: StreamPeerTCP = StreamPeerTCP.new()
var _redis_connected: bool = false
var _redis_buffer: String = ""
var _room_id: String = ""

func _ready() -> void:
	_room_id = OS.get_environment("GAME_ROOM_ID")
	if _room_id.is_empty():
		_room_id = "testgame"
	_init_redis()

func _init_redis() -> void:
	var host = OS.get_environment("REDIS_HOST")
	if host.is_empty(): host = "127.0.0.1"
	var port_str = OS.get_environment("REDIS_PORT")
	var port = int(port_str) if not port_str.is_empty() else 6379
	
	print("RedisNotificationReceiver: connecting to %s:%d for room %s" % [host, port, _room_id])
	_redis_peer.connect_to_host(host, port)

func _process(_delta: float) -> void:
	_redis_peer.poll()
	var status = _redis_peer.get_status()
	
	if status == StreamPeerTCP.STATUS_CONNECTED:
		if not _redis_connected:
			_redis_connected = true
			print("RedisNotificationReceiver: connected to Redis")
			var topic = "planning." + _room_id + ".plan-updated"
			var cmd = "*2\r\n$9\r\nSUBSCRIBE\r\n$" + str(topic.length()) + "\r\n" + topic + "\r\n"
			_redis_peer.put_data(cmd.to_utf8_buffer())
		
		var avail = _redis_peer.get_available_bytes()
		if avail > 0:
			var data = _redis_peer.get_partial_data(avail)
			if data[0] == OK:
				_redis_buffer += data[1].get_string_from_utf8()
				_parse_redis_buffer()
				
	elif status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		if _redis_connected:
			print("RedisNotificationReceiver: disconnected from Redis, reconnecting...")
			_redis_connected = false
			_redis_buffer = ""
			_init_redis()

func _parse_redis_buffer() -> void:
	while _redis_buffer.length() > 0:
		var parsed = _parse_resp(_redis_buffer)
		if parsed.has("error"):
			break # Wait for more data
		
		var resp_val = parsed["value"]
		_redis_buffer = _redis_buffer.substr(parsed["length"])
		
		if typeof(resp_val) == TYPE_ARRAY and resp_val.size() == 3:
			var type = str(resp_val[0])
			if type == "message":
				var payload = str(resp_val[2])
				_handle_pubsub_payload(payload)

func _parse_resp(buffer: String) -> Dictionary:
	if buffer.length() == 0:
		return {"error": "incomplete"}
	var type_char = buffer.substr(0, 1)
	if type_char == "*": # Array
		var line_end = buffer.find("\r\n")
		if line_end == -1: return {"error": "incomplete"}
		var count = int(buffer.substr(1, line_end - 1))
		var current_pos = line_end + 2
		var arr = []
		for i in range(count):
			var sub_buf = buffer.substr(current_pos)
			var el = _parse_resp(sub_buf)
			if el.has("error"): return {"error": "incomplete"}
			arr.append(el["value"])
			current_pos += el["length"]
		return {"value": arr, "length": current_pos}
		
	elif type_char == "$": # Bulk String
		var line_end = buffer.find("\r\n")
		if line_end == -1: return {"error": "incomplete"}
		var length = int(buffer.substr(1, line_end - 1))
		if length == -1:
			return {"value": null, "length": line_end + 2}
		var data_start = line_end + 2
		var data_end = data_start + length
		if buffer.length() < data_end + 2: return {"error": "incomplete"}
		var value = buffer.substr(data_start, length)
		return {"value": value, "length": data_end + 2}
		
	elif type_char == ":": # Integer
		var line_end = buffer.find("\r\n")
		if line_end == -1: return {"error": "incomplete"}
		var value = int(buffer.substr(1, line_end - 1))
		return {"value": value, "length": line_end + 2}
		
	elif type_char == "+" or type_char == "-": # Simple String / Error
		var line_end = buffer.find("\r\n")
		if line_end == -1: return {"error": "incomplete"}
		var value = buffer.substr(1, line_end - 1)
		return {"value": value, "length": line_end + 2}
		
	return {"error": "unknown type"}

func _handle_pubsub_payload(body_text: String) -> void:
	print("RedisNotificationReceiver: payload received: %s" % body_text)
	var json = JSON.new()
	if json.parse(body_text) != OK:
		push_warning("RedisNotificationReceiver: JSON parse error in payload: '%s'" % body_text)
		return
		
	var body: Dictionary = json.get_data()
	var game_id: String   = body.get("game_id", "")
	var player_id: String = body.get("player_id", "")
	var unit_ids: Array   = body.get("unit_ids", [])
	
	if game_id.is_empty() or player_id.is_empty() or unit_ids.is_empty():
		push_warning("RedisNotificationReceiver: missing fields in notification")
		return
		
	plan_notified.emit(game_id, player_id, unit_ids)
