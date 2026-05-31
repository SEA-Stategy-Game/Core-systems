extends IStateSerializer

func _get_state_key() -> String:
	var game_id = OS.get_environment("GAME_ROOM_ID")
	if game_id == "": 
		game_id = "testgame"
		
	return "game:%s:state_snapshot" % game_id

func save_state(state: Dictionary, tree: SceneTree) -> bool:
	var json_string = JSON.stringify(state)
	var redis = RedisClient
	
	var state_key = _get_state_key()
	redis.set_value(state_key, json_string)
	
	if redis.has_method("expire"):
		var save_time_seconds = TickManager.get_auto_save_interval_seconds();
		var calculated_ttl = int(save_time_seconds * 5.0)
		var ttl = calculated_ttl if calculated_ttl > 10 else 10
		
		redis.expire(state_key, ttl) 
		
	RedisStateMirror.mirror_state()
		
	print("[TaskSerializer] State synced to Redis successfully.")
	return true
	
func load_state() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return {}
		
	var redis = RedisClient
		
	var snapshot_key = _get_state_key()
	var snapshot_json = ""
	
	# Support for Redis client get implementations (assuming synchronous or pre-cached)

	snapshot_json = redis.get_value(snapshot_key)
		
	if typeof(snapshot_json) == TYPE_STRING and snapshot_json != "":
		var parsed = JSON.parse_string(snapshot_json)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
			
	return {}
