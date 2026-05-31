## RedisClient.gd (Autoload Singleton)
## -----------------------------------------------------------------------
## A lightweight, native GDScript Redis client using StreamPeerTCP.
## Translates commands into the Redis Serialization Protocol (RESP).
## -----------------------------------------------------------------------
extends Node

var host: String = "127.0.0.1"
var port: int = 6379

var _tcp: StreamPeerTCP = StreamPeerTCP.new()
var _tcp_pubsub: StreamPeerTCP = StreamPeerTCP.new()
var _subscriptions: Dictionary = {}
var _read_buffer: String = ""

func _ready() -> void:
	var err = _tcp.connect_to_host(host, port)
	_tcp_pubsub.connect_to_host(host, port)
	if err != OK:
		push_error("[REDIS] Failed to connect to %s:%d" % [host, port])
	else:
		print("[REDIS] Connecting to %s:%d..." % [host, port])

func _process(_delta: float) -> void:
	_tcp.poll()
	if _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var avail = _tcp.get_available_bytes()
		if avail > 0:
			# Consume normal responses (+OK, etc) so the TCP buffer doesn't overflow
			_tcp.get_utf8_string(avail) 
	
	_tcp_pubsub.poll()
	if _tcp_pubsub.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var avail = _tcp_pubsub.get_available_bytes()
		if avail > 0:
			var data = _tcp_pubsub.get_utf8_string(avail)
			_handle_incoming_data(data)

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

func srem(key: String, value: String) -> void:
	_send_command(["SREM", key, value])

## Named `set_value` instead of `set` to avoid shadowing Godot's built-in Node.set()
func set_value(key: String, value: String) -> void:
	_send_command(["SET", key, value])

func expire(key: String, seconds: int) -> void:
	_send_command(["EXPIRE", key, str(seconds)])

func subscribe(channel: String, callable: Callable) -> void:
	_subscriptions[channel] = callable
	_send_pubsub_command(["SUBSCRIBE", channel])

# =================================================================
# Basic PubSub Parsing
# =================================================================
func _handle_incoming_data(data: String) -> void:
	_read_buffer += data
	
	while _read_buffer.contains("*3\r\n"):
		var parts = _read_buffer.split("\r\n")
		if parts.size() >= 7 and parts[2] == "message":
			if _subscriptions.has(parts[4]):
				_subscriptions[parts[4]].call(parts[4], parts[6])
		_read_buffer = "" # Flush buffer for simplicity
