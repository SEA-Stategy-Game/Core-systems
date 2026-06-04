extends Node

signal unit_created(unit: Node)
signal unit_destroyed(unit_id: int)

signal resource_created(resource: Node)
signal resource_destroyed(resource_id: int)

# Game room lifecycle signals
signal game_room_ready()
signal game_room_running()
signal game_room_ended(winner_local_id: int, reason: String)
signal game_room_crashed(reason: String)
