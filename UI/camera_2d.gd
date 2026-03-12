extends Camera2D

# Camera Control
@export var CamSpeed = 20.0
@export var ZoomSpeed = 20.0
@export var ZoomMargin = 0.1
@export var ZoomMin = 0.5
@export var ZoomMax = 3.0

var ZoomFactor = 1.0
var ZoomPos = Vector2()
var Zooming = false


var mousePos = Vector2()

var mousePosGlobal = Vector2()
var start = Vector2()
var startV = Vector2()
var end = Vector2()
var endV = Vector2()
var isDragging = false
signal area_selected(object)
signal start_move_selection(object)
@onready var box = get_parent().get_node("UI/Panel") if get_parent().has_node("UI/Panel") else get_parent().get_node("Panel")

func _ready():
	pass
	

# logic for "selecting" units with mouse
# maybe disable this if client wants
func _process(delta):
	var inputX = int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left"))
	var inputY = int(Input.is_action_pressed("ui_down")) - int(Input.is_action_pressed("ui_up"))
	
	position.x = lerp(position.x, position.x + inputX * CamSpeed * zoom.x, CamSpeed * delta)
	position.y = lerp(position.y, position.y + inputY * CamSpeed * zoom.y, CamSpeed * delta)
	
	zoom.x = lerp(zoom.x, zoom.x * ZoomFactor, ZoomSpeed * delta)
	zoom.y = lerp(zoom.y, zoom.y * ZoomFactor, ZoomSpeed * delta)
	
	zoom.x = clamp(zoom.x, ZoomMin, ZoomMax)
	zoom.y = clamp(zoom.y, ZoomMin, ZoomMax)
	
	if not Zooming:
		ZoomFactor = 1.0
	
	if Input.is_action_just_pressed("LeftClick"):
		start = mousePosGlobal
		startV = mousePos
		isDragging = true

	# Updating the drawing of the retangle 
	if isDragging:
		end = mousePosGlobal
		endV = mousePos
		draw_area()

	if Input.is_action_just_released("LeftClick"):
		if startV.distance_to(mousePos) > 20:
			end = mousePosGlobal
			endV = mousePos
			isDragging = false
			draw_area(false)
			emit_signal("area_selected", self)
		else:
			end = start
			isDragging = false
			draw_area(false)

# function for tracking mouse
func _input(event):
	if abs(ZoomPos.x - get_global_mouse_position().x) > ZoomMargin:
		ZoomFactor = 1.0
	if abs(ZoomPos.y - get_global_mouse_position().y) > ZoomMargin:
		ZoomFactor = 1.0
	# function for zooming with mouse
	if event is InputEventMouseButton:
		if event.is_pressed():
			Zooming = true
			if event.is_action("WheelDown"):
				ZoomFactor -= 0.01 * ZoomSpeed
				ZoomPos = get_global_mouse_position()
			if event.is_action("WheelUp"):
				ZoomFactor += 0.01 * ZoomSpeed
				ZoomPos = get_global_mouse_position()
		else:
			Zooming = false
		
	if event is InputEventMouse:
		mousePos = event.position
		mousePosGlobal = get_global_mouse_position()

# function for drawing a retangle 
func draw_area(s=true):
	box.size = Vector2(abs(startV.x - endV.x), abs(startV.y - endV.y))
	var pos = Vector2()
	pos.x = min(startV.x, endV.x)
	pos.y = min(startV.y, endV.y)
	box.position = pos
	# sets the drawn retangle to false so it dissapears on screen
	box.size *= int(s)
