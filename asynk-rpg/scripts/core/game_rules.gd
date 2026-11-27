class_name GameRules
extends RefCounted
## Die Spielregeln. Ein Zug ("move") ist ein einfaches Dictionary, das sich
## direkt als JSON speichern und verschicken laesst:
##
##   {"type": "move",     "player": 0, "round": 1, "path": [[x, y], ...]}
##   {"type": "end_turn", "player": 0, "round": 1}
##   {"type": "harvest",  "player": 0, "round": 1, "action": "collect", "target": "x,y,L"}
##   {"type": "join",     "player": 3, "round": 5, "name": "Mia", "pos": [x, y]}
##
## "join": ein neuer Spieler steigt in ein laufendes Spiel ein (nur der Host
## erzeugt diesen Zug). Er kommt ans Ende der Zugreihenfolge.
##
## Abbauen ("harvest"): Die Figur muss auf dem Feld des Objekts stehen; die
## Zahlen dazu stehen in ResourceConfig, die Objekte in WorldObjects.
##
## validate() prueft einen Zug gegen einen Spielstand, apply() fuehrt ihn aus.
## Wer denselben Startstand hat und dieselben Zuege anwendet, landet immer beim
## selben Ergebnis. Darauf baut spaeter der asynchrone Austausch auf.

const STEPS_PER_TURN := 4

const TYPE_MOVE := "move"
const TYPE_END_TURN := "end_turn"
const TYPE_HARVEST := "harvest"
const TYPE_JOIN := "join"
const MAX_PLAYERS := 20


## Baut einen Bewegungszug fuer den aktuellen Spieler zum Zielfeld.
## Liefert {} wenn das Ziel nicht (mit den restlichen Schritten) erreichbar ist.
static func make_move_to(state: GameState, map: HexMap, target: Vector2i) -> Dictionary:
	var me := state.current()
	var cost := cost_func(state, map)
	var path := map.find_path(me["pos"], target, state.occupied_cells(state.current_player), me["steps_left"], cost)
	if path.is_empty():
		return {}
	var total := map.path_cost(path, cost)
	if total > me["steps_left"]:
		return {}
	var p := []
	for c in path:
		p.append([c.x, c.y])
	return {"type": TYPE_MOVE, "player": state.current_player, "round": state.round_number, "path": p, "cost": total}


## Schritte, um ein Feld zu betreten (0 = geht nicht), je nach Gelaende,
## Jahreszeit und Winterhaerte.
static func step_cost(state: GameState, map: HexMap, cell: Vector2i) -> int:
	if not map.is_walkable(cell):
		return 0
	return Terrain.move_cost(map.kind_at(cell), state.season(), state.winter_level())


static func cost_func(state: GameState, map: HexMap) -> Callable:
	var season := state.season()
	var winter := state.winter_level()
	return func(cell: Vector2i) -> int:
		return Terrain.move_cost(map.kind_at(cell), season, winter) if map.is_walkable(cell) else 0


## Von wo aus kann man an diesem Objekt arbeiten? Gewaesser vom Feld selbst
## (falls begehbar) oder einem Nachbarfeld, alles andere nur darauf stehend.
static func work_cells(state: GameState, map: HexMap, id: String) -> Array[Vector2i]:
	var cell := WorldObjects.id_cell(id)
	var out: Array[Vector2i] = []
	if WorldObjects.id_slot(id) != WorldObjects.SLOT_WATER:
		out.append(cell)
		return out
	if step_cost(state, map, cell) > 0:
		out.append(cell)
	for n in map.neighbors(cell):
		if step_cost(state, map, n) > 0:
			out.append(n)
	return out


## Findet auf einem Feld das Objekt, an dem diese Aktion gerade moeglich ist
## (passende Art und noch Vorrat). Liefert "" wenn keins.
static func find_target(state: GameState, objects: WorldObjects, cell: Vector2i, action: String) -> String:
	if objects == null:
		return ""
	for id in objects.ids_at(cell):
		var kind := objects.kind(id)
		if Terrain.is_water(kind) and not Terrain.can_fish(kind, state.season(), state.winter_level()):
			continue
		if ResourceConfig.action_fits(action, kind) and not state.is_gone(id) 				and (action == ResourceConfig.ACT_FELL or state.resource_amount(id, kind) > 0):
			return id
	return ""


