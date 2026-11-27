class_name GameSession
extends Node
## Verbindet Spiellogik und Szene. Haelt den aktuellen GameState, nimmt Zuege
## entgegen, prueft sie mit GameRules und meldet Aenderungen per Signal.
## Die Anzeige (Figuren, HUD) hoert nur auf diese Signale und veraendert den
## Spielstand nie selbst.
##
## Im LAN-Spiel (siehe Net) gehen Zug-Wuensche eines Clients erst zum Host;
## der Host prueft, fuehrt aus und schickt die Zuege an alle (apply_remote).
## Spaeter kommt hier der Austausch ueber Google Drive dazu.

signal game_started(state: GameState)
signal move_applied(move: Dictionary, state: GameState)
signal turn_started(player_index: int, state: GameState)
signal move_rejected(reason: String)
## Eine Karte wurde erzeugt (MapGen-Ergebnis); kommt vor game_started.
signal map_ready(gen: Dictionary)

const GROUP := "game_session"

## Die Bodenebene, aus der die begehbaren Felder gelesen werden.
@export var terrain: TileMapLayer
## Objekt-Ebenen (Baeume, Steine) links und rechts im Feld.
@export var objects_left: TileMapLayer
@export var objects_right: TileMapLayer
@export var player_names: PackedStringArray = ["Spieler 1", "Spieler 2"]
@export var start_cells: Array[Vector2i] = [Vector2i(0, 1), Vector2i(2, 2)]
## Spielstand nach jedem Zug in user://savegame.json sichern und beim Start laden.
@export var autosave := true

const SAVE_PATH := "user://savegame.json"

var state: GameState
var map: HexMap
var objects: WorldObjects


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	map = HexMap.from_cells(terrain.get_used_cells() if terrain else [])
	objects = WorldObjects.from_layers(terrain, objects_left, objects_right)
	# Erst starten, wenn alle Figuren/HUDs ihr _ready hinter sich haben.
	_start.call_deferred()


func _exit_tree() -> void:
	Net.detach(self)


func _start() -> void:
	if Net.is_active():
		_start_lan()
		return
	if Glob.start_new_game:
		Glob.start_new_game = false
		new_game()
		return
	var loaded := load_game() if autosave else null
	if loaded:
		state = loaded
	else:
		new_game()
		return
	game_started.emit(state)
	turn_started.emit(state.current_player, state)


func new_game(names: Array = player_names) -> void:
	var settings := new_game_settings()
	_setup_map(settings)
	state = GameState.new_game(names, pick_start_cells(names.size()), GameRules.STEPS_PER_TURN,
		scene_file_path_or_name(), settings)
	_save()
	game_started.emit(state)
	turn_started.emit(state.current_player, state)


## LAN: Client bekommt den Stand vom Host, der Host setzt ein gespeichertes
## Spiel fort oder beginnt ein neues mit den Spielern aus der Lobby.
func _start_lan() -> void:
	var s := Net.take_start_state()
	if s == null and Net.is_authority():
		new_game(Net.player_names())
	elif s != null:
		load_state(s)
	else:
		Net.last_error = "Kein Spielstand vom Host erhalten."
		Glob.go_to_menu()
		return
	Net.attach(self)


## Einstellungen fuer ein neues Spiel aus der Lobby (ohne Lobby: gemalte
## Karte ohne Jahreszeiten). Ein Seed 0 wird hier einmal ausgewuerfelt, damit
## alle Geraete dieselbe Karte bekommen.
func new_game_settings() -> Dictionary:
	if not Net.is_active():
		return {}
	var map_settings: Dictionary = MapGen.default_settings()
	map_settings.merge(Net.lobby.get("map", {}), true)
	if int(map_settings.get("seed", 0)) == 0:
		map_settings["seed"] = randi_range(1, 999999)
	return {"season_length": Net.season_length(), "map": map_settings}


## Karte zu den Einstellungen aufbauen: gemalte Karte der Szene oder
## generierte Karte (dann map_ready, damit MapPainter sie zeichnet).
func _setup_map(settings: Dictionary) -> void:
	var map_settings: Dictionary = settings.get("map", {})
	if not MapGen.is_generated(map_settings):
		return
	var gen := MapGen.generate(map_settings)
	map = HexMap.from_types(gen["types"], gen["flow"])
	objects = WorldObjects.from_dict(gen["objects"])
	start_cells = [gen["start"]]
	map_ready.emit(gen)


## Kompletten Spielstand uebernehmen (LAN-Start, Wiederbeitritt, Neuabgleich).
func load_state(s: GameState) -> void:
	if state == null or state.settings != s.settings:
		_setup_map(s.settings)
	state = s
	_save()
	game_started.emit(state)
	turn_started.emit(state.current_player, state)


## Freies Startfeld fuer einen neu einsteigenden Spieler.
func free_start_cell() -> Vector2i:
	var taken := state.occupied_cells()
	var origin: Vector2i = start_cells[0] if not start_cells.is_empty() else taken[0]
	for c in map.reachable(origin):
		var ok := not taken.has(c) and map.is_land(c)
		for t in taken:
			if map.are_neighbors(t, c):
				ok = false
				break
		if ok:
			return c
	for c in map.reachable(origin):
		if not taken.has(c):
			return c
	return origin


