extends Node
## Lobby und Mehrspieler (Autoload "Net").
##
## Jedes Spiel mit Lobby laeuft ueber diesen Knoten:
## - LOCAL: Einzelspieler/Hotseat auf diesem Geraet (kein Netzwerk).
## - HOST:  dieses Geraet eroeffnet ein LAN-Spiel.
## - CLIENT: dieses Geraet ist einem LAN-Spiel beigetreten.
## LOCAL und HOST sind "Autoritaet": nur dort wird der Spielstand wirklich
## geaendert. Clients schicken Zug-WUENSCHE, der Host prueft (gehoert die Figur
## diesem Geraet? ist der Zug erlaubt?), fuehrt aus und schickt die Zuege an
## alle. Beim (Wieder-)Beitreten gibt es den ganzen Spielstand.
##
## Die Lobby gehoert NICHT zum GameState:
##   {"id", "lan": bool, "running": bool, "resume": bool,
##    "turn_time": Sekunden (0 = aus), "season_length": Runden,
##    "map": {"preset", "size", "seed"},
##    "players": [{"name", "device", "orig", "peer", "ai", "connected", "new"?}]}
## device = Geraet, das den Spieler gerade steuert; orig = Geraet, dem der
## Spieler urspruenglich gehoert (hat Vorrang, wenn es wiederkommt).
## Ein Geraet kann mehrere Spieler steuern (Hotseat), KI-Spieler haben peer 0.

signal lobby_changed
## Text fuer das Menue ("Verbinde ...", Fehler).
signal status_changed(text: String)
## Client: der Host hat uns in die Lobby aufgenommen.
signal joined
## Client im laufenden Spiel: Platz waehlen (frei oder neu einsteigen).
signal choose_slot
signal clock_changed

enum Mode {OFF, LOCAL, HOST, CLIENT}

const PORT := 47000
const DISCOVERY_PORT := 47001
const MAX_PLAYERS := 20
const PROTOCOL := 2
## Auswahl fuer die Zugzeit in Sekunden (0 = ohne Zeitlimit).
const TURN_TIMES := [0, 30, 60, 120, 300]
## Auswahl: nach so vielen Runden beginnt die naechste Jahreszeit.
const SEASON_LENGTHS := [5, 10, 15, 20, 30]
const DEFAULT_SEASON_LENGTH := 10
const SETTINGS := "user://settings.cfg"
const DEVICE_FILE := "user://device_id.txt"
const CONNECT_TIMEOUT := 8.0

var mode := Mode.OFF
var lobby := {}
## Bleibt fuer dieses Geraet immer gleich, damit man nach einem Abbruch
## seine Figur zurueckbekommt.
var device_id := ""
## Letzte Fehlermeldung, die das Menue anzeigen soll.
var last_error := ""
var discovery: LanDiscovery
var director: TurnDirector
var session: GameSession

## Spielstand fuer den Wechsel in die Spielszene (vom Host bekommen bzw. geladen).
var _start_state: GameState
## Zuege, die ankommen, waehrend die Spielszene noch laedt.
var _buffer: Array = []
var _pending_name := ""
## peer -> {"device", "name"}
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

## Irgendein Spiel mit Lobby (lokal oder LAN).
func is_active() -> bool:
	return mode != Mode.OFF


func is_networked() -> bool:
	return mode == Mode.HOST or mode == Mode.CLIENT


func is_local() -> bool:
	return mode == Mode.LOCAL


func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT


## Aendert dieses Geraet den Spielstand selbst (lokal oder als Host)?
func is_authority() -> bool:
	return mode == Mode.LOCAL or mode == Mode.HOST


func my_peer() -> int:
	return multiplayer.get_unique_id() if is_networked() else 1


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
	if not is_networked() or state == null or not lobby.get("running", false):
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


func season_length() -> int:
	return int(lobby.get("season_length", DEFAULT_SEASON_LENGTH))