## Baut die Zuege fuer "mit Faehigkeit auf ein Feld tippen": falls noetig erst
## hinlaufen, dann abbauen. Liefert {"moves": [...]} oder {"error": "..."}.
static func make_action_at(state: GameState, map: HexMap, objects: WorldObjects, cell: Vector2i, action: String) -> Dictionary:
	var target := find_target(state, objects, cell, action)
	if target == "":
		return {"error": _nothing_here(action)}
	var moves: Array[Dictionary] = []
	var me := state.current()
	var walk_steps := 0
	var spots := work_cells(state, map, target)
	if not spots.has(me["pos"]):
		# Zum guenstigsten Feld laufen, von dem aus man arbeiten kann.
		var best := {}
		for spot in spots:
			var w := make_move_to(state, map, spot)
			if not w.is_empty() and (best.is_empty() or w["cost"] < best["cost"]):
				best = w
		if best.is_empty():
			return {"error": "Feld nicht erreichbar"}
		walk_steps = best["cost"]
		moves.append(best)
	if walk_steps + ResourceConfig.ACTION_STEP_COST > me["steps_left"]:
		return {"error": "Nicht genug Schritte zum Hinlaufen und Abbauen"}
	var harvest := {"type": TYPE_HARVEST, "player": state.current_player, "round": state.round_number,
		"action": action, "target": target, "kind": objects.kind(target)}
	# Abbau gegen den Stand NACH dem Hinlaufen pruefen (z. B. Tragegrenze).
	var after := state.duplicate_state()
	for m in moves:
		apply(after, m)
	var err := validate(after, map, harvest, objects)
	if err != "":
		return {"error": err}
	moves.append(harvest)
	return {"moves": moves}


static func _nothing_here(action: String) -> String:
	match action:
		ResourceConfig.ACT_COLLECT:
			return "Hier gibt es nichts zu sammeln"
		ResourceConfig.ACT_FELL:
			return "Hier steht kein Baum"
		ResourceConfig.ACT_MINE:
			return "Hier gibt es keine Steine"
		ResourceConfig.ACT_FISH:
			return "Hier gibt es keine Fische"
	return "Hier gibt es nichts"


static func make_end_turn(state: GameState) -> Dictionary:
	return {"type": TYPE_END_TURN, "player": state.current_player, "round": state.round_number}


## Gibt "" zurueck, wenn der Zug erlaubt ist, sonst eine Fehlermeldung.
## objects wird nur fuer Abbau-Zuege gebraucht.
static func validate(state: GameState, map: HexMap, move: Dictionary, objects: WorldObjects = null) -> String:
	if move.get("type") == TYPE_JOIN:
		return _validate_join(state, map, move)
	var player := int(move.get("player", -1))
	if player != state.current_player:
		return "Spieler %d ist nicht am Zug" % (player + 1)
	if int(move.get("round", -1)) != state.round_number:
		return "Zug gehoert zu Runde %s, aktuell ist Runde %d" % [move.get("round"), state.round_number]
	match move.get("type"):
		TYPE_END_TURN:
			return ""
		TYPE_MOVE:
			var path: Array = move.get("path", [])
			if path.is_empty():
				return "Leerer Weg"
			var me := state.players[player]
			var blocked := state.occupied_cells(player)
			var prev: Vector2i = me["pos"]
			var total := 0
			for raw in path:
				var c := _cell(raw)
				if not map.are_neighbors(prev, c):
					return "Weg springt von %s nach %s" % [prev, c]
				var step := step_cost(state, map, c)
				if step <= 0:
					return _blocked_reason(state, map, c)
				if blocked.has(c):
					return "Feld %s ist besetzt" % c
				total += step
				prev = c
			if total > me["steps_left"]:
				return "Nicht genug Schritte (%d nötig, %d übrig)" % [total, me["steps_left"]]
			if move.has("cost") and int(move["cost"]) != total:
				return "Schrittkosten passen nicht"
			return ""
		TYPE_HARVEST:
			return _validate_harvest(state, map, move, objects)
		_:
			return "Unbekannter Zugtyp %s" % move.get("type")


## Zug fuer einen neuen Spieler, der auf `pos` startet.
static func make_join(state: GameState, player_name: String, pos: Vector2i) -> Dictionary:
	return {"type": TYPE_JOIN, "player": state.players.size(), "round": state.round_number,
		"name": player_name, "pos": [pos.x, pos.y]}


static func _validate_join(state: GameState, map: HexMap, move: Dictionary) -> String:
	if int(move.get("player", -1)) != state.players.size():
		return "Falsche Spielernummer fuer neuen Spieler"
	if state.players.size() >= MAX_PLAYERS:
		return "Spiel ist voll (%d Spieler)" % MAX_PLAYERS
	if int(move.get("round", -1)) != state.round_number:
		return "Beitritt gehoert zu einer anderen Runde"
	if str(move.get("name", "")).strip_edges() == "":
		return "Neuer Spieler braucht einen Namen"
	var pos := _cell(move.get("pos", [0, 0]))
	if not map.is_walkable(pos) or state.occupied_cells().has(pos):
		return "Startfeld %s ist nicht frei" % pos
	return ""


static func _blocked_reason(state: GameState, map: HexMap, c: Vector2i) -> String:
	var k := map.kind_at(c)
	if (k == Terrain.POND or k == Terrain.LAKE or k == Terrain.SHALLOW) and state.season() != Terrain.SUMMER:
		return "Zu kalt zum Schwimmen – nur im Sommer"
	if k == Terrain.DEEP or k == Terrain.OCEAN:
		return "Zu tief zum Schwimmen"
	return "Feld %s ist nicht begehbar" % c


