## RedisStateMirror.gd (Autoload Singleton)
## -----------------------------------------------------------------------
## Handles "Fire-and-Forget" incremental updates (SADD/SREM) to Redis.
## The full state snapshot is handled separately by TaskSerializer & TickManager.
## -----------------------------------------------------------------------
extends Node

var game_id: String = "testgame"
var _redis: Object = null 

func _ready() -> void:
	var use_redis = "true"
	if use_redis != "true" and use_redis != "1":
		queue_free()
		return
		
	game_id = OS.get_environment("GAME_ROOM_ID")
	if game_id == "":
		game_id = "testgame"

	if has_node("/root/RedisClient"):
		_redis = get_node("/root/RedisClient")

# --- Incremental Updates (Fire + Forget) ---
func add_unit(unit_id: int) -> void:
	if _redis and _redis.has_method("sadd"):
		var key = "game:%s:units" % game_id
		_redis.sadd(key, str(unit_id))
		print("[STATE_MIRROR] Added unit ", unit_id, " to Redis.")

func remove_unit(unit_id: int) -> void:
	if _redis and _redis.has_method("srem"):
		var key = "game:%s:units" % game_id
		_redis.srem(key, str(unit_id))
		print("[STATE_MIRROR] Removed unit ", unit_id, " from Redis.")

func add_resource(resource_id: int) -> void:
	if _redis and _redis.has_method("sadd"):
		var key = "game:%s:resources" % game_id
		_redis.sadd(key, str(resource_id))
		print("[STATE_MIRROR] Added resource ", resource_id, " to Redis.")

func remove_resource(resource_id: int) -> void:
	if _redis and _redis.has_method("srem"):
		var key = "game:%s:resources" % game_id
		_redis.srem(key, str(resource_id))
		print("[STATE_MIRROR] Removed resource ", resource_id, " from Redis.")