## Restzeit des aktuellen Zuges in Sekunden, -1 ohne Zeitlimit.
func time_left() -> float:
	if turn_time() <= 0:
		return -1.0
	if _clock_running:
		return maxf(0.0, (_clock_end_ms - Time.get_ticks_msec()) / 1000.0)
	return _clock_left


func clock_running() -> bool:
	return _clock_running


## Ein Platz ist frei, wenn ihn gerade niemand steuert (auch KI-Vertretung).
func is_free(index: int) -> bool:
	var p := player_entry(index)
	return not p.is_empty() and not p["connected"]


func free_slots() -> Array:
	var out := []
	for i in players().size():
		if is_free(i):
			out.append(i)
	return out


## Lobby eines geladenen Spielstands (Spieler stehen schon fest)?
func is_resume() -> bool:
	return lobby.get("resume", false)


# ------------------------------------------------- Lokal / Host / Beitreten

## Neues lokales Spiel (Einzelspieler/Hotseat): Lobby oeffnen.
func start_local(player_name: String) -> void:
	leave()
	mode = Mode.LOCAL
	lobby = _new_lobby(false)
	_add_player(player_name, device_id, 1)
	lobby_changed.emit()


## Neues LAN-Spiel eroeffnen. Liefert "" oder eine Fehlermeldung.
func host_game(player_name: String) -> String:
	var err := _open_server()
	if err != "":
		return err
	lobby = _new_lobby(true)
	_add_player(player_name, device_id, 1)
	lobby_changed.emit()
	return ""


## Spielstand lokal weiterspielen: alle Menschen sitzen an diesem Geraet.
func load_local(save_id: String) -> String:
	var data := SaveStore.read(save_id)
	if data.is_empty():
		return "Spielstand ist beschädigt."
	leave()
	mode = Mode.LOCAL
	lobby = _normalize_lobby(data["lobby"])
	lobby["lan"] = false
	lobby["running"] = true
	lobby["resume"] = false
	for p in players():
		if not p["ai"]:
			p["peer"] = 1
			p["device"] = device_id
		p["connected"] = true
	_start_state = data["state"]
	_enter_game()
	return ""


## Spielstand als LAN-Spiel hosten: Lobby mit den gespeicherten Spielern.
## Spieler dieses Geraets sind belegt, die anderen frei. Wer beitritt, bekommt
## seine alten Spieler automatisch zurueck oder waehlt einen freien Platz bzw.
## steigt neu ein.
func host_saved(save_id: String) -> String:
	var data := SaveStore.read(save_id)
	if data.is_empty():
		return "Spielstand ist beschädigt."
	var err := _open_server()
	if err != "":
		return err
	lobby = _normalize_lobby(data["lobby"])
	lobby["lan"] = true
	lobby["running"] = false
	lobby["resume"] = true
	for p in players():
		var mine: bool = p["orig"] == device_id or (p["orig"] == "" and not p["ai"])
		if p["ai"]:
			p["peer"] = 0
			p["connected"] = true
		else:
			p["peer"] = 1 if mine else 0
			p["connected"] = mine
			p["device"] = device_id if mine else ""
	_start_state = data["state"]
	lobby_changed.emit()
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


## Spiel verlassen bzw. beenden (Host: fuer alle).
func leave() -> void:
	director.detach()
	discovery.stop_host()
	# Erst den Modus zuruecksetzen: beim Schliessen kommen noch
	# "peer_disconnected"-Meldungen, auf die nicht mehr reagiert werden soll.
	mode = Mode.OFF
	var peer := multiplayer.multiplayer_peer
	if peer and not peer is OfflineMultiplayerPeer:
		peer.close()
	multiplayer.multiplayer_peer = null
	lobby = _empty_lobby()
	session = null
	_start_state = null
	_buffer.clear()
	_peer_devices.clear()
	_clock_running = false
	_clock_left = 0.0


# ------------------------------------------------------- Lobby bearbeiten

