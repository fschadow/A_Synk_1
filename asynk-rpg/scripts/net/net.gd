extends Node
## LAN-Mehrspieler (Autoload "Net").
##
## Ein Geraet eroeffnet das Spiel (Host), die anderen treten bei (Clients).
## Der Host ist die einzige Stelle, die den Spielstand wirklich aendert:
## Clients schicken nur Zug-WUENSCHE, der Host prueft sie (gehoert die Figur
## diesem Geraet? ist der Zug erlaubt?), fuehrt sie aus und schickt sie an
## alle weiter. Weil die Spielregeln deterministisch sind, reicht es, die
## Zuege zu verschicken. Beim (Wieder-)Beitreten gibt es den ganzen Spielstand.
##
## Die Lobby (wer spielt mit, welches Geraet steuert welchen Spieler, KI an/aus,
## Zugzeit) gehoert NICHT zum GameState, sondern liegt hier in `lobby`:
##   {"players": [{"name", "device", "peer", "ai", "connected"}],
##    "turn_time": int (Sekunden, 0 = aus), "running": bool, "id": String}
## Ein Geraet kann mehrere Spieler steuern (Hotseat im LAN-Spiel).

signal lobby_changed
## Text fuer das LAN-Menue ("Verbinde ...", Fehler).
signal status_changed(text: String)
## Client: der Host hat uns in die Lobby aufgenommen.
signal joined
## Client: das Spiel laeuft schon, wir sollen einen freien Platz waehlen.
signal choose_slot
signal clock_changed

enum Mode {OFF, HOST, CLIENT}

const PORT := 47000
const DISCOVERY_PORT := 47001
const MAX_PLAYERS := 20
const PROTOCOL := 1
## Auswahl fuer die Zugzeit in Sekunden (0 = ohne Zeitlimit).
const TURN_TIMES := [0, 30, 60, 120, 300]
const STATE_SAVE := "user://lan_savegame.json"
const LOBBY_SAVE := "user://lan_lobby.json"
const SETTINGS := "user://settings.cfg"
const DEVICE_FILE := "user://device_id.txt"
const CONNECT_TIMEOUT := 8.0

var mode := Mode.OFF
var lobby := {}
## Bleibt fuer dieses Geraet immer gleich, damit man nach einem Abbruch
## seine Figur zurueckbekommt.
var device_id := ""
## Letzte Fehlermeldung, die das Hauptmenue anzeigen soll.
var last_error := ""
var discovery: LanDiscovery
var director: TurnDirector
var session: GameSession

## Spielstand fuer den Wechsel in die Spielszene (vom Host bekommen bzw. geladen).
var _start_state: GameState
## Zuege, die ankommen, waehrend die Spielszene noch laedt.
var _buffer: Array = []
var _pending_name := ""
var _peer_devices := {}
var _clock_end_ms := 0
var _clock_left := 0.0
var _clock_running := false


func _ready() -> void:
	device_id = _load_device_id()
	lobby = _empty_lobby()
	discovery = LanDiscovery.new()
	discovery.port = DISCOVERY_PORT
	add_child(discovery)
	director = TurnDirector.new()
	add_child(director)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------- Abfragen

func is_active() -> bool:
	return mode != Mode.OFF


func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT


func my_peer() -> int:
	return multiplayer.get_unique_id() if is_active() else 1


func players() -> Array:
	return lobby.get("players", [])


func player_entry(index: int) -> Dictionary:
	var list := players()
	return list[index] if index >= 0 and index < list.size() else {}


## Darf DIESES Geraet den Spieler gerade steuern?
func controls(index: int) -> bool:
	if not is_active():
		return true
	var p := player_entry(index)
	return not p.is_empty() and int(p["peer"]) == my_peer() and not p["ai"] and p["connected"]


func is_ai(index: int) -> bool:
	var p := player_entry(index)
	return is_active() and not p.is_empty() and p["ai"]


## Spiel steht still: der Spieler, der dran ist, hat keine Verbindung und
## keine KI vertritt ihn. Der Host entscheidet dann (warten oder KI).
func is_paused(state: GameState) -> bool:
	if not is_active() or state == null or not lobby.get("running", false):
		return false
	var p := player_entry(state.current_player)
	return not p.is_empty() and not p["connected"] and not p["ai"]


## Wie viele Spieler steuert dieses Geraet (fuer den Hotseat-Uebergabe-Bildschirm)?
func local_player_count() -> int:
	var n := 0
	for i in players().size():
		if controls(i):
			n += 1
	return n


func turn_time() -> int:
	return int(lobby.get("turn_time", 0))


