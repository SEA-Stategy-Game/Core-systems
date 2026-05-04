# Entities/Map/MapManager.gd
extends Node
class_name MapManager

@export var tile_size: int = 32
var map_node: Node = null

func world_to_grid(world_pos: Vector2) -> Vector2i:
    return Vector2i(int(floor(world_pos.x / tile_size)), int(floor(world_pos.y / tile_size)))

func get_tile_at_world_pos(world_pos: Vector2) -> Variant:
    if map_node == null:
        return null
    var g = world_to_grid(world_pos)
    if map_node.has_method("get_tile"):
        return map_node.get_tile(g.x, g.y)
    if map_node.has_method("getTile"):
        return map_node.getTile(g.x, g.y)
    return null