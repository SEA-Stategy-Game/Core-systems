extends Node
class_name DeterminismVerifier

signal verification_passed(tick: int)
signal verification_failed(tick: int, divergence: Dictionary)
signal state_snapshot_collected(player_id: int, snapshot: Dictionary)

@export var check_interval_ms: int = 1000
@export var detailed_logging: bool = false

var instances: Array = []
var tick_manager: TickManager
var last_check_tick: int = -1
var verification_log: Array = []
var state_divergence_log: Array = []

func initialize(p_instances: Array) -> void:
	instances = p_instances
	tick_manager = TickManager
	_start_verification_loop()

func _start_verification_loop() -> void:
	while true:
		await get_tree().create_timer(maxf(float(check_interval_ms) / 1000.0, 0.05)).timeout
		if instances.is_empty():
			continue
		verify_current_state()

func verify_current_state() -> bool:
	var current_tick := tick_manager.current_tick if tick_manager != null else -1
	if current_tick == last_check_tick:
		return true
	last_check_tick = current_tick

	var snapshots := _collect_snapshots()
	if snapshots.is_empty():
		return true

	var reference_snapshot = null
	var all_match := true

	for player_id in snapshots:
		var snapshot = snapshots[player_id]
		if reference_snapshot == null:
			reference_snapshot = snapshot
			continue
		if not _snapshots_match(reference_snapshot, snapshot):
			all_match = false
			_log_divergence(current_tick, reference_snapshot, snapshot)
			break

	if all_match:
		verification_log.append({"tick": current_tick, "ok": true})
		verification_passed.emit(current_tick)
		if detailed_logging:
			print("[VERIFIER] Tick %d: in sync" % current_tick)
	else:
		var divergence := _calculate_divergence(snapshots)
		state_divergence_log.append(divergence)
		verification_failed.emit(current_tick, divergence)
		print("[VERIFIER] Tick %d: desynchronization detected" % current_tick)

	return all_match

func _collect_snapshots() -> Dictionary:
	var snapshots := {}
	for inst in instances:
		if inst == null or not inst.has_method("is_initialized"):
			continue
		if not inst.is_initialized():
			continue

		var snapshot: Dictionary = {}
		if inst.has_method("request_snapshot"):
			snapshot = inst.request_snapshot()
		elif inst.has_method("get_state_snapshot"):
			snapshot = inst.get_state_snapshot()
		elif inst.has_method("get_debug_info"):
			snapshot = inst.get_debug_info()

		if snapshot.is_empty():
			continue

		snapshots[inst.get_player_id() if inst.has_method("get_player_id") else snapshots.size()] = snapshot
		state_snapshot_collected.emit(inst.get_player_id() if inst.has_method("get_player_id") else snapshots.size(), snapshot)

	return snapshots

func _snapshots_match(snap1: Dictionary, snap2: Dictionary) -> bool:
	if snap1.get("state_hash") != snap2.get("state_hash"):
		return false
	if snap1.get("unit_count") != snap2.get("unit_count"):
		return false
	if snap1.get("resource_count") != snap2.get("resource_count"):
		return false
	if snap1.get("building_count") != snap2.get("building_count"):
		return false
	return true

func _calculate_divergence(snapshots: Dictionary) -> Dictionary:
	var divergence := {
		"tick": tick_manager.current_tick if tick_manager != null else -1,
		"affected_players": snapshots.keys(),
		"divergence_type": "STATE_HASH_MISMATCH"
	}
	if snapshots.size() >= 2:
		var values := snapshots.values()
		divergence["summary"] = "Hash mismatch: %s vs %s" % [values[0].get("state_hash", "n/a"), values[1].get("state_hash", "n/a")]
	return divergence

func _log_divergence(tick: int, snap1: Dictionary, snap2: Dictionary) -> void:
	state_divergence_log.append({
		"tick": tick,
		"snapshot_a": snap1,
		"snapshot_b": snap2,
		"summary": "Mismatch at tick %d" % tick
	})

func get_status_report() -> Dictionary:
	var total_checks := verification_log.size() + state_divergence_log.size()
	var success_rate := 0.0
	if total_checks > 0:
		success_rate = float(verification_log.size()) / float(total_checks) * 100.0
	return {
		"total_verifications": total_checks,
		"passed": verification_log.size(),
		"failed": state_divergence_log.size(),
		"success_rate_percent": success_rate,
		"last_check_tick": last_check_tick
	}
