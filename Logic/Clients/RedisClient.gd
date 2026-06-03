## RedisClient.gd (Autoload Singleton)
## -----------------------------------------------------------------------
## A lightweight, native GDScript Redis client using StreamPeerTCP.
## Translates commands into the Redis Serialization Protocol (RESP).
## -----------------------------------------------------------------------
extends Node

var redis_flag = ""

var host: String = "127.0.0.1"
var port: int = 6379

var _tcp: StreamPeerTCP = StreamPeerTCP.new()
var _tcp_pubsub: StreamPeerTCP = StreamPeerTCP.new()
var _subscriptions: Dictionary = {}
var _read_buffer: String = ""

var _was_tcp_connected: bool = false
var _was_pubsub_connected: bool = false
var _reconnect_timer: float = 0.0
var _connecting_timer: float = 0.0

func _ready() -> void:
	
	redis_flag = OS.get_environment("USE_REDIS")
	if redis_flag != "true" and redis_flag != "1":
		return
	
	var env_host = OS.get_environment("REDIS_HOST")
	if env_host != "": host = env_host
	var env_port = OS.get_environment("REDIS_PORT")
	if env_port != "": port = env_port.to_int()

	var main_err = _tcp.connect_to_host(host, port)
	var pubsub_err = _tcp_pubsub.connect_to_host(host, port)
	if main_err != OK or pubsub_err != OK:
		push_error("[REDIS] Failed to initiate connection to %s:%d" % [host, port])
	else:
		print("[REDIS] Connecting to %s:%d..." % [host, port])

func _process(_delta: float) -> void:
	if redis_flag != "true" and redis_flag != "1":
		return 
		
	_tcp.poll()
	_tcp_pubsub.poll()
	
	var tcp_status = _tcp.get_status()
	var pubsub_status = _tcp_pubsub.get_status()
	
	# --- Connection Timeout ---
	if tcp_status == StreamPeerTCP.STATUS_CONNECTING or pubsub_status == StreamPeerTCP.STATUS_CONNECTING:
		_connecting_timer += _delta
		if _connecting_timer >= 5.0:
			push_warning("[REDIS] Connection attempt timed out (5s). Forcing disconnect...")
			_tcp.disconnect_from_host()
			_tcp_pubsub.disconnect_from_host()
			_connecting_timer = 0.0
	else:
		_connecting_timer = 0.0

	if tcp_status == StreamPeerTCP.STATUS_CONNECTED:
		if not _was_tcp_connected:
			_was_tcp_connected = true
			print("[REDIS] Main TCP socket connected.")
		var avail = _tcp.get_available_bytes()
		if avail > 0:
			# Consume normal responses (+OK, etc) so the TCP buffer doesn't overflow
			_tcp.get_utf8_string(avail) 
	elif tcp_status == StreamPeerTCP.STATUS_ERROR:
		if _was_tcp_connected:
			print("[REDIS] Main TCP socket connection lost.")
		_was_tcp_connected = false
	
	if pubsub_status == StreamPeerTCP.STATUS_CONNECTED:
		if not _was_pubsub_connected:
			_was_pubsub_connected = true
			print("[REDIS] PubSub TCP socket connected. Sending pending subscriptions...")
			for channel in _subscriptions.keys():
				_send_pubsub_command(["SUBSCRIBE", channel])
				
		var avail = _tcp_pubsub.get_available_bytes()
		if avail > 0:
			var data = _tcp_pubsub.get_utf8_string(avail)
			_handle_incoming_data(data)
	elif pubsub_status == StreamPeerTCP.STATUS_ERROR:
		if _was_pubsub_connected:
			print("[REDIS] PubSub TCP socket connection lost.")
		_was_pubsub_connected = false
		
	# --- Auto-Reconnect Logic ---
	if tcp_status != StreamPeerTCP.STATUS_CONNECTED or pubsub_status != StreamPeerTCP.STATUS_CONNECTED:
		_reconnect_timer -= _delta
		if _reconnect_timer <= 0.0:
			if tcp_status == StreamPeerTCP.STATUS_NONE or tcp_status == StreamPeerTCP.STATUS_ERROR:
				print("[REDIS] Main socket is down. Retrying %s:%d..." % [host, port])
				_tcp.connect_to_host(host, port)
			if pubsub_status == StreamPeerTCP.STATUS_NONE or pubsub_status == StreamPeerTCP.STATUS_ERROR:
				print("[REDIS] PubSub socket is down. Retrying %s:%d..." % [host, port])
				_tcp_pubsub.connect_to_host(host, port)
			_reconnect_timer = 3.0

