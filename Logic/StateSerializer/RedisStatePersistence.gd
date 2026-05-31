extends IStateSerializer

func save_state(state: Dictionary, tree: SceneTree) -> bool:
	var json_string = JSON.stringify(state)
	var redis = tree.root.get_node_or_null("RedisClient")
	
	if redis and redis.has_method("set_value"):
		var game_id = OS.get_environment("GAME_ROOM_ID")
		if game_id == "": 
			game_id = "testgame"
			
		var state_key = "game:%s:state_snapshot" % game_id
		redis.set_value(state_key, json_string)
		
		if redis.has_method("expire"):
			var ttl: int = 60
			var tm = tree.root.get_node_or_null("TickManager")
			if tm and tm.has_method("get_auto_save_interval_seconds"):
				var save_time_seconds = tm.get_auto_save_interval_seconds()
				var calculated_ttl = int(save_time_seconds * 2.0)
				ttl = calculated_ttl if calculated_ttl > 10 else 10
			redis.expire(state_key, ttl) 
			
		print("[TaskSerializer] State synced to Redis successfully.")
		return true
	
	else:
		print("not redis ");
	push_error("[TaskSerializer] Redis flag enabled but RedisClient is missing.")
	return false

func load_state() -> Dictionary:
	push_warning("[TaskSerializer] Redis load_state is not implemented synchronously.")
	return {}
