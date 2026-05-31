extends Node

signal plan_notified(game_id: String, player_id: String, unit_ids: Array)

var game_id: String = "testgame"
var _redis: Object = null

func _ready() -> void:
	game_id = OS.get_environment("GAME_ROOM_ID")
	if game_id == "":
		game_id = "testgame"

	if has_node("/root/RedisClient"):
		_redis = get_node("/root/RedisClient")
		var topic = "planning.%s.plan-updated" % game_id
		_redis.subscribe(topic, Callable(self, "_on_redis_message"))
		print("[REDIS_RECEIVER] Subscribed to %s" % topic)
	else:
		push_error("[REDIS_RECEIVER] RedisClient not found!")

func _on_redis_message(channel: String, message: String) -> void:
	var plan = JSON.parse_string(message)
	if typeof(plan) == TYPE_DICTIONARY:
		var p_id = str(plan.get("player_id", ""))
		var u_ids = plan.get("unit_ids", [])
		plan_notified.emit(game_id, p_id, u_ids)
	else:
		push_error("RedisNotificationReceiver: Invalid JSON plan payload from PubSub.")
