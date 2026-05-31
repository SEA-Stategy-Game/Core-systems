extends IStateSerializer

func _get_state_key() -> String:
	var game_id = OS.get_environment("GAME_ROOM_ID")
	if game_id == "": 
		game_id = "testgame"
		
	return "game:%s:state_snapshot" % game_id

func save_state(state: Dictionary, tree: SceneTree) -> bool:
	var json_string = JSON.stringify(state)
	var redis = tree.root.get_node_or_null("RedisClient")
	
	if redis and redis.has_method("set_value"):
		var state_key = _get_state_key()
		redis.set_value(state_key, json_string)
		
		if redis.has_method("expire"):
			var ttl: int = 60
			var tm = tree.root.get_node_or_null("TickManager")
			if tm and tm.has_method("get_auto_save_interval_seconds"):
				var save_time_seconds = tm.get_auto_save_interval_seconds()
				var calculated_ttl = int(save_time_seconds * 2.0)
				ttl = calculated_ttl if calculated_ttl > 10 else 10
			redis.expire(state_key, ttl) 
			
		var state_mirror = tree.root.get_node_or_null("RedisStateMirror")
		if state_mirror and state_mirror.has_method("mirror_state"):
			state_mirror.mirror_state()
			
		print("[TaskSerializer] State synced to Redis successfully.")
		return true
	
	else:
		print("not redis ");
	push_error("[TaskSerializer] Redis flag enabled but RedisClient is missing.")
	return false

func load_state() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return {}
		
	var redis = tree.root.get_node_or_null("RedisClient")
	if not redis:
		return {}
		
	var snapshot_key = _get_state_key()
	var snapshot_json = ""
	
	# Support for Redis client get implementations (assuming synchronous or pre-cached)
	if redis.has_method("get_value"):
		snapshot_json = redis.get_value(snapshot_key)
	elif redis.has_method("get"):
		snapshot_json = redis.get(snapshot_key)
		
	if typeof(snapshot_json) == TYPE_STRING and snapshot_json != "":
		var parsed = JSON.parse_string(snapshot_json)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
			
	return {}
