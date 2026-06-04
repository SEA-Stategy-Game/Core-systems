extends Node

signal plan_notified(game_id: String, player_id: String, unit_ids: Array)

var game_id: String
var _redis: Object = null

func _ready() -> void:
	game_id = Game.game_room_id

	_redis = RedisClient
	var topic = "planning.%s.plan-updated" % game_id
	_redis.subscribe(topic, Callable(self, "_on_redis_message"))
	print("[REDIS_RECEIVER] Subscribed to %s" % topic)

func _on_redis_message(channel: String, message: String) -> void:
	var plan = JSON.parse_string(message)
	if typeof(plan) == TYPE_DICTIONARY:
		var p_id = str(plan.get("player_id", ""))
		var raw_u_ids = plan.get("unit_ids", [])
		var u_ids = []
		for id in raw_u_ids:
			u_ids.append(str(id))
		plan_notified.emit(game_id, p_id, u_ids)
	else:
		push_error("RedisNotificationReceiver: Invalid JSON plan payload from PubSub.")
