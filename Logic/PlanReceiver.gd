## PlanReceiver.gd — Autoload singleton
## Modtager plan-notifikationer fra Planning, henter UnitPlans og driver
## sekventiel, loopende plan-eksekvering for hver unit via ActionGateway.
extends Node

const LISTEN_PORT  = 8085
const PLANNING_URL = "http://127.0.0.1:5020"

## unit_id (String) → { "steps": Array, "index": int }
var _store: Dictionary = {}

var _server: TCPServer = TCPServer.new()

# ----------------------------------------------------------------
# Lifecycle
# ----------------------------------------------------------------

func _ready() -> void:
	if _server.listen(LISTEN_PORT, "127.0.0.1") != OK:
		push_error("PlanReceiver: Kan ikke lytte på port %d" % LISTEN_PORT)
		return
	print("PlanReceiver: Lytter på port %d" % LISTEN_PORT)

	var gateway = get_node_or_null("/root/ActionGateway")
	if gateway:
		gateway.unit_idled.connect(_on_unit_idled)
		print("PlanReceiver: Tilsluttet ActionGateway.unit_idled signal")
	else:
		push_error("PlanReceiver: ActionGateway ikke fundet ved opstart")

func _process(_delta: float) -> void:
	if _server.is_connection_available():
		_handle_connection(_server.take_connection())

# ----------------------------------------------------------------
# HTTP server — modtag notifikation fra Planning
# ----------------------------------------------------------------

func _handle_connection(peer: StreamPeerTCP) -> void:
	print("PlanReceiver: Indkommende forbindelse modtaget")
	var raw = ""
	var deadline = Time.get_ticks_msec() + 2000

	# Fase 1: læs indtil headers er modtaget
	while Time.get_ticks_msec() < deadline:
		var n = peer.get_available_bytes()
		if n > 0:
			raw += peer.get_string(n)
			if "\r\n\r\n" in raw:
				break
		OS.delay_msec(1)

	if not "\r\n\r\n" in raw:
		push_warning("PlanReceiver: Timeout — ingen headers modtaget")
		_respond(peer, 400)
		return

	# Fase 2: læs body baseret på Content-Length
	var content_length = 0
	for line in raw.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			content_length = int(line.split(":")[1].strip_edges())
			break

	var header_end = raw.find("\r\n\r\n") + 4
	var body_so_far = raw.length() - header_end
	deadline = Time.get_ticks_msec() + 1000
	while body_so_far < content_length and Time.get_ticks_msec() < deadline:
		var n = peer.get_available_bytes()
		if n > 0:
			raw += peer.get_string(n)
			body_so_far = raw.length() - header_end
		OS.delay_msec(1)

	var body_text = raw.substr(header_end)
	print("PlanReceiver: Body modtaget: %s" % body_text)

	var json = JSON.new()
	if json.parse(body_text) != OK:
		push_warning("PlanReceiver: JSON parse fejl i body: '%s'" % body_text)
		_respond(peer, 400)
		return

	var body: Dictionary = json.get_data()
	var game_id: String   = body.get("game_id", "")
	var player_id: String = body.get("player_id", "")
	var unit_ids: Array   = body.get("unit_ids", [])

	print("PlanReceiver: Notifikation — game=%s player=%s units=%s" % [game_id, player_id, str(unit_ids)])

	if game_id.is_empty() or player_id.is_empty() or unit_ids.is_empty():
		push_warning("PlanReceiver: Manglende felter i notifikation")
		_respond(peer, 422)
		return

	_respond(peer, 200)
	peer.disconnect_from_host()
	_fetch_and_store.call_deferred(game_id, player_id, unit_ids)

func _respond(peer: StreamPeerTCP, code: int) -> void:
	var msg = "OK" if code == 200 else "Error"
	peer.put_data(
		("HTTP/1.1 %d %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" % [code, msg])
		.to_utf8_buffer()
	)

# ----------------------------------------------------------------
# Hent UnitPlans fra Planning og gem i _store
# ----------------------------------------------------------------

