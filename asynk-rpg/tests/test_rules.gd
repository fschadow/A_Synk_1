extends SceneTree
## Tests fuer die reine Spiellogik (ohne Grafik). Ausfuehren mit:
##   godot --headless --path asynk-rpg -s res://tests/test_rules.gd
## Beendet sich mit Code 0, wenn alles passt, sonst 1.

var _failures := 0
var _checks := 0


func _init() -> void:
	test_pathfinding()
	test_move_and_turn_order()
	test_invalid_moves()
	test_serialization_and_replay()
	test_harvest()
	test_harvest_limits_and_regrow()
	test_reachable()
	test_simple_ai()
	print("%d Checks, %d Fehler" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FEHLER: ", what)


## Kleine Karte: Rechteck 0..5 x 0..5 ohne das Feld (2,2).
func small_map() -> HexMap:
	var cells := []
	for x in 6:
		for y in 6:
			if Vector2i(x, y) != Vector2i(2, 2):
				cells.append(Vector2i(x, y))
	return HexMap.from_cells(cells)


func new_state() -> GameState:
	return GameState.new_game(["A", "B"], [Vector2i(0, 0), Vector2i(5, 5)], GameRules.STEPS_PER_TURN, "test")


func test_pathfinding() -> void:
	var m := small_map()
	var p := m.find_path(Vector2i(0, 0), Vector2i(3, 3))
	check(p.size() == 3 or p.size() == 4, "Weg (0,0)->(3,3) hat sinnvolle Laenge: %s" % [p])
	check(not p.has(Vector2i(2, 2)), "Weg meidet Loch (2,2)")
	check(p[-1] == Vector2i(3, 3), "Weg endet am Ziel")
	var prev := Vector2i(0, 0)
	for c in p:
		check(m.are_neighbors(prev, c), "Schritte sind Nachbarn")
		prev = c
	check(m.find_path(Vector2i(0, 0), Vector2i(9, 9)).is_empty(), "Kein Weg ausserhalb der Karte")
	check(m.find_path(Vector2i(0, 0), Vector2i(1, 0), [Vector2i(1, 0)]).is_empty(), "Besetztes Ziel nicht erreichbar")
	check(m.find_path(Vector2i(0, 0), Vector2i(5, 5), [], 2).is_empty(), "max_steps begrenzt die Suche")


func test_move_and_turn_order() -> void:
	var m := small_map()
	var s := new_state()
	check(s.current_player == 0 and s.current()["steps_left"] == 4, "A beginnt mit 4 Schritten")
	var mv := GameRules.make_move_to(s, m, Vector2i(2, 0))
	check(not mv.is_empty(), "A kann 2 Felder weit gehen")
	check(GameRules.validate(s, m, mv) == "", "Zug ist gueltig")
	GameRules.apply(s, mv)
	check(s.players[0]["pos"] == Vector2i(2, 0), "A steht auf (2,0)")
	check(s.players[0]["steps_left"] == 2, "A hat noch 2 Schritte")
	check(GameRules.make_move_to(s, m, Vector2i(5, 0)).is_empty(), "3 Felder geht nicht mehr")
	GameRules.apply(s, GameRules.make_end_turn(s))
	check(s.current_player == 1 and s.round_number == 1, "B ist dran, noch Runde 1")
	check(s.players[1]["steps_left"] == 4 and s.players[0]["steps_left"] == 0, "Schritte wurden weitergegeben")
	GameRules.apply(s, GameRules.make_end_turn(s))
	check(s.current_player == 0 and s.round_number == 2, "Wieder A, Runde 2")
	check(s.history.size() == 3, "3 Zuege im Verlauf")


func test_invalid_moves() -> void:
	var m := small_map()
	var s := new_state()
	var wrong_player := {"type": "end_turn", "player": 1, "round": 1}
	check(GameRules.validate(s, m, wrong_player) != "", "B darf nicht ziehen, wenn A dran ist")
	var jump := {"type": "move", "player": 0, "round": 1, "path": [[3, 0]]}
	check(GameRules.validate(s, m, jump) != "", "Springen ist verboten")
	var hole := {"type": "move", "player": 0, "round": 1, "path": [[1, 1], [2, 2]]}
	check(GameRules.validate(s, m, hole) != "", "Loch ist nicht begehbar")
	var too_far := {"type": "move", "player": 0, "round": 1, "path": [[1, 0], [2, 0], [3, 0], [4, 0], [5, 0]]}
	check(GameRules.validate(s, m, too_far) != "", "Mehr als 4 Schritte verboten")
	var old_round := {"type": "end_turn", "player": 0, "round": 7}
	check(GameRules.validate(s, m, old_round) != "", "Zug aus falscher Runde verboten")
	s.players[1]["pos"] = Vector2i(1, 0)
	var onto := {"type": "move", "player": 0, "round": 1, "path": [[1, 0]]}
	check(GameRules.validate(s, m, onto) != "", "Feld mit Figur ist besetzt")


func test_serialization_and_replay() -> void:
	var m := small_map()
	var s := new_state()
	var start_json := s.to_json()
	GameRules.apply(s, GameRules.make_move_to(s, m, Vector2i(1, 1)))
	GameRules.apply(s, GameRules.make_end_turn(s))
	GameRules.apply(s, GameRules.make_move_to(s, m, Vector2i(4, 4)))

	# Rundreise durch JSON-Text, wie spaeter ueber eine Drive-Datei.
	var text := s.to_json()
	var back := GameState.from_json(text)
	check(back != null, "JSON laesst sich wieder einlesen")
	check(back.to_dict() == s.to_dict(), "Spielstand ueberlebt JSON unveraendert")
	check(back.players[1]["pos"] == Vector2i(4, 4), "Position korrekt gelesen")

	# Nur die Zugliste verschicken und auf dem Startstand nachspielen.
	var moves = JSON.parse_string(JSON.stringify(s.history))
	var replayed := GameState.from_json(start_json)
	check(GameRules.replay(replayed, m, moves) == "", "Zuege lassen sich nachspielen")
	check(replayed.to_dict() == s.to_dict(), "Nachgespielter Stand ist identisch")
	check(GameRules.replay(GameState.from_json(start_json), m, [moves[2]]) != "", "Zug in falscher Reihenfolge wird abgelehnt")


## Objekte auf der kleinen Karte: Apfelbaum + Stein auf (1,0), Pfuetze auf (0,1).
func small_objects() -> WorldObjects:
	return WorldObjects.from_dict({
		"1,0,L": ResourceConfig.KIND_TREE_APPLE,
		"1,0,R": ResourceConfig.KIND_STONE,
		"0,1,T": ResourceConfig.KIND_PUDDLE,
	})


func run_action(s: GameState, m: HexMap, o: WorldObjects, cell: Vector2i, action: String) -> String:
	var plan := GameRules.make_action_at(s, m, o, cell, action)
	if plan.has("error"):
		return plan["error"]
	for mv in plan["moves"]:
		var err := GameRules.validate(s, m, mv, o)
		if err != "":
			return err
		GameRules.apply(s, mv)
	return ""


func test_harvest() -> void:
	var m := small_map()
	var o := small_objects()
	var s := new_state()
	# Hinlaufen (1 Schritt) + Sammeln (1 Schritt) am Apfelbaum.
	check(run_action(s, m, o, Vector2i(1, 0), ResourceConfig.ACT_COLLECT) == "", "Sammeln am Apfelbaum geht")
	var inv: Dictionary = s.current()["inv"]
	check(inv[ResourceConfig.AESTE] == 1 and inv[ResourceConfig.OBST] == 1, "Sammeln gibt Ast + Obst")
	check(s.current()["steps_left"] == 2, "Laufen + Sammeln kostet 2 Schritte")
	check(s.resource_amount("1,0,L", ResourceConfig.KIND_TREE_APPLE) == 2, "Vorrat sinkt auf 2")
	# Stein abbauen auf demselben Feld (kein Laufen).
	check(run_action(s, m, o, Vector2i(1, 0), ResourceConfig.ACT_MINE) == "", "Mine geht")
	check(s.current()["inv"][ResourceConfig.STEIN] == 1, "Mine gibt Stein")
	# Faellen: Holz, Baum weg.
	check(run_action(s, m, o, Vector2i(1, 0), ResourceConfig.ACT_FELL) == "", "Faellen geht")
	check(s.current()["inv"][ResourceConfig.HOLZ] == ResourceConfig.FELL_WOOD, "Faellen gibt Holz")
	check(s.is_gone("1,0,L"), "Baum ist nach dem Faellen weg")
	check(run_action(s, m, o, Vector2i(1, 0), ResourceConfig.ACT_COLLECT) != "", "Gefaellter Baum: kein Sammeln mehr")
	check(s.current()["steps_left"] == 0, "Alle Schritte verbraucht")
	# Falsche Faehigkeit / leeres Feld
	var s2 := new_state()
	check(run_action(s2, m, o, Vector2i(0, 1), ResourceConfig.ACT_MINE) != "", "Keine Steine auf der Pfuetze")
	check(run_action(s2, m, o, Vector2i(3, 3), ResourceConfig.ACT_COLLECT) != "", "Nichts zu sammeln auf leerem Feld")
	check(run_action(s2, m, o, Vector2i(0, 1), ResourceConfig.ACT_FISH) == "", "Fischen auf Pfuetze geht")
	check(run_action(s2, m, o, Vector2i(0, 1), ResourceConfig.ACT_FISH) != "", "Pfuetze ist nach 1 Fisch leer")
	# Gefaelschter Zug: falsche Objektart
	var fake := {"type": GameRules.TYPE_HARVEST, "player": 0, "round": 1, "action": ResourceConfig.ACT_MINE,
		"target": "0,0,L", "kind": ResourceConfig.KIND_STONE}
	check(GameRules.validate(new_state(), m, fake, o) != "", "Abbau ohne Objekt wird abgelehnt")
	# Spielstand mit Rohstoffen ueberlebt JSON
	var copy := GameState.from_json(s.to_json())
	check(copy.is_gone("1,0,L") and copy.players[0]["inv"][ResourceConfig.HOLZ] == ResourceConfig.FELL_WOOD,
		"Rohstoffe und Vorrat werden gespeichert")
	var old_save := GameState.from_dict({"players": [{"id": "p1", "name": "A", "pos": [0, 0], "steps_left": 4}]})
	check(old_save.players[0]["inv"][ResourceConfig.HOLZ] == 0, "Alter Spielstand ohne Inventar laedt")


func end_turns(s: GameState, n: int) -> void:
	for i in n:
		GameRules.apply(s, GameRules.make_end_turn(s))


func test_harvest_limits_and_regrow() -> void:
	var m := small_map()
	var o := small_objects()
	var s := new_state()
	# Stein 3x abbauen -> weg, waechst nicht nach.
	s.players[0]["pos"] = Vector2i(1, 0)
	for i in 3:
		s.players[0]["steps_left"] = 4
		check(run_action(s, m, o, Vector2i(1, 0), ResourceConfig.ACT_MINE) == "", "Stein abbauen %d" % (i + 1))
	check(s.is_gone("1,0,R"), "Leerer Steinhaufen verschwindet")
	end_turns(s, 2 * ResourceConfig.REGROW_ROUNDS * 2)
	check(s.is_gone("1,0,R"), "Stein waechst nicht nach")
	# Baum leer sammeln, dann waechst er nach.
	var t := new_state()
	t.players[0]["pos"] = Vector2i(1, 0)
	for i in 3:
		t.players[0]["steps_left"] = 4
		run_action(t, m, o, Vector2i(1, 0), ResourceConfig.ACT_COLLECT)
	check(t.resource_amount("1,0,L", ResourceConfig.KIND_TREE_APPLE) == 0, "Baum leer gesammelt")
	check(run_action(t, m, o, Vector2i(1, 0), ResourceConfig.ACT_COLLECT) != "", "Leerer Baum: nichts zu sammeln")
	end_turns(t, 2 * ResourceConfig.REGROW_ROUNDS)  # 2 Spieler -> REGROW_ROUNDS Runden
	check(t.resource_amount("1,0,L", ResourceConfig.KIND_TREE_APPLE) == 1, "Baum waechst nach %d Runden um 1 nach" % ResourceConfig.REGROW_ROUNDS)
	end_turns(t, 2 * ResourceConfig.REGROW_ROUNDS * 10)
	check(t.resource_amount("1,0,L", ResourceConfig.KIND_TREE_APPLE) == 3, "Nachwachsen hoert beim Startvorrat auf")
	# Tragegrenze
	var u := new_state()
	u.players[0]["pos"] = Vector2i(1, 0)
	u.players[0]["inv"][ResourceConfig.STEIN] = ResourceConfig.CARRY_LIMIT
	check(run_action(u, m, o, Vector2i(1, 0), ResourceConfig.ACT_MINE).begins_with("Du kannst nicht mehr tragen"), "Tragegrenze greift")
	u.players[0]["inv"][ResourceConfig.AESTE] = ResourceConfig.CARRY_LIMIT
	check(run_action(u, m, o, Vector2i(1, 0), ResourceConfig.ACT_COLLECT) == "", "Sammeln geht, solange Obst noch Platz hat")
	check(u.players[0]["inv"][ResourceConfig.AESTE] == ResourceConfig.CARRY_LIMIT, "Aeste bleiben bei der Grenze")


func test_reachable() -> void:
	var m := small_map()
	var cells := m.reachable(Vector2i(0, 0), [], 1)
	check(cells[0] == Vector2i(0, 0), "reachable: Startfeld zuerst")
	check(cells.size() == 1 + m.neighbors(Vector2i(0, 0)).size(), "reachable(1): Start + Nachbarn")
	check(not m.reachable(Vector2i(0, 0)).has(Vector2i(2, 2)), "reachable: Loch ist nicht dabei")
	check(m.reachable(Vector2i(0, 0)).size() == m.cell_count(), "reachable: ganze Karte zusammenhaengend")


func test_simple_ai() -> void:
	var m := small_map()
	var o := small_objects()
	var s := new_state()
	# Die KI spielt einen ganzen Zug: sammelt, bis die Schritte alle sind.
	var rounds := 0
	while rounds < 10:
		rounds += 1
		var moves := SimpleAI.next_moves(s, m, o)
		if moves.is_empty():
			break
		for mv in moves:
			check(GameRules.validate(s, m, mv, o) == "", "KI-Zug ist gueltig: %s" % mv)
			check(mv.get("action", "") != ResourceConfig.ACT_FELL, "KI faellt keine Baeume")
			GameRules.apply(s, mv)
	check(s.current()["steps_left"] < ResourceConfig.ACTION_STEP_COST, "KI hat ihre Schritte genutzt")
	var total := 0
	for item in s.current()["inv"]:
		total += s.current()["inv"][item]
	check(total > 0, "KI hat etwas gesammelt (%d)" % total)
	for id in s.resources:
		check(not s.resources[id]["gone"] or o.kind(id) == ResourceConfig.KIND_STONE or o.kind(id) == ResourceConfig.KIND_PUDDLE,
			"KI hat keinen Baum gefaellt (%s)" % id)
	# Nichts in Reichweite: leere Liste
	var lonely := GameState.new_game(["A", "B"], [Vector2i(5, 0), Vector2i(5, 5)], GameRules.STEPS_PER_TURN, "test")
	var nothing := WorldObjects.from_dict({})
	check(SimpleAI.next_moves(lonely, m, nothing).is_empty(), "KI ohne Rohstoffe: Zug beenden")
