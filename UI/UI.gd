extends CanvasLayer

@onready var label: Label = $Label

func _process(_delta: float) -> void:
	var lines: Array[String] = []
	var count = max(1, Game.player_count)
	for pid in range(count):
		lines.append("P%d  Wood %d  Stone %d" % [
			pid, Game.get_player_wood(pid), Game.get_player_stone(pid)
		])
	label.text = "\n".join(lines)
