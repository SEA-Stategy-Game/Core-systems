extends GutTest

## -----------------------------------------------------------------------
## Unit tests for the BehaviorPlanner rule language (_eval_predicate)
## -----------------------------------------------------------------------
## The AI team's reactive plans are (when, do, priority) rules whose
## "when" predicates are small expressions.  These tests evaluate the
## parser against a hand-built context, fully isolated from the scene.
## -----------------------------------------------------------------------

const PlannerScript = preload("res://Logic/BehaviorPlanner.gd")

var planner

func before_each() -> void:
	planner = autofree(PlannerScript.new())

func after_each() -> void:
	planner = null

func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var ctx := {
		"wood": 10,
		"stone": 5,
		"hp": 50,
		"max_hp": 100,
		"hp_pct": 0.5,
		"is_idle": true,
		"enemy_dist": 200.0,
		"position": Vector2.ZERO,
		"pid": 0,
	}
	ctx.merge(overrides, true)
	return ctx

# ----------------
# constant rules
# ----------------
func test_true_and_always_always_fire() -> void:
	assert_true(planner._eval_predicate("true", null, _ctx()))
	assert_true(planner._eval_predicate("always", null, _ctx()))

func test_empty_predicate_never_fires() -> void:
	assert_false(planner._eval_predicate("", null, _ctx()))

# ----------------
# idle / busy
# ----------------
func test_idle_fires_only_when_unit_is_idle() -> void:
	assert_true(planner._eval_predicate("idle", null, _ctx({"is_idle": true})))
	assert_false(planner._eval_predicate("idle", null, _ctx({"is_idle": false})))

func test_busy_is_the_inverse_of_idle() -> void:
	assert_true(planner._eval_predicate("busy", null, _ctx({"is_idle": false})))
	assert_false(planner._eval_predicate("busy", null, _ctx({"is_idle": true})))

# ----------------
# stockpile comparisons
# ----------------
func test_wood_greater_than_stone_comparison() -> void:
	assert_true(planner._eval_predicate("wood > stone", null, _ctx({"wood": 6, "stone": 2})))
	assert_false(planner._eval_predicate("wood > stone", null, _ctx({"wood": 2, "stone": 6})))

func test_stone_greater_than_wood_comparison() -> void:
	assert_true(planner._eval_predicate("stone > wood", null, _ctx({"wood": 2, "stone": 6})))

func test_wood_threshold_comparisons() -> void:
	assert_true(planner._eval_predicate("wood >= 10", null, _ctx({"wood": 10})))
	assert_false(planner._eval_predicate("wood >= 11", null, _ctx({"wood": 10})))
	assert_true(planner._eval_predicate("wood < 11", null, _ctx({"wood": 10})))
	assert_false(planner._eval_predicate("wood < 10", null, _ctx({"wood": 10})))

func test_stone_equality_comparison() -> void:
	assert_true(planner._eval_predicate("stone == 5", null, _ctx({"stone": 5})))
	assert_false(planner._eval_predicate("stone == 4", null, _ctx({"stone": 5})))

func test_hp_threshold_comparison() -> void:
	assert_true(planner._eval_predicate("hp <= 50", null, _ctx({"hp": 50})))
	assert_false(planner._eval_predicate("hp <= 49", null, _ctx({"hp": 50})))

# ----------------
# proximity rules
# ----------------
func test_enemy_within_compares_against_nearest_hostile_distance() -> void:
	assert_true(planner._eval_predicate("enemy_within(250)", null, _ctx({"enemy_dist": 200.0})))
	assert_false(planner._eval_predicate("enemy_within(100)", null, _ctx({"enemy_dist": 200.0})))

func test_no_enemy_within_is_the_inverse() -> void:
	assert_true(planner._eval_predicate("no_enemy_within(100)", null, _ctx({"enemy_dist": 200.0})))
	assert_false(planner._eval_predicate("no_enemy_within(250)", null, _ctx({"enemy_dist": 200.0})))

func test_enemy_within_with_no_enemies_never_fires() -> void:
	assert_false(planner._eval_predicate("enemy_within(99999)", null, _ctx({"enemy_dist": INF})))

# ----------------
# health rules
# ----------------
func test_hp_below_fires_under_the_fraction() -> void:
	assert_true(planner._eval_predicate("hp_below(0.6)", null, _ctx({"hp_pct": 0.5})))
	assert_false(planner._eval_predicate("hp_below(0.4)", null, _ctx({"hp_pct": 0.5})))

func test_hp_above_fires_over_the_fraction() -> void:
	assert_true(planner._eval_predicate("hp_above(0.4)", null, _ctx({"hp_pct": 0.5})))
	assert_false(planner._eval_predicate("hp_above(0.6)", null, _ctx({"hp_pct": 0.5})))

# ----------------
# malformed input
# ----------------
func test_unknown_function_never_fires() -> void:
	assert_false(planner._eval_predicate("teleport_home(3)", null, _ctx()))

func test_unknown_comparison_field_never_fires() -> void:
	assert_false(planner._eval_predicate("gold >= 5", null, _ctx()))

func test_garbage_input_never_fires() -> void:
	assert_false(planner._eval_predicate("certainly not a rule", null, _ctx()))