func add_local_player(player_name: String) -> void:
	player_name = player_name.strip_edges()
	if player_name == "" or players().size() >= MAX_PLAYERS:
		return
	if is_authority():
		if lobby["running"]:
			return
		_add_player(player_name, device_id, 1, is_resume())
		_broadcast_lobby()
	elif is_client():
		_req_add_player.rpc_id(1, player_name)


func add_ai_player() -> void:
	if not is_authority() or lobby["running"] or players().size() >= MAX_PLAYERS:
		return
	var n := 1
	for p in players():
		if p["ai"]:
			n += 1
	_add_player("KI %d" % n, "", 0, is_resume())
	players()[-1]["ai"] = true
	_broadcast_lobby()


func remove_player(index: int) -> void:
	if is_authority():
		_remove_player_checked(index, 1)
	elif is_client():
		_req_remove_player.rpc_id(1, index)


## Lobby eines geladenen Spiels: freien Platz uebernehmen (Host oder Client).
func take_slot(index: int) -> void:
	if is_authority():
		_assign(index, 1, device_id)
		_broadcast_lobby()
	elif is_client():
		_claim.rpc_id(1, index, _pending_name)


## Lobby eines geladenen Spiels (Host): Platz freigeben fuer andere Geraete.
func free_slot(index: int) -> void:
	var p := player_entry(index)
	if not is_host() or p.is_empty() or lobby["running"] or p.get("new", false):
		return
	p["peer"] = 0
	p["connected"] = false
	p["device"] = ""
	_broadcast_lobby()


## Client im laufenden Spiel: als neuer Spieler einsteigen.
func join_as_new() -> void:
	if is_client():
		_claim.rpc_id(1, -1, _pending_name)


## Client im laufenden Spiel: freien Platz uebernehmen.
func claim(index: int) -> void:
	if is_client():
		_claim.rpc_id(1, index, _pending_name)


func set_turn_time(seconds: int) -> void:
	_set_lobby_value("turn_time", seconds)


func set_season_length(rounds: int) -> void:
	_set_lobby_value("season_length", rounds)


func set_map(settings: Dictionary) -> void:
	_set_lobby_value("map", settings)


func _set_lobby_value(key: String, value: Variant) -> void:
	if not is_authority() or lobby["running"]:
		return
	lobby[key] = value
	save_setting(key, value)
	_broadcast_lobby()


func can_start() -> bool:
	if not is_authority() or lobby["running"]:
		return false
	return players().size() >= (1 if is_local() else 2) or is_resume()


## Spiel starten (alle Geraete wechseln ins Spiel).
func start_game() -> void:
	if not can_start():
		return
	lobby["running"] = true
	lobby["resume"] = false
	_broadcast_lobby()
	_enter_game()


## Host: KI fuer einen Spieler ein-/ausschalten.
func set_ai(index: int, on: bool) -> void:
	if not is_authority() or player_entry(index).is_empty():
		return
	players()[index]["ai"] = on
	_broadcast_lobby()


# ------------------------------------------------ Verbindung zur Spielszene

## GameSession holt hier beim Start den Spielstand ab (null = neues Spiel).
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
	# Neu eingestiegene Spieler (Lobby eines geladenen Spiels) ins Spiel holen.
	if is_authority():
		for i in range(s.state.players.size(), players().size()):
			var p: Dictionary = players()[i]
			if s.try_submit(GameRules.make_join(s.state, p["name"], s.free_start_cell())) != "":
				push_warning("Neuer Spieler %s konnte nicht einsteigen" % p["name"])
			p.erase("new")
		while players().size() > s.state.players.size():
			players().pop_back()
	if is_host():
		s.move_applied.connect(_on_host_move_applied)
		_game_start.rpc(s.state.to_json(), lobby)
	if is_authority():
		director.attach(s)
	else:
		var pending := _buffer.duplicate()
		_buffer.clear()
		for m in pending:
			s.apply_remote(m)
	s.save_now()


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


## Zuguhr setzen (Autoritaet) und im LAN an alle schicken.
func set_clock(left: float, running: bool) -> void:
	if not is_authority():
		return
	_set_clock_local(left, running)
	if is_host():
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
	return {"players": [], "turn_time": 0, "season_length": DEFAULT_SEASON_LENGTH,
		"map": {}, "running": false, "resume": false, "lan": false, "id": ""}