## Startfelder fuer n Spieler: erst die eingestellten, dann weitere begehbare
## Felder in der Naehe, die nicht direkt nebeneinander liegen.
func pick_start_cells(n: int) -> Array:
	var cells: Array = []
	for c in start_cells:
		if cells.size() < n and map.is_land(c) and not cells.has(c):
			cells.append(c)
	if cells.size() < n and not start_cells.is_empty():
		for c in map.reachable(start_cells[0]):
			if cells.size() >= n:
				break
			var free := map.is_land(c)
			for other in cells:
				if other == c or map.are_neighbors(other, c):
					free = false
					break
			if free:
				cells.append(c)
	return cells


## Versucht, den aktuellen Spieler auf das Feld zu bewegen.
func request_move_to(cell: Vector2i) -> bool:
	if not _may_act():
		return false
	var move := GameRules.make_move_to(state, map, cell)
	if move.is_empty():
		move_rejected.emit("Feld nicht erreichbar")
		return false
	return _request([move])


## Mit gewaehlter Faehigkeit auf ein Feld getippt: hinlaufen (falls noetig)
## und dort abbauen. ACT_WALK ist normales Laufen.
func request_action(cell: Vector2i, action: String) -> bool:
	if action == ResourceConfig.ACT_WALK:
		return request_move_to(cell)
	if not _may_act():
		return false
	var plan := GameRules.make_action_at(state, map, objects, cell, action)
	if plan.has("error"):
		move_rejected.emit(plan["error"])
		return false
	return _request(plan["moves"])


func request_end_turn() -> bool:
	if not _may_act():
		return false
	return _request([GameRules.make_end_turn(state)])


## Darf dieses Geraet gerade ziehen? (Im LAN: eigener Spieler und keine Pause.)
func _may_act() -> bool:
	if state == null:
		return false
	var who: String = state.current()["name"]
	if Net.is_paused(state):
		move_rejected.emit("Spiel pausiert – %s fehlt" % who)
		return false
	if not Net.controls(state.current_player):
		move_rejected.emit("%s ist dran" % who)
		return false
	return true


## Zuege dieses Geraets: lokal direkt ausfuehren, als LAN-Client erst
## vorpruefen und dann an den Host schicken.
func _request(moves: Array) -> bool:
	if Net.is_client():
		var sim := state.duplicate_state()
		for m in moves:
			var err := GameRules.validate(sim, map, m, objects)
			if err != "":
				move_rejected.emit(err)
				return false
			GameRules.apply(sim, m)
		Net.send_moves(moves)
		return true
	for m in moves:
		if not submit(m):
			return false
	return true


## Einziger Weg, den Spielstand zu aendern (lokal bzw. auf dem Host).
func submit(move: Dictionary) -> bool:
	var err := try_submit(move)
	if err != "":
		move_rejected.emit(err)
		return false
	return true


## Wie submit(), meldet einen Fehler aber nicht per Signal, sondern gibt ihn
## zurueck (fuer Zuege anderer Geraete, der KI und der Zuguhr).
func try_submit(move: Dictionary) -> String:
	var err := GameRules.validate(state, map, move, objects)
	if err != "":
		return err
	_apply(move)
	_save()
	return ""


## LAN-Client: Zug, den der Host schon ausgefuehrt hat, uebernehmen.
func apply_remote(move: Dictionary) -> void:
	if state == null:
		return
	var err := GameRules.validate(state, map, move, objects)
	if err != "":
		push_warning("LAN: Zug vom Host passt nicht (%s), hole Spielstand neu" % err)
		Net.request_sync()
		return
	_apply(move)
	_save()


func _apply(move: Dictionary) -> void:
	var before_player := state.current_player
	GameRules.apply(state, move)
	move_applied.emit(state.history[-1], state)
	if state.current_player != before_player:
		turn_started.emit(state.current_player, state)


## true, wenn der alte Einzel-Spielstand existiert (Szene ohne Lobby gestartet).
static func has_savegame() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Sofort speichern (z. B. nach Lobby-Aenderungen im laufenden Spiel).
func save_now() -> void:
	_save()


func load_game() -> GameState:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var s := GameState.from_json(FileAccess.get_file_as_string(SAVE_PATH))
	if s == null or s.players.size() != player_names.size():
		return null
	for p in s.players:
		if not map.is_walkable(p["pos"]):
			return null
	return s


## Spiele mit Lobby landen in SaveStore (auf jedem beteiligten Geraet, auch
## als LAN-Client), die Szene ohne Lobby (Tests/Editor) im alten Einzelstand.
func _save() -> void:
	if not autosave or state == null:
		return
	if Net.is_active():
		SaveStore.save(Net.lobby.get("id", ""), state, Net.lobby)
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(state.to_json())


func scene_file_path_or_name() -> String:
	var owner_scene := owner if owner else get_tree().current_scene
	return owner_scene.scene_file_path if owner_scene else ""