## Restzeit des aktuellen Zuges in Sekunden, -1 ohne Zeitlimit.
func time_left() -> float:
	if turn_time() <= 0:
		return -1.0
	if _clock_running:
		return maxf(0.0, (_clock_end_ms - Time.get_ticks_msec()) / 1000.0)
	return _clock_left


func clock_running() -> bool:
	return _clock_running


static func has_lan_save() -> bool:
	return FileAccess.file_exists(STATE_SAVE) and FileAccess.file_exists(LOBBY_SAVE)


# ------------------------------------------------------- Host / Beitreten

## Spiel eroeffnen. resume = gespeichertes LAN-Spiel fortsetzen.
## Liefert "" oder eine Fehlermeldung.
func host_game(player_name: String, resume := false) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 32) != OK:
		return "Port %d ist belegt – läuft schon ein Spiel auf diesem Gerät?" % PORT
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	if resume:
		var err := _load_lan_save()
		if err != "":
			leave()
			return err
	else:
		lobby = _empty_lobby()
		lobby["turn_time"] = int(load_setting("turn_time", 0))
		_add_player(player_name, device_id, 1)
	discovery.start_host(_announce_info)
	lobby_changed.emit()
	if resume:
		_enter_game()
	return ""


## Einem Spiel beitreten. Liefert "" oder eine Fehlermeldung.
func join(ip: String, player_name: String) -> String:
	leave()
	ip = ip.strip_edges()
	if not ip.is_valid_ip_address():
		return "„%s“ ist keine gültige IP-Adresse." % ip
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		return "Verbindung zu %s nicht möglich." % ip
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	_pending_name = player_name
	status_changed.emit("Verbinde mit %s …" % ip)
	var t := get_tree().create_timer(CONNECT_TIMEOUT)
	t.timeout.connect(func():
		if is_client() and multiplayer.multiplayer_peer == peer \
				and peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			_fail("Keine Antwort von %s." % ip))
	return ""


## LAN-Spiel verlassen bzw. beenden (Host: fuer alle).
func leave() -> void:
	director.detach()
	discovery.stop_host()
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.OFF
	lobby = _empty_lobby()
	session = null
	_start_state = null
	_buffer.clear()
	_peer_devices.clear()
	_clock_running = false
	_clock_left = 0.0


func add_local_player(player_name: String) -> void:
	player_name = player_name.strip_edges()
	if player_name == "":
		return
	if is_host():
		if players().size() < MAX_PLAYERS and not lobby["running"]:
			_add_player(player_name, device_id, 1)
			_broadcast_lobby()
	elif is_client():
		_req_add_player.rpc_id(1, player_name)


func remove_player(index: int) -> void:
	if is_host():
		_remove_player_checked(index, 1)
	elif is_client():
		_req_remove_player.rpc_id(1, index)


func set_turn_time(seconds: int) -> void:
	if not is_host():
		return
	lobby["turn_time"] = seconds
	save_setting("turn_time", seconds)
	_broadcast_lobby()


## Host: Spiel starten (alle Geraete wechseln ins Spiel).
func start_game() -> void:
	if not is_host() or players().size() < 2:
		return
	lobby["running"] = true
	_broadcast_lobby()
	_enter_game()


## Host: KI fuer einen Spieler ein-/ausschalten.
func set_ai(index: int, on: bool) -> void:
	if not is_host() or player_entry(index).is_empty():
		return
	players()[index]["ai"] = on
	_broadcast_lobby()


## Client im laufenden Spiel: freien Platz uebernehmen.
func claim(index: int) -> void:
	if is_client():
		_claim.rpc_id(1, index)


func free_slots() -> Array:
	var out := []
	for i in players().size():
		if not players()[i]["connected"]:
			out.append(i)
	return out


# ------------------------------------------------ Verbindung zur Spielszene

## GameSession holt hier beim Start den Spielstand ab (null = Host, neues Spiel).
func take_start_state() -> GameState:
	var s := _start_state
	_start_state = null
	return s


func player_names() -> Array:
	var names := []
	for p in players():
		names.append(p["name"])
	return names


## Die GameSession der Spielszene meldet sich an.
func attach(s: GameSession) -> void:
	session = s
	if is_host():
		s.move_applied.connect(_on_host_move_applied)
		_game_start.rpc(s.state.to_json(), lobby)
		director.attach(s)
	else:
		var pending := _buffer.duplicate()
		_buffer.clear()
		for m in pending:
			s.apply_remote(m)


func detach(s: GameSession) -> void:
	if session == s:
		session = null
		director.detach()


## Client: Zug-Wunsch an den Host schicken.
func send_moves(moves: Array) -> void:
	if is_client():
		_req_moves.rpc_id(1, moves)