## Neue Lobby mit den zuletzt benutzten Einstellungen.
func _new_lobby(lan: bool) -> Dictionary:
	var l := _empty_lobby()
	l["lan"] = lan
	l["id"] = "%d_%s" % [int(Time.get_unix_time_from_system()), Crypto.new().generate_random_bytes(3).hex_encode()]
	l["turn_time"] = int(load_setting("turn_time", 0))
	l["season_length"] = int(load_setting("season_length", DEFAULT_SEASON_LENGTH))
	var map_settings = load_setting("map", {})
	l["map"] = map_settings if map_settings is Dictionary else {}
	return l


## Felder aelterer Spielstaende ergaenzen.
func _normalize_lobby(raw: Dictionary) -> Dictionary:
	var l := _empty_lobby()
	l.merge(raw, true)
	for p in l["players"]:
		p["ai"] = bool(p.get("ai", false))
		p["device"] = str(p.get("device", ""))
		p["orig"] = str(p.get("orig", p["device"]))
		p["peer"] = int(p.get("peer", 0))
		p["connected"] = bool(p.get("connected", false))
		p.erase("new")
	return l


func _open_server() -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 32) != OK:
		return "Port %d ist belegt – läuft schon ein Spiel auf diesem Gerät?" % PORT
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	discovery.start_host(_announce_info)
	return ""


func _add_player(player_name: String, device: String, peer: int, is_new := false) -> void:
	var p := {"name": player_name.left(20), "device": device, "orig": device, "peer": peer,
		"ai": false, "connected": true}
	if is_new:
		p["new"] = true
	players().append(p)


func _assign(index: int, peer: int, device: String) -> void:
	var p := player_entry(index)
	if p.is_empty():
		return
	p["peer"] = peer
	p["device"] = device
	p["connected"] = true
	p["ai"] = false


func _remove_player_checked(index: int, sender: int) -> void:
	var p := player_entry(index)
	if p.is_empty() or lobby["running"]:
		return
	# In einem geladenen Spiel lassen sich nur neu hinzugekommene Spieler entfernen.
	if is_resume() and not p.get("new", false):
		return
	if sender != 1 and int(p["peer"]) != sender:
		return
	players().remove_at(index)
	_broadcast_lobby()


func _broadcast_lobby() -> void:
	if not is_authority():
		return
	lobby_changed.emit()
	if is_host():
		_lobby.rpc(lobby)
	if lobby["running"] and session:
		session.save_now()


func _announce_info() -> Dictionary:
	var host_name := ""
	for p in players():
		if int(p["peer"]) == 1:
			host_name = p["name"]
			break
	return {"id": lobby["id"], "proto": PROTOCOL, "host": host_name, "players": players().size(),
		"running": lobby["running"] or is_resume(), "port": PORT}


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


## Spieler, die urspruenglich diesem Geraet gehoeren, zurueckgeben (Vorrang!).
## Liefert [bekommen: bool, verdraengte Peers: Array].
func _reclaim(device: String, peer: int) -> Array:
	var got := false
	var bumped := []
	for p in players():
		if p["orig"] != device:
			continue
		var holder := int(p["peer"])
		if p["connected"] and holder != 0 and holder != peer:
			if not bumped.has(holder):
				bumped.append(holder)
		p["peer"] = peer
		p["device"] = device
		p["connected"] = true
		p["ai"] = false
		got = true
	# Verdraengte Geraete behalten ggf. noch andere Spieler.
	var still := []
	for b in bumped:
		var has_any := false
		for p in players():
			if int(p["peer"]) == b:
				has_any = true
		if not has_any:
			still.append(b)
	return [got, still]