## Core internal method to encode and send RESP arrays
func _send_command(args: Array) -> void:
	if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
		
	var req = "*%d\r\n" % args.size()
	for arg in args:
		var s = str(arg)
		var byte_length = s.to_utf8_buffer().size()
		req += "$%d\r\n%s\r\n" % [byte_length, s]
		
	_tcp.put_data(req.to_utf8_buffer())

## Internal method specifically for PubSub commands on the secondary connection
func _send_pubsub_command(args: Array) -> void:
	if _tcp_pubsub.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
		
	var req = "*%d\r\n" % args.size()
	for arg in args:
		var s = str(arg)
		var byte_length = s.to_utf8_buffer().size()
		req += "$%d\r\n%s\r\n" % [byte_length, s]
		
	_tcp_pubsub.put_data(req.to_utf8_buffer())

# =================================================================
# Expose Redis Commands
# =================================================================

func sadd(key: String, value: String) -> void:
	_send_command(["SADD", key, value])

func sadd_array(key: String, values: Array) -> void:
	if values.is_empty():
		return
	var cmd = ["SADD", key]
	cmd.append_array(values)
	_send_command(cmd)

func srem(key: String, value: String) -> void:
	_send_command(["SREM", key, value])

## Named `set_value` instead of `set` to avoid shadowing Godot's built-in Node.set()
func set_value(key: String, value: String) -> void:
	_send_command(["SET", key, value])

func get_value(key: String) -> String:
	# Flush any pending async responses to avoid reading a "+OK" instead of our string
	if _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_tcp.poll()
		if _tcp.get_available_bytes() > 0:
			_tcp.get_utf8_string(_tcp.get_available_bytes())
			
	_send_command(["GET", key])
	var max_wait = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < max_wait:
		_tcp.poll()
		var avail = _tcp.get_available_bytes()
		if avail > 0:
			var data = _tcp.get_utf8_string(avail)
			if data.begins_with("$"):
				var nl_idx = data.find("\r\n")
				if nl_idx != -1:
					var str_len = data.substr(1, nl_idx - 1).to_int()
					if str_len == -1: return ""
					return data.substr(nl_idx + 2, str_len)
			return ""
		OS.delay_msec(10)
	return ""

func expire(key: String, seconds: int) -> void:
	_send_command(["EXPIRE", key, str(seconds)])

func del_key(key: String) -> void:
	_send_command(["DEL", key])

func subscribe(channel: String, callable: Callable) -> void:
	_subscriptions[channel] = callable
	_send_pubsub_command(["SUBSCRIBE", channel])

# =================================================================
# Basic PubSub Parsing
# =================================================================
func _handle_incoming_data(data: String) -> void:
	_read_buffer += data
	
	# Robust RESP parser that handles fragmented TCP packets 
	# and multiline JSON payloads correctly
	while _read_buffer.begins_with("*3\r\n"):
		var ptr = 4
		var elements = []
		var is_complete = true
		
		for i in range(3):
			if ptr >= _read_buffer.length():
				is_complete = false
				break
				
			var char_type = _read_buffer[ptr]
			var rn_pos = _read_buffer.find("\r\n", ptr)
			if rn_pos == -1:
				is_complete = false
				break
				
			if char_type == '$':
				var length_str = _read_buffer.substr(ptr + 1, rn_pos - ptr - 1)
				var str_len = length_str.to_int()
				var content_start = rn_pos + 2
				var content_end = content_start + str_len
				
				if content_end + 2 > _read_buffer.length():
					is_complete = false
					break
					
				var content = _read_buffer.substr(content_start, str_len)
				elements.append(content)
				ptr = content_end + 2
				
			elif char_type == ':':
				var int_str = _read_buffer.substr(ptr + 1, rn_pos - ptr - 1)
				elements.append(int_str)
				ptr = rn_pos + 2
			else:
				_read_buffer = ""
				return
				
		if not is_complete:
			break
			
		if elements.size() == 3:
			if elements[0] == "message":
				if _subscriptions.has(elements[1]):
					_subscriptions[elements[1]].call(elements[1], elements[2])
				
		_read_buffer = _read_buffer.substr(ptr)

	# Recover buffer if misaligned
	if _read_buffer.length() > 0 and not _read_buffer.begins_with("*3\r\n"):
		var next_start = _read_buffer.find("*3\r\n")
		if next_start != -1:
			_read_buffer = _read_buffer.substr(next_start)
		elif _read_buffer.length() > 4096:
			_read_buffer = ""
