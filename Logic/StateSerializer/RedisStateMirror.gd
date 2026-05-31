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


func mirror_state() -> void:
	if not _redis: return
	
	var sense_api = get_node_or_null("/root/SenseAPI")
	if not sense_api:
		push_error("[STATE_MIRROR] SenseAPI not found. Cannot mirror state.")
		return
		
	var units_key = "game:%s:units" % game_id
	var resources_key = "game:%s:resources" % game_id
	
	# Retrieve the definitive Source of Truth from the Core system
	var units_data = []
	if sense_api.has_method("get_all_units"):
		units_data = sense_api.get_all_units()
		
	var resources_data = []
	if sense_api.has_method("get_all_resources"):
		resources_data = sense_api.get_all_resources()
	elif sense_api.has_method("get_world_resources"):
		resources_data = sense_api.get_world_resources()
	
	# Forcefully overwrite the existing Redis state to resolve any inconsistencies
	if _redis.has_method("set_value"):
		_redis.set_value(units_key, JSON.stringify(units_data))
		_redis.set_value(resources_key, JSON.stringify(resources_data))
	elif _redis.has_method("set"):
		_redis.set(units_key, JSON.stringify(units_data))
		_redis.set(resources_key, JSON.stringify(resources_data))
		
	print("[STATE_MIRROR] State overridden and mirrored for game_id: ", game_id)