func _load_device_id() -> String:
	if FileAccess.file_exists(DEVICE_FILE):
		var text := FileAccess.get_file_as_string(DEVICE_FILE).strip_edges()
		if text != "":
			return text
	var id := Crypto.new().generate_random_bytes(8).hex_encode()
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
	for i in range(players().size() - 1, -1, -1):
		var p: Dictionary = players()[i]
		if int(p["peer"]) != id:
			continue
		if lobby["running"] or (is_resume() and not p.get("new", false)):
			p["peer"] = 0
			p["connected"] = false
		else:
			players().remove_at(i)
	# Erst im naechsten Frame senden: andere Peers koennen gerade mit abbauen.
	_broadcast_lobby.call_deferred()


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
	_peer_devices[id] = {"device": device, "name": player_name}
	if lobby["running"] or is_resume():
		var result := _reclaim(device, id)
		_broadcast_lobby()
		if lobby["running"]:
			if result[0]:
				_send_sync(id)
			else:
				_choose_slot.rpc_id(id, lobby)
			for b in result[1]:
				_choose_slot.rpc_id(b, lobby)
		else:
			_welcome.rpc_id(id)
		return
	if players().size() >= MAX_PLAYERS:
		_reject(id, "Die Lobby ist voll (%d Spieler)." % MAX_PLAYERS)
		return
	_add_player(player_name, device, id)
	_broadcast_lobby()
	_welcome.rpc_id(id)


## index >= 0: freien Platz uebernehmen, -1: als neuer Spieler einsteigen.
@rpc("any_peer", "call_remote", "reliable")
func _claim(index: int, player_name: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _peer_devices.has(id):
		return
	var device: String = _peer_devices[id]["device"]
	player_name = player_name.strip_edges().left(20)
	if player_name == "":
		player_name = "Spieler %d" % (players().size() + 1)
	if index < 0:
		if players().size() >= MAX_PLAYERS:
			_move_rejected.rpc_id(id, "Das Spiel ist voll.")
			return
		if lobby["running"]:
			if session == null:
				return
			var err := session.try_submit(GameRules.make_join(session.state, player_name, session.free_start_cell()))
			if err != "":
				_move_rejected.rpc_id(id, err)
				return
			_add_player(player_name, device, id)
		elif is_resume():
			_add_player(player_name, device, id, true)
		else:
			return
	else:
		if not is_free(index) or not (lobby["running"] or is_resume()):
			if lobby["running"]:
				_choose_slot.rpc_id(id, lobby)
			return
		_assign(index, id, device)
	_broadcast_lobby()
	if lobby["running"]:
		_send_sync(id)


@rpc("any_peer", "call_remote", "reliable")
func _req_add_player(player_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host() or lobby["running"] or not _peer_devices.has(id):
		return
	player_name = player_name.strip_edges()
	if player_name == "" or players().size() >= MAX_PLAYERS:
		return
	_add_player(player_name, _peer_devices[id]["device"], id, is_resume())
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
		if not m is Dictionary or m.get("type") == GameRules.TYPE_JOIN or not _owned_by(int(m.get("player", -1)), id):
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
	if lobby.get("running", false) and session:
		session.save_now()


@rpc("authority", "call_remote", "reliable")
func _choose_slot(data: Dictionary) -> void:
	lobby = data
	status_changed.emit("")
	if session:
		# Im Spiel verdraengt (urspruenglicher Spieler ist zurueck): ins Menue
		# zur Platzwahl, die Verbindung bleibt bestehen.
		session = null
		Glob.menu_entry = Glob.MENU_SLOTS
		get_tree().change_scene_to_file(Glob.LAN_SCENE)
		return
	choose_slot.emit()


@rpc("authority", "call_remote", "reliable")
func _game_start(state_json: String, data: Dictionary) -> void:
	lobby = data
	if session:
		session.load_state(GameState.from_json(state_json))
		return
	if local_player_count() == 0:
		# Wir haben (noch) keinen Platz: Platz waehlen oder neu einsteigen.
		choose_slot.emit()
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
	_buffer.clear()
	if session:
		session.load_state(state)
		return
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
	else:
		status_changed.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _clock(left: float, running: bool) -> void:
	_set_clock_local(left, running)
