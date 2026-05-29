extends Node

# Persistent mapping: { uuid: String -> local_id: int }
var player_uuid_to_local_id = {}

# Current session data: { peer_id: int -> { "local_id": int, "player_uuid": String, ... } }
var connected_players = {}

# Counter for assigning new local IDs
var _next_local_id = 0

## Returns the existing local_id for a uuid, or creates a new one if it's new.
func get_or_create_local_id(uuid: String) -> int:
	if player_uuid_to_local_id.has(uuid):
		return player_uuid_to_local_id[uuid]
	
	var new_id = _next_local_id
	player_uuid_to_local_id[uuid] = new_id
	_next_local_id += 1
	return new_id



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
