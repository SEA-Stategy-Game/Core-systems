## IUnitAction.gd
## -----------------------------------------------------------------------
## Interface contract for all unit actions.  GDScript does not have formal
## interfaces; this RefCounted class acts as a compile-time reference AND
## provides the duck-typing validator `is_implemented_by()`.
##
## Every concrete action must expose the four methods below.
## -----------------------------------------------------------------------
extends RefCounted
class_name IUnitAction

# ---- Action lifecycle states ----
enum ActionState {
	PENDING,    ## Queued but not yet started
	RUNNING,    ## Pre-flight or execution in progress
	COMPLETED,  ## Finished successfully
	FAILED      ## Could not complete (path blocked, target removed, etc.)
}

# -----------------------------------------------------------------
# Contract methods -- override in every concrete implementation.
# -----------------------------------------------------------------

## Called once when the action is popped from the CommandQueue.
## `unit` is the acting CharacterBody2D, `target` is action-specific.
func start(_unit: CharacterBody2D, _target: Node2D) -> void:
	push_error("IUnitAction.start() is abstract -- override in subclass.")

## Called every simulation tick while the action is RUNNING.
## Return the current ActionState so the CommandQueue knows when to advance.
func tick(_unit: CharacterBody2D, _delta: float) -> int:
	push_error("IUnitAction.tick() is abstract -- override in subclass.")
	return ActionState.FAILED

## Request a graceful cancellation (e.g., AI re-plans mid-action).
func cancel(_unit: CharacterBody2D) -> void:
	push_error("IUnitAction.cancel() is abstract -- override in subclass.")

## Serialise the action to a Dictionary for persistence.
func serialize() -> Dictionary:
	push_error("IUnitAction.serialize() is abstract -- override in subclass.")
	return {}

# -----------------------------------------------------------------
# Duck-typing validator
# -----------------------------------------------------------------
static func is_implemented_by(obj: Variant) -> bool:
	if obj == null:
		return false
	return (
		obj.has_method("start")
		and obj.has_method("tick")
		and obj.has_method("cancel")
		and obj.has_method("serialize")
	)
