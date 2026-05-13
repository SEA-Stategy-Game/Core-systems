extends GutTest

## -----------------------------------------------------------------------
## Unit tests for WinConditionChecker.gd
## -----------------------------------------------------------------------
## Two win paths: economy (stockpile reaches RESOURCE_WIN_THRESHOLD) and
## combat (last player with assets, only once the match has started).
## A fresh checker instance is used per test; Game.is_headless is forced
## so no WinPopup scene is spawned.
## -----------------------------------------------------------------------

const CheckerScript = preload("res://Logic/WinConditionChecker.gd")

## Minimal asset (counts as "this player is still alive").
class FakeAsset extends Node2D:
	var player_id: int = 0

var checker
var _orig_headless: bool

func before_each() -> void:
	_reset_game_state()
	_orig_headless = Game.is_headless
	Game.is_headless = true

	checker = CheckerScript.new()
	add_child_autofree(checker)

func after_each() -> void:
	Game.is_headless = _orig_headless
	_reset_game_state()
	checker = null

func _reset_game_state() -> void:
	Game.player_resources.clear()
	Game.Wood = 0
	Game.Stone = 0
	Game.game_over = false
	Game.player_count = 1

func _make_asset(pid: int) -> FakeAsset:
	var asset := FakeAsset.new()
	asset.player_id = pid
	asset.add_to_group("units")
	add_child_autofree(asset)
	return asset

# ----------------
# no-win baseline
# ----------------
func test_no_winner_with_empty_stockpiles_and_no_assets() -> void:
	var won := checker.check_now()

	assert_false(won)
	assert_false(Game.game_over)

func test_no_check_runs_when_player_count_is_zero() -> void:
	Game.player_count = 0
	Game.add_resource(0, "wood", Game.RESOURCE_WIN_THRESHOLD)

	assert_false(checker.check_now())

func test_no_check_runs_after_game_over() -> void:
	Game.game_over = true
	Game.add_resource(0, "wood", Game.RESOURCE_WIN_THRESHOLD)

	assert_false(checker.check_now())

# ----------------
# economy win
# ----------------
func test_wood_at_threshold_wins_via_economy() -> void:
	watch_signals(GlobalSignals)
	Game.add_resource(0, "wood", Game.RESOURCE_WIN_THRESHOLD)

	var won := checker.check_now()

	assert_true(won)
	assert_true(Game.game_over)
	assert_signal_emitted_with_parameters(GlobalSignals, "game_room_ended", [0, "economy"])

func test_stone_at_threshold_wins_via_economy() -> void:
	Game.add_resource(0, "stone", Game.RESOURCE_WIN_THRESHOLD)

	assert_true(checker.check_now())

func test_one_below_threshold_does_not_win() -> void:
	Game.add_resource(0, "wood", Game.RESOURCE_WIN_THRESHOLD - 1)
	Game.add_resource(0, "stone", Game.RESOURCE_WIN_THRESHOLD - 1)

	assert_false(checker.check_now())
	assert_false(Game.game_over)

func test_economy_win_credits_the_correct_player() -> void:
	watch_signals(GlobalSignals)
	Game.player_count = 2
	Game.add_resource(1, "stone", Game.RESOURCE_WIN_THRESHOLD)

	assert_true(checker.check_now())
	assert_signal_emitted_with_parameters(GlobalSignals, "game_room_ended", [1, "economy"])

# ----------------
# combat win
# ----------------
func test_solo_player_cannot_win_via_combat() -> void:
	Game.player_count = 1
	_make_asset(0)

	assert_false(checker.check_now())

func test_combat_win_not_declared_before_match_started() -> void:
	Game.player_count = 2
	_make_asset(0)  # player 1 never had assets -> match never started

	assert_false(checker.check_now())

func test_last_player_with_assets_wins_via_combat() -> void:
	watch_signals(GlobalSignals)
	Game.player_count = 2
	_make_asset(0)
	var enemy_asset := _make_asset(1)

	# Both alive: the match counts as started, nobody wins yet.
	assert_false(checker.check_now())

	# Player 1 loses their last asset.
	enemy_asset.free()

	var won := checker.check_now()

	assert_true(won)
	assert_true(Game.game_over)
	assert_signal_emitted_with_parameters(GlobalSignals, "game_room_ended", [0, "combat"])

func test_combat_win_considers_buildings_as_assets() -> void:
	Game.player_count = 2
	_make_asset(0)
	var enemy_unit := _make_asset(1)
	var enemy_barracks := FakeAsset.new()
	enemy_barracks.player_id = 1
	enemy_barracks.add_to_group("barracks")
	add_child_autofree(enemy_barracks)

	assert_false(checker.check_now())  # match starts
	enemy_unit.free()

	# Player 1 still owns a barracks -> no combat win yet.
	assert_false(checker.check_now())
	assert_false(Game.game_over)
