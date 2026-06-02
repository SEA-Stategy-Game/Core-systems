## RedisStateMirror.gd (Autoload Singleton)
## -----------------------------------------------------------------------
## Handles "Fire-and-Forget" incremental updates (SADD/SREM) to Redis.
## The full state snapshot is handled separately by TaskSerializer & TickManager.
## -----------------------------------------------------------------------
extends Node

var game_id: String
var _redis: Object = null 

func _ready() -> void:
	var redis_flag = OS.get_environment("USE_REDIS")
	if redis_flag != "true" and redis_flag != "1":
		queue_free()
		return

	game_id = Game.game_room_id
	_redis = RedisClient

	GlobalSignals.unit_created.connect(_on_unit_created)
	GlobalSignals.unit_destroyed.connect(_on_unit_destroyed)
	GlobalSignals.resource_created.connect(_on_resource_created)
	GlobalSignals.resource_destroyed.connect(_on_resource_destroyed)

func _on_unit_created(unit: Node) -> void:
	var unit_id = unit.get("entity_id")
	if unit_id == null:
		unit_id = -1
	var key = "game:%s:units" % game_id
	_redis.sadd(key, str(unit_id))
	print("[STATE_MIRROR] Added unit ", unit_id, " to Redis set via signal.")

func _on_unit_destroyed(unit_id: int) -> void:
	var key = "game:%s:units" % game_id
	_redis.srem(key, str(unit_id))
	print("[STATE_MIRROR] Removed unit ", unit_id, " from Redis set via signal.")

func _on_resource_created(resource: Node) -> void:
	var resource_id = resource.get("entity_id")
	if resource_id == null:
		resource_id = -1
	var key = "game:%s:resources" % game_id
	_redis.sadd(key, str(resource_id))
	print("[STATE_MIRROR] Added resource ", resource_id, " to Redis set via signal.")

func _on_resource_destroyed(resource_id: int) -> void:
	var key = "game:%s:resources" % game_id
	_redis.srem(key, str(resource_id))
	print("[STATE_MIRROR] Removed resource ", resource_id, " from Redis set via signal.")



func mirror_state() -> void:
	var sense_api = ActionGateway.sense()

	if not sense_api:
		push_error("[STATE_MIRROR] SenseAPI not found. Cannot mirror state.")
		return
		
	var units_key = "game:%s:units" % game_id
	var resources_key = "game:%s:resources" % game_id
	
	# Retrieve the definitive Source of Truth from the Core system
	var units_data = []
	units_data = sense_api.get_all_units()
		
	var resources_data = []
	resources_data = sense_api.get_all_resources()
	resources_data = sense_api.get_world_resources()
	
	var u_ids = []
	for unit in units_data:
		var uid = unit.get("id", unit.get("entity_id", null))
		if uid != null:
			u_ids.append(str(uid))
	_redis.del_key(units_key)
	if not u_ids.is_empty():
		_redis.sadd_array(units_key, u_ids)
		
	var r_ids = []
	for res in resources_data:
		var rid = res.get("id", res.get("entity_id", null))
		if rid != null:
			r_ids.append(str(rid))
	_redis.del_key(resources_key)
	if not r_ids.is_empty():
		_redis.sadd_array(resources_key, r_ids)
		
	print("[STATE_MIRROR] State overridden and mirrored for game_id: ", game_id)
