extends Node
class_name FogOfWar

enum FogState {
	UNKNOWN,
	EXPLORED,
	VISIBLE
}

signal tile_visibility_changed(player_id: int, tile: Vector2i, old_state: int, new_state: int)
signal player_fog_rebuilt(player_id: int)

@export var tile_size: int = 32
@export var map_width: int = 128
@export var map_height: int = 128
@export var default_unit_vision_tiles: int = 6
@export var default_building_vision_tiles: int = 8
@export var update_on_tick: bool = true

# player_id -> Dictionary[Vector2i, bool]
var _visible_by_player: Dictionary = {}
var _explored_by_player: Dictionary = {}

func _ready() -> void:
	if update_on_tick:
		var tick_manager = get_node_or_null("../TickManager")
		if tick_manager and tick_manager.has_signal("tick_processed"):
			if not tick_manager.tick_processed.is_connected(_on_tick_processed):
				tick_manager.tick_processed.connect(_on_tick_processed)

func _on_tick_processed(_count: int) -> void:
	rebuild_all_players()


func rebuild_all_players() -> void:
	var players := _collect_known_players()
	for pid in players:
		rebuild_player(pid)

func rebuild_player(player_id: int) -> void:
	_ensure_player(player_id)

	var old_visible: Dictionary = _visible_by_player[player_id]
	var old_states: Dictionary = _snapshot_states(player_id)
	var new_visible: Dictionary = {}

	for source in _get_vision_sources(player_id):
		var center_tile := world_to_tile(source.global_position)
		var radius := _get_vision_radius_tiles(source)
		_add_visible_circle(new_visible, center_tile, radius)

	_visible_by_player[player_id] = new_visible

	
	var explored: Dictionary = _explored_by_player[player_id]
	for tile in new_visible.keys():
		explored[tile] = true

	_emit_changed_tiles(player_id, old_states)
	player_fog_rebuilt.emit(player_id)

func clear_player(player_id: int) -> void:
	_visible_by_player.erase(player_id)
	_explored_by_player.erase(player_id)

func clear_all() -> void:
	_visible_by_player.clear()
	_explored_by_player.clear()




func get_fog_state(player_id: int, tile: Vector2i) -> int:
	_ensure_player(player_id)
	if _visible_by_player[player_id].has(tile):
		return FogState.VISIBLE
	if _explored_by_player[player_id].has(tile):
		return FogState.EXPLORED
	return FogState.UNKNOWN

func is_tile_visible(player_id: int, tile: Vector2i) -> bool:
	_ensure_player(player_id)
	return _visible_by_player[player_id].has(tile)

func is_tile_explored(player_id: int, tile: Vector2i) -> bool:
	_ensure_player(player_id)
	return _explored_by_player[player_id].has(tile)

func is_world_position_visible(player_id: int, world_position: Vector2) -> bool:
	return is_tile_visible(player_id, world_to_tile(world_position))

func is_world_position_explored(player_id: int, world_position: Vector2) -> bool:
	return is_tile_explored(player_id, world_to_tile(world_position))

func get_visible_tiles(player_id: int) -> Array[Vector2i]:
	_ensure_player(player_id)
	var result: Array[Vector2i] = []
	for tile in _visible_by_player[player_id].keys():
		result.append(tile)
	return result

func get_explored_tiles(player_id: int) -> Array[Vector2i]:
	_ensure_player(player_id)
	var result: Array[Vector2i] = []
	for tile in _explored_by_player[player_id].keys():
		result.append(tile)
	return result

func can_player_sense_node(player_id: int, node: Node) -> bool:
	if not node is Node2D:
		return false
	return is_world_position_visible(player_id, node.global_position)

func world_to_tile(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / tile_size), floori(world_position.y / tile_size))

func tile_to_world_center(tile: Vector2i) -> Vector2:
	return Vector2((tile.x + 0.5) * tile_size, (tile.y + 0.5) * tile_size)





func _ensure_player(player_id: int) -> void:
	if not _visible_by_player.has(player_id):
		_visible_by_player[player_id] = {}
	if not _explored_by_player.has(player_id):
		_explored_by_player[player_id] = {}

func _collect_known_players() -> Array[int]:
	var players: Array[int] = []
	for node in _get_all_player_owned_nodes():
		var pid := _get_player_id(node)
		if pid >= 0 and not players.has(pid):
			players.append(pid)
	return players

func _get_all_player_owned_nodes() -> Array[Node]:
	var result: Array[Node] = []
	for unit in get_tree().get_nodes_in_group("units"):
		result.append(unit)
	for building in get_tree().get_nodes_in_group("buildings"):
		result.append(building)

	# Your current SenseAPI also looks under World/Houses, so include that path.
	var houses = get_tree().get_root().get_node_or_null("World/Houses")
	if houses:
		for child in houses.get_children():
			if not result.has(child):
				result.append(child)
	return result

func _get_vision_sources(player_id: int) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node in _get_all_player_owned_nodes():
		if not node is Node2D:
			continue
		if _get_player_id(node) != player_id:
			continue
		if _is_dead(node):
			continue
		result.append(node)
	return result

func _get_player_id(node: Node) -> int:
	if "player_id" in node:
		return int(node.player_id)
	if node.has_method("get_player_id"):
		return int(node.get_player_id())
	return -1

func _is_dead(node: Node) -> bool:
	if "current_health" in node:
		return int(node.current_health) <= 0
	return false

func _get_vision_radius_tiles(source: Node) -> int:
	if "vision_range_tiles" in source:
		return max(0, int(source.vision_range_tiles))
	if source.is_in_group("buildings") or source.get_parent() != null and source.get_parent().name == "Houses":
		return default_building_vision_tiles
	return default_unit_vision_tiles

func _add_visible_circle(target: Dictionary, center: Vector2i, radius: int) -> void:
	var r2 := radius * radius
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var tile := Vector2i(x, y)
			if not _is_in_bounds(tile):
				continue
			var dx := x - center.x
			var dy := y - center.y
			if dx * dx + dy * dy <= r2:
				target[tile] = true

func _is_in_bounds(tile: Vector2i) -> bool:
	if map_width <= 0 or map_height <= 0:
		return true
	return tile.x >= 0 and tile.y >= 0 and tile.x < map_width and tile.y < map_height

func _snapshot_states(player_id: int) -> Dictionary:
	var states: Dictionary = {}
	var visible: Dictionary = _visible_by_player[player_id]
	var explored: Dictionary = _explored_by_player[player_id]

	for tile in explored.keys():
		states[tile] = FogState.EXPLORED
	for tile in visible.keys():
		states[tile] = FogState.VISIBLE
	return states

func _emit_changed_tiles(player_id: int, old_states: Dictionary) -> void:
	var new_states := _snapshot_states(player_id)
	var all_tiles: Dictionary = {}

	for tile in old_states.keys():
		all_tiles[tile] = true
	for tile in new_states.keys():
		all_tiles[tile] = true

	for tile in all_tiles.keys():
		var old_state: int = int(old_states.get(tile, FogState.UNKNOWN))
		var new_state: int = int(new_states.get(tile, FogState.UNKNOWN))
		if old_state != new_state:
			tile_visibility_changed.emit(player_id, tile, old_state, new_state)
