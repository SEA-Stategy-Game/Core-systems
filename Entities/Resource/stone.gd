class_name StoneResource
extends MapResource

func _ready() -> void:
    super()
    amount = 3
    total_time = 10.0
    current_time = total_time
    if bar:
        bar.max_value = total_time
        bar.value = current_time
    resource_name = "ressource_stone"

func on_finished_harvesting() -> void:
    Game.Stone += 1
    super.on_finished_harvesting()