## Client: eigener Stand passt nicht mehr, ganzen Stand neu holen.
func request_sync() -> void:
	if is_client():
		_req_sync.rpc_id(1)


## Host: Zuguhr setzen und an alle schicken.
func set_clock(left: float, running: bool) -> void:
	if not is_host():
		return
	_set_clock_local(left, running)
	_clock.rpc(left, running)


func _set_clock_local(left: float, running: bool) -> void:
	_clock_left = left
	_clock_running = running
	_clock_end_ms = Time.get_ticks_msec() + int(left * 1000.0)
	clock_changed.emit()


# ------------------------------------------------------------ Einstellungen

func load_setting(key: String, default: Variant) -> Variant:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return cfg.get_value("lan", key, default)


func save_setting(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("lan", key, value)
	cfg.save(SETTINGS)


# ------------------------------------------------------------------ intern

func _empty_lobby() -> Dictionary:
	return {"players": [], "turn_time": 0, "running": false, "id": "%x" % randi()}


func _add_player(player_name: String, device: String, peer: int) -> void:
	players().append({"name": player_name.left(20), "device": device, "peer": peer,
		"ai": false, "connected": true})


func _remove_player_checked(index: int, sender: int) -> void:
	var p := player_entry(index)
	if p.is_empty() or lobby["running"]:
		return
	if sender != 1 and int(p["peer"]) != sender:
		return
	players().remove_at(index)
	_broadcast_lobby()


func _broadcast_lobby() -> void:
	if not is_host():
		return
	if lobby["running"]:
		_save_lobby()
	lobby_changed.emit()
	_lobby.rpc(lobby)


func _announce_info() -> Dictionary:
	var host_name := ""
	if not players().is_empty():
		host_name = players()[0]["name"]
	return {"id": lobby["id"], "proto": PROTOCOL, "host": host_name, "players": players().size(),
		"running": lobby["running"], "port": PORT}


func _enter_game() -> void:
	Glob.start_lan_game()


func _fail(reason: String) -> void:
	var was_in_game := session != null
	leave()
	status_changed.emit(reason)
	if was_in_game:
		last_error = reason
		Glob.go_to_menu()


func _owned_by(index: int, peer: int) -> bool:
	var p := player_entry(index)
	return not p.is_empty() and int(p["peer"]) == peer and p["connected"] and not p["ai"]


func _send_sync(peer: int) -> void:
	if session == null:
		return
	_sync.rpc_id(peer, session.state.to_json(), lobby, time_left(), _clock_running)


func _save_lobby() -> void:
	var f := FileAccess.open(LOBBY_SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(lobby))


func _load_lan_save() -> String:
	var data = JSON.parse_string(FileAccess.get_file_as_string(LOBBY_SAVE)) if FileAccess.file_exists(LOBBY_SAVE) else null
	var state := GameState.from_json(FileAccess.get_file_as_string(STATE_SAVE)) if FileAccess.file_exists(STATE_SAVE) else null
	if not data is Dictionary or state == null or state.players.size() != data.get("players", []).size():
		return "Kein gültiges gespeichertes LAN-Spiel gefunden."
	lobby = data
	lobby["running"] = true
	lobby["turn_time"] = int(lobby.get("turn_time", 0))
	for p in players():
		var mine: bool = p["device"] == device_id
		p["peer"] = 1 if mine else 0
		p["connected"] = mine
		p["ai"] = bool(p.get("ai", false))
	_start_state = state
	return ""


func _load_device_id() -> String:
	if FileAccess.file_exists(DEVICE_FILE):
		var text := FileAccess.get_file_as_string(DEVICE_FILE).strip_edges()
		if text != "":
			return text
	var crypto := Crypto.new()
	var id := crypto.generate_random_bytes(8).hex_encode()
	var f := FileAccess.open(DEVICE_FILE, FileAccess.WRITE)
	if f:
		f.store_string(id)
	return id


# ------------------------------------------------- Netzwerk-Ereignisse

func _on_peer_connected(_id: int) -> void:
	pass  # Der Client meldet sich mit _hello.


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	_peer_devices.erase(id)
	if lobby["running"]:
		for p in players():
			if int(p["peer"]) == id:
				p["peer"] = 0
				p["connected"] = false
	else:
		for i in range(players().size() - 1, -1, -1):
			if int(players()[i]["peer"]) == id:
				players().remove_at(i)
	_broadcast_lobby()


func _on_connected_to_server() -> void:
	_hello.rpc_id(1, device_id, PROTOCOL, _pending_name)


func _on_connection_failed() -> void:
	_fail("Verbindung fehlgeschlagen.")


func _on_server_disconnected() -> void:
	_fail("Verbindung zum Host verloren.")


func _on_host_move_applied(move: Dictionary, _state: GameState) -> void:
	_remote_move.rpc(move)


# ------------------------------------------------------- RPC: Client -> Host

@rpc("any_peer", "call_remote", "reliable")
func _hello(device: String, protocol: int, player_name: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_reject(id, "Andere Spielversion – bitte alle Geräte auf denselben Stand bringen.")
		return
	_peer_devices[id] = device
	if lobby["running"]:
		# Wiederkommen: Spieler dieses Geraets zurueckgeben (auch wenn die KI sie vertritt).
		var found := false
		for p in players():
			if p["device"] == device and not p["connected"]:
				p["peer"] = id
				p["connected"] = true
				p["ai"] = false
				found = true
		if found:
			_broadcast_lobby()
			_send_sync(id)
		elif free_slots().is_empty():
			_reject(id, "Das Spiel läuft bereits und alle Plätze sind belegt.")
		else:
			_choose_slot.rpc_id(id, lobby)
		return
	if players().size() >= MAX_PLAYERS:
		_reject(id, "Die Lobby ist voll (%d Spieler)." % MAX_PLAYERS)
		return
	_add_player(player_name, device, id)
	_broadcast_lobby()
	_welcome.rpc_id(id)


@rpc("any_peer", "call_remote", "reliable")
func _claim(index: int) -> void:
	if not is_host() or not lobby["running"]:
		return
	var id := multiplayer.get_remote_sender_id()
	var p := player_entry(index)
	if p.is_empty() or p["connected"] or not _peer_devices.has(id):
		_reject(id, "Dieser Platz ist nicht mehr frei.")
		return
	p["peer"] = id
	p["device"] = _peer_devices[id]
	p["connected"] = true
	p["ai"] = false
	_broadcast_lobby()
	_send_sync(id)


@rpc("any_peer", "call_remote", "reliable")
func _req_add_player(player_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host() or lobby["running"] or not _peer_devices.has(id):
		return
	player_name = player_name.strip_edges()
	if player_name == "" or players().size() >= MAX_PLAYERS:
		return
	_add_player(player_name, _peer_devices[id], id)
	_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func _req_remove_player(index: int) -> void:
	if is_host():
		_remove_player_checked(index, multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _req_moves(moves: Array) -> void:
	if not is_host() or session == null:
		return
	var id := multiplayer.get_remote_sender_id()
	if session.state and is_paused(session.state):
		_move_rejected.rpc_id(id, "Spiel ist pausiert.")
		return
	for m in moves:
		if not m is Dictionary or not _owned_by(int(m.get("player", -1)), id):
			_move_rejected.rpc_id(id, "Das ist nicht dein Zug.")
			return
		var err := session.try_submit(m)
		if err != "":
			_move_rejected.rpc_id(id, err)
			return


@rpc("any_peer", "call_remote", "reliable")
func _req_sync() -> void:
	if is_host():
		_send_sync(multiplayer.get_remote_sender_id())


func _reject(peer: int, reason: String) -> void:
	_rejected.rpc_id(peer, reason)
	get_tree().create_timer(0.5).timeout.connect(func():
		if is_host() and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer))


# ------------------------------------------------------- RPC: Host -> Clients

@rpc("authority", "call_remote", "reliable")
func _welcome() -> void:
	status_changed.emit("")
	joined.emit()


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	_fail(reason)


@rpc("authority", "call_remote", "reliable")
func _lobby(data: Dictionary) -> void:
	lobby = data
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _choose_slot(data: Dictionary) -> void:
	lobby = data
	status_changed.emit("")
	choose_slot.emit()


@rpc("authority", "call_remote", "reliable")
func _game_start(state_json: String, data: Dictionary) -> void:
	lobby = data
	if session:
		session.load_state(GameState.from_json(state_json))
		return
	_buffer.clear()
	_start_state = GameState.from_json(state_json)
	_enter_game()


@rpc("authority", "call_remote", "reliable")
func _sync(state_json: String, data: Dictionary, left: float, running: bool) -> void:
	lobby = data
	lobby_changed.emit()
	_set_clock_local(left, running)
	var state := GameState.from_json(state_json)
	if session:
		_buffer.clear()
		session.load_state(state)
		return
	_buffer.clear()
	_start_state = state
	_enter_game()


@rpc("authority", "call_remote", "reliable")
func _remote_move(move: Dictionary) -> void:
	if session:
		session.apply_remote(move)
	else:
		_buffer.append(move)


@rpc("authority", "call_remote", "reliable")
func _move_rejected(reason: String) -> void:
	if session:
		session.move_rejected.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _clock(left: float, running: bool) -> void:
	_set_clock_local(left, running)