func _fetch_and_store(game_id: String, player_id: String, unit_ids: Array) -> void:
	var ids_param = ",".join(unit_ids)
	var url = "%s/plan/%s/%s?unitIds=%s" % [PLANNING_URL, game_id, player_id, ids_param]
	print("PlanReceiver: Henter UnitPlans fra %s" % url)

	var http = HTTPRequest.new()
	add_child(http)
	if http.request(url) != OK:
		push_error("PlanReceiver: HTTP request fejlede")
		http.queue_free()
		return

	var res = await http.request_completed
	http.queue_free()

	print("PlanReceiver: Planning svarede med HTTP %d" % res[1])

	if res[1] != 200:
		push_warning("PlanReceiver: Planning svarede %d — ingen planer tildelt" % res[1])
		return

	var raw_body = res[3].get_string_from_utf8()
	print("PlanReceiver: Svar body: %s" % raw_body)

	var j = JSON.new()
	if j.parse(raw_body) != OK:
		push_error("PlanReceiver: Kan ikke parse svar fra Planning")
		return

	var resp_body: Dictionary = j.get_data()
	var unit_plans: Array = resp_body.get("unit_plans", [])
	print("PlanReceiver: Modtog %d UnitPlan(s)" % unit_plans.size())

	# Debug: vis alle unit entity_ids i scenen
	var gateway = get_node_or_null("/root/ActionGateway")
	if gateway:
		var all_units = gateway.get_all_units()
		print("PlanReceiver: Units i scenen: %s" % str(all_units.map(func(u): return u.get("id", "?"))))

	for up in unit_plans:
		var uid_str: String = str(up.get("unit_id", ""))
		var steps: Array    = up.get("steps", [])
		print("PlanReceiver: Behandler UnitPlan for unit_id='%s', %d steps" % [uid_str, steps.size()])

		if uid_str.is_empty() or steps.is_empty():
			push_warning("PlanReceiver: Tom UnitPlan — springes over")
			continue

		_store[uid_str] = { "steps": steps, "index": 0 }

		var uid_int = int(uid_str)
		if gateway:
			var unit = gateway._find_unit(uid_int)
			if unit == null:
				push_warning("PlanReceiver: Ingen unit med entity_id=%d fundet i scenen" % uid_int)
				continue
			if unit.command_queue:
				unit.command_queue.clear()
		_execute_current_step(uid_int)

# ----------------------------------------------------------------
# Step-eksekvering og looping
# ----------------------------------------------------------------

func _on_unit_idled(unit_id: int) -> void:
	var uid_str = str(unit_id)
	if not _store.has(uid_str):
		return
	var entry = _store[uid_str]
	entry["index"] = (entry["index"] + 1) % entry["steps"].size()
	print("PlanReceiver: Unit %d idle — avancerer til step %d" % [unit_id, entry["index"]])
	_execute_current_step(unit_id)

func _execute_current_step(unit_id: int) -> void:
	var uid_str = str(unit_id)
	if not _store.has(uid_str):
		return
	var entry = _store[uid_str]
	var step  = entry["steps"][entry["index"]]
	_dispatch_step(unit_id, step)

func _dispatch_step(unit_id: int, step: Dictionary) -> void:
	var gateway = get_node_or_null("/root/ActionGateway")
	if not gateway:
		push_error("PlanReceiver: ActionGateway ikke fundet")
		return

	var action_type: String  = step.get("action_type", "")
	var params: Dictionary   = step.get("parameters", {})
	print("PlanReceiver: Dispatcher step til unit %d: action_type=%s params=%s" % [unit_id, action_type, str(params)])

	match action_type:
		"MoveTo":
			var pos = Vector2(float(params.get("x", 0)), float(params.get("y", 0)))
			gateway.move_unit(unit_id, pos)
		"Harvest":
			var tid = int(params.get("target_id", -1))
			gateway.go_chop_tree(unit_id, tid)
		"Construct":
			gateway.go_construct(
				unit_id,
				params.get("scene", ""),
				Vector2(float(params.get("x", 0)), float(params.get("y", 0))),
				float(params.get("duration", 10.0))
			)
		_:
			push_warning("PlanReceiver: Ukendt action_type '%s'" % action_type)
