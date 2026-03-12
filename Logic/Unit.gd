extends Entity
class_name Unit

@export var move_speed: float = 150.0

# "Classless" system Roles are defined by equipment
var equipment: Array[String] = []

# Anti-APM measures aka sets a timer for plan input
var can_accept_plan: bool = true
@onready var cooldown_timer: Timer = Timer.new()

func _ready():
	super._ready() # Calls Entity._ready()
	setup_cooldown()

func setup_cooldown():
	cooldown_timer.wait_time = 2.0 # 2-second forced delay between plans
	cooldown_timer.one_shot = true
	cooldown_timer.timeout.connect(_on_cooldown_finished)
	add_child(cooldown_timer)

func _on_cooldown_finished():
	can_accept_plan = true

# The "Execute" part of the Plan-Execute loop
func receive_plan(target_position: Vector2):
	if not can_accept_plan:
		print("Plan rejected: Unit ", entity_id, " is on cooldown.")
		return

	print("Unit ", entity_id, " moving to ", target_position)
	# Pathfinding logic goes here ...
	
	can_accept_plan = false
	cooldown_timer.start()

func equip_item(item_name: String):
	equipment.append(item_name)
	print("Unit ", entity_id, " updated role with: ", item_name)
