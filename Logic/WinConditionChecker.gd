extends Node

## -----------------------------------------------------------------------
## WinConditionChecker -- autoload.
##
## Two ways to win:
##   1. Economy   -- a player's stockpile contains >= RESOURCE_WIN_THRESHOLD
##                   of one resource (wood OR stone).
##   2. Combat    -- only one player still has any units OR barracks alive.
##                   In a 1-player match this is skipped (you cannot beat
##                   "yourself" in combat), so solo players win only via
##                   the economy condition.
##
## A check runs every TickManager tick and also on a built-in 1 Hz timer,
## so it works regardless of whether the TickManager is hooked up.
## -----------------------------------------------------------------------

const WIN_POPUP_SCENE: PackedScene = preload("res://UI/WinPopup.tscn")

var _check_timer: Timer
var _match_started: bool = false

func _ready() -> void:
	_check_timer = Timer.new()
	_check_timer.wait_time = 1.0
	_check_timer.autostart = true
	_check_timer.timeout.connect(check_now)
	add_child(_check_timer)

	# Also hook the TickManager when it becomes available so we sample on
	# every simulation tick.
	call_deferred("_try_connect_tick_manager")

func _try_connect_tick_manager() -> void:
	var tm = get_node_or_null("/root/TickManager")
	if tm and tm.has_signal("tick_processed"):
		if not tm.tick_processed.is_connected(_on_tick):
			tm.tick_processed.connect(_on_tick)

func _on_tick(_count: int) -> void:
	check_now()

# ---------------------------------------------------------------
#  Public: forces an immediate check.  Returns true if a winner was found.
# ---------------------------------------------------------------
func check_now() -> bool:
	if Game.game_over:
		return false
	if Game.player_count <= 0:
		return false

	# ----- Economy win -----
	for pid in range(Game.player_count):
		if Game.get_player_wood(pid) >= Game.RESOURCE_WIN_THRESHOLD:
			return _declare_winner(pid, "economy")
		if Game.get_player_stone(pid) >= Game.RESOURCE_WIN_THRESHOLD:
			return _declare_winner(pid, "economy")

	# ----- Combat win (only meaningful for >= 2 players) -----
	if Game.player_count >= 2:
		var alive: Array = []
		for pid in range(Game.player_count):
			if _player_has_assets(pid):
				alive.append(pid)
		# Need at least 2 alive for the "last man standing" check to be valid;
		# otherwise the match has not really started yet.
		if alive.size() == 1 and _match_started:
			return _declare_winner(alive[0], "combat")
		if alive.size() >= 2:
			_match_started = true

	return false

func _player_has_assets(pid: int) -> bool:
	for u in get_tree().get_nodes_in_group("units"):
		if "player_id" in u and u.player_id == pid:
			return true
	for b in get_tree().get_nodes_in_group("buildings"):
		if "player_id" in b and b.player_id == pid:
			return true
	for b in get_tree().get_nodes_in_group("barracks"):
		if "player_id" in b and b.player_id == pid:
			return true
	return false

func _declare_winner(pid: int, reason: String) -> bool:
	Game.game_over = true
	print("[GAME_OVER] Player ", pid, " wins via ", reason, ".")
	GlobalSignals.game_room_ended.emit(pid, reason)
	if Game.is_headless:
		return true
	var popup = WIN_POPUP_SCENE.instantiate()
	popup.winning_player_id = pid
	popup.reason = reason
	var world = get_tree().get_root().get_node_or_null("World")
	if world:
		world.add_child(popup)
	else:
		get_tree().get_root().add_child(popup)
	return true
