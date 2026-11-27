class_name GameState
extends RefCounted
## Der komplette Spielstand als reine Daten. Alles hier laesst sich mit
## to_dict()/from_dict() in JSON umwandeln, damit der Stand spaeter in einer
## (Google-Drive-)Datei zwischen den Spielern hin und her gehen kann.

const FORMAT_VERSION := 3

var map_id: String = ""
## Spiel-Einstellungen, die die Regeln beeinflussen (gleich auf allen Geraeten):
## {"season_length": Runden (0 = ohne Jahreszeiten),
##  "map": {"preset", "size", "seed"}}  (siehe MapGen)
var settings: Dictionary = {}
## Laufende Runde, beginnt bei 1. Eine Runde ist vorbei, wenn alle einmal dran waren.
var round_number: int = 1
## Index in players, wer gerade am Zug ist.
var current_player: int = 0
## Jeder Spieler: {"id": String, "name": String, "pos": Vector2i, "steps_left": int,
##                 "inv": {item: int}}  (siehe ResourceConfig.ITEMS)
var players: Array[Dictionary] = []
## Alle bisher ausgefuehrten Zuege, in Reihenfolge (siehe GameRules fuer das Format).
var history: Array[Dictionary] = []
## Nur Objekte, die schon angefasst wurden (alle anderen haben vollen Vorrat):
## id (siehe WorldObjects) -> {"amount": int, "since": int, "gone": bool}
## amount = Vorrat in Runde since; danach waechst er ggf. nach (resource_amount()).
var resources: Dictionary = {}


static func new_game(names: Array, start_cells: Array, steps_per_turn: int, p_map_id: String = "",
		p_settings: Dictionary = {}) -> GameState:
	assert(names.size() == start_cells.size())
	var s := GameState.new()
	s.map_id = p_map_id
	s.settings = p_settings.duplicate(true)
	for i in names.size():
		s.players.append({
			"id": "p%d" % (i + 1),
			"name": str(names[i]),
			"pos": start_cells[i],
			"steps_left": steps_per_turn if i == 0 else 0,
			"inv": ResourceConfig.empty_inventory(),
			"quests": [],
		})
	return s


func current() -> Dictionary:
	return players[current_player]


func occupied_cells(except_player: int = -1) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for i in players.size():
		if i != except_player:
			cells.append(players[i]["pos"])
	return cells


## Aktueller Vorrat eines Objekts (0, wenn gefaellt/leer). Nachwachsen wird
## hier ausgerechnet, damit niemand jede Runde ueber alle Objekte laufen muss.
func resource_amount(id: String, kind: String) -> int:
	var full: int = ResourceConfig.stock(kind)
	if not resources.has(id):
		return full
	var r: Dictionary = resources[id]
	if r["gone"]:
		return 0
	var amount: int = r["amount"]
	if ResourceConfig.regrows(kind):
		amount += (round_number - int(r["since"])) / ResourceConfig.REGROW_ROUNDS
	return mini(amount, full)


## Aktuelle Jahreszeit (Terrain.SPRING..WINTER) oder -1 ohne Jahreszeiten.
func season() -> int:
	return Terrain.season_for(round_number, int(settings.get("season_length", 0)))


func year() -> int:
	return Terrain.year_for(round_number, int(settings.get("season_length", 0)))


## Haerte des aktuellen (bzw. naechsten) Winters: 0 mild, 1 normal, 2 hart.
func winter_level() -> int:
	return Terrain.winter_level_for(int(settings.get("map", {}).get("seed", 0)), year())


func is_gone(id: String) -> bool:
	return resources.has(id) and resources[id]["gone"]


func duplicate_state() -> GameState:
	return GameState.from_dict(to_dict())


func to_dict() -> Dictionary:
	var ps := []
	for p in players:
		ps.append({
			"id": p["id"],
			"name": p["name"],
			"pos": [p["pos"].x, p["pos"].y],
			"steps_left": p["steps_left"],
			"inv": p["inv"].duplicate(),
			"quests": p.get("quests", []).duplicate(),
		})
	return {
		"version": FORMAT_VERSION,
		"map_id": map_id,
		"settings": settings.duplicate(true),
		"round": round_number,
		"current_player": current_player,
		"players": ps,
		"history": history.duplicate(true),
		"resources": resources.duplicate(true),
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.map_id = str(d.get("map_id", ""))
	var raw_settings = d.get("settings", {})
	s.settings = raw_settings if raw_settings is Dictionary else {}
	s.round_number = int(d.get("round", 1))
	s.current_player = int(d.get("current_player", 0))
	for p in d.get("players", []):
		s.players.append({
			"id": str(p["id"]),
			"name": str(p["name"]),
			"pos": Vector2i(int(p["pos"][0]), int(p["pos"][1])),
			"steps_left": int(p["steps_left"]),
			"inv": _read_inventory(p.get("inv", {})),
			"quests": Array(p.get("quests", [])).map(func(q): return str(q)),
		})
	var res: Dictionary = d.get("resources", {})
	for id in res:
		var r: Dictionary = res[id]
		s.resources[str(id)] = {
			"amount": int(r.get("amount", 0)),
			"since": int(r.get("since", 1)),
			"gone": bool(r.get("gone", false)),
		}
	for m in d.get("history", []):
		s.history.append(GameRules.normalize_move(m))
	return s


static func _read_inventory(raw: Dictionary) -> Dictionary:
	var inv := ResourceConfig.empty_inventory()
	for item in inv:
		inv[item] = int(raw.get(item, 0))
	return inv


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


static func from_json(text: String) -> GameState:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return from_dict(parsed)
