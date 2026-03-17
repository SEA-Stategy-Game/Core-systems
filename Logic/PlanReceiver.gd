## PlanReceiver.gd — Autoload singleton
## Modtager plan-notifikationer fra Planning, henter UnitPlans og driver
## sekventiel, loopende plan-eksekvering for hver unit via ActionGateway.
extends Node

const LISTEN_PORT  = 8081
const PLANNING_URL = "http://localhost:5000"

## unit_id (String) → { "steps": Array, "index": int }
var _store: Dictionary = {}

var _server: TCPServer = TCPServer.new()

# ----------------------------------------------------------------
# Lifecycle
# ----------------------------------------------------------------

func _ready() -> void:
	if _server.listen(LISTEN_PORT) != OK:
		push_error("PlanReceiver: Kan ikke lytte på port %d" % LISTEN_PORT)
		return
	print("PlanReceiver: Lytter på port %d" % LISTEN_PORT)

	var gateway = get_node_or_null("/root/ActionGateway")
	if gateway:
		gateway.unit_idled.connect(_on_unit_idled)

func _process(_delta: float) -> void:
	if _server.is_connection_available():
		_handle_connection(_server.take_connection())

# ----------------------------------------------------------------
# HTTP server — modtag notifikation fra Planning
# ----------------------------------------------------------------

func _handle_connection(peer: StreamPeerTCP) -> void:
	var raw = ""
	var deadline = Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < deadline:
		var n = peer.get_available_bytes()
		if n > 0:
			raw += peer.get_string(n)
			if "\r\n\r\n" in raw:
				break
		OS.delay_msec(1)

	var parts = raw.split("\r\n\r\n", true, 1)
	if parts.size() < 2:
		_respond(peer, 400)
		return

	var json = JSON.new()
	if json.parse(parts[1]) != OK:
		_respond(peer, 400)
		return

	var body: Dictionary = json.get_data()
	var game_id: String   = body.get("game_id", "")
	var player_id: String = body.get("player_id", "")
	var unit_ids: Array   = body.get("unit_ids", [])

	if game_id.is_empty() or player_id.is_empty() or unit_ids.is_empty():
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

	var http = HTTPRequest.new()
	add_child(http)
	if http.request(url) != OK:
		push_error("PlanReceiver: HTTP request fejlede")
		http.queue_free()
		return

	var res = await http.request_completed
	http.queue_free()

	if res[1] != 200:
		push_warning("PlanReceiver: Planning svarede %d" % res[1])
		return

	var j = JSON.new()
	if j.parse(res[3].get_string_from_utf8()) != OK:
		push_error("PlanReceiver: Kan ikke parse svar fra Planning")
		return

	# Planning returnerer { "unit_plans": [...] }
	var resp_body: Dictionary = j.get_data()
	var unit_plans: Array = resp_body.get("unit_plans", [])

	var gateway = get_node_or_null("/root/ActionGateway")

	for up in unit_plans:
		var uid_str: String = str(up.get("unit_id", ""))
		var steps: Array    = up.get("steps", [])
		if uid_str.is_empty() or steps.is_empty():
			continue

		# Ny plan: gem og nulstil index
		_store[uid_str] = { "steps": steps, "index": 0 }

		# Ryd eventuel igangværende kø og start step 0 med det samme
		var uid_int = int(uid_str)
		if gateway:
			var unit = gateway._find_unit(uid_int)
			if unit and unit.command_queue:
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
	# Avancér index — loop tilbage til 0 når alle steps er gennemløbet
	entry["index"] = (entry["index"] + 1) % entry["steps"].size()
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