static func _validate_harvest(state: GameState, map: HexMap, move: Dictionary, objects: WorldObjects) -> String:
	if objects == null:
		return "Keine Kartenobjekte bekannt"
	var me := state.players[int(move["player"])]
	var target := str(move.get("target", ""))
	var action := str(move.get("action", ""))
	var kind := objects.kind(target)
	if kind == "" or not ResourceConfig.action_fits(action, kind):
		return _nothing_here(action)
	if str(move.get("kind", "")) != kind:
		return "Objektart passt nicht zur Karte"
	if not work_cells(state, map, target).has(me["pos"]):
		if WorldObjects.id_slot(target) == WorldObjects.SLOT_WATER:
			return "Die Figur muss am Ufer stehen"
		return "Die Figur muss auf dem Feld stehen"
	if Terrain.is_water(kind) and not Terrain.can_fish(kind, state.season(), state.winter_level()):
		return "Zugefroren – hier kann man nicht fischen"
	if me["steps_left"] < ResourceConfig.ACTION_STEP_COST:
		return "Keine Schritte mehr übrig"
	if state.is_gone(target):
		return _nothing_here(action)
	if action != ResourceConfig.ACT_FELL and state.resource_amount(target, kind) <= 0:
		return "Leer, wächst in einigen Runden nach" if ResourceConfig.regrows(kind) else "Leer"
	var y := ResourceConfig.yields(action, kind, state.season())
	var room := false
	for item in y:
		if me["inv"][item] < ResourceConfig.CARRY_LIMIT:
			room = true
	if not room:
		return "Du kannst nicht mehr tragen (max. %d)" % ResourceConfig.CARRY_LIMIT
	return ""


## Fuehrt einen (vorher validierten) Zug auf dem Spielstand aus.
static func apply(state: GameState, move: Dictionary) -> void:
	var m := normalize_move(move)
	match m["type"]:
		TYPE_MOVE:
			var me := state.players[m["player"]]
			me["pos"] = _cell(m["path"][-1])
			me["steps_left"] -= int(m["cost"]) if m.has("cost") else m["path"].size()
		TYPE_HARVEST:
			_apply_harvest(state, m)
		TYPE_JOIN:
			state.players.append({
				"id": "p%d" % (state.players.size() + 1),
				"name": m["name"],
				"pos": _cell(m["pos"]),
				"steps_left": 0,
				"inv": ResourceConfig.empty_inventory(),
			})
		TYPE_END_TURN:
			state.players[state.current_player]["steps_left"] = 0
			state.current_player = (state.current_player + 1) % state.players.size()
			if state.current_player == 0:
				state.round_number += 1
			state.players[state.current_player]["steps_left"] = STEPS_PER_TURN
	state.history.append(m)


## Die Objektart steckt in der ID nicht drin, deshalb wird sie beim Erzeugen des
## Zugs mitgespeichert ("kind"), damit apply() ohne WorldObjects auskommt.
static func _apply_harvest(state: GameState, m: Dictionary) -> void:
	var me := state.players[m["player"]]
	var kind: String = m["kind"]
	var target: String = m["target"]
	me["steps_left"] -= ResourceConfig.ACTION_STEP_COST
	var y := ResourceConfig.yields(m["action"], kind, state.season())
	for item in y:
		me["inv"][item] = mini(me["inv"][item] + y[item], ResourceConfig.CARRY_LIMIT)
	if m["action"] == ResourceConfig.ACT_FELL:
		state.resources[target] = {"amount": 0, "since": state.round_number, "gone": true}
		return
	var left := state.resource_amount(target, kind) - 1
	var gone: bool = left <= 0 and not ResourceConfig.regrows(kind)
	state.resources[target] = {"amount": left, "since": state.round_number, "gone": gone}


## Spielt eine Liste von Zuegen auf einem Startstand nach. Bricht beim ersten
## ungueltigen Zug ab und gibt dann dessen Fehler zurueck.
static func replay(state: GameState, map: HexMap, moves: Array, objects: WorldObjects = null) -> String:
	for m in moves:
		var err := validate(state, map, m, objects)
		if err != "":
			return err
		apply(state, m)
	return ""


## Bringt einen Zug in eine einheitliche Form (JSON liefert Zahlen als float).
static func normalize_move(move: Dictionary) -> Dictionary:
	var m := {
		"type": str(move.get("type", "")),
		"player": int(move.get("player", -1)),
		"round": int(move.get("round", -1)),
	}
	if move.has("path"):
		var p := []
		for raw in move["path"]:
			var c := _cell(raw)
			p.append([c.x, c.y])
		m["path"] = p
	for key in ["action", "target", "kind", "name"]:
		if move.has(key):
			m[key] = str(move[key])
	if move.has("pos"):
		var c := _cell(move["pos"])
		m["pos"] = [c.x, c.y]
	if move.has("cost"):
		m["cost"] = int(move["cost"])
	return m


static func path_cells(move: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for raw in move.get("path", []):
		cells.append(_cell(raw))
	return cells


static func _cell(raw) -> Vector2i:
	if raw is Vector2i:
		return raw
	return Vector2i(int(raw[0]), int(raw[1]))
