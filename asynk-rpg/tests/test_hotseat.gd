extends Node
## Integrationstest: laedt die echte Spielszene und spielt ein paar Zuege im
## Hotseat-Modus durch (ohne Maus, direkt ueber die GameSession). Ausfuehren mit:
##   godot --headless --path asynk-rpg res://tests/test_hotseat.tscn

var _failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		printerr("FEHLER: ", what)


func _ready() -> void:
	var world: Node = load("res://scenes/node_2d.tscn").instantiate()
	var session: GameSession = world.get_node("GameSession")
	session.autosave = false
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	var s := session.state
	check(s != null and s.players.size() == 2, "Spiel mit 2 Spielern gestartet")
	check(session.map.cell_count() > 1000, "Karte aus der TileMap gelesen (%d Felder)" % session.map.cell_count())
	for p in s.players:
		check(session.map.is_walkable(p["pos"]), "Startfeld %s ist begehbar" % p["pos"])

	var hud = world.get_node("CanvasLayer/TurnHud")
	check(hud.is_blocking(), "Uebergabe-Bildschirm zeigt sich zu Beginn")

	var a1: Node2D = world.get_node("Objects/CharacterBody2D")
	var a2: Node2D = world.get_node("Objects/CharacterBody2D2")
	var agent1 = a1.get_node("HexAgent")
	check(a1.global_position.distance_to(agent1.cell_to_position(s.players[0]["pos"])) < 0.5, "Figur 1 steht auf ihrem Feld")

	# Spieler 1 zieht 2 Felder, Spieler 2 darf in der Zeit nichts.
	var target: Vector2i = s.players[0]["pos"] + Vector2i(2, 0)
	if not session.map.is_walkable(target):
		target = s.players[0]["pos"] + Vector2i(0, 2)
	check(session.request_move_to(target), "Spieler 1 bewegt sich nach %s" % target)
	check(s.players[0]["steps_left"] == 2, "Spieler 1 hat noch 2 Schritte")
	check(not session.submit({"type": "end_turn", "player": 1, "round": 1}), "Spieler 2 darf nicht beenden")

	await get_tree().create_timer(1.0).timeout
	check(a1.global_position.distance_to(agent1.cell_to_position(target)) < 0.5, "Figur 1 ist sichtbar angekommen")

	var p2_before := a2.global_position
	check(session.request_end_turn(), "Spieler 1 beendet den Zug")
	check(s.current_player == 1, "Spieler 2 ist dran")
	check(a2.global_position == p2_before, "Figur 2 hat sich nicht bewegt")
	check(session.request_end_turn(), "Spieler 2 beendet den Zug")
	check(s.current_player == 0 and s.round_number == 2, "Runde 2, Spieler 1")

	# --- Tippen auf die Karte mit "Laufen" (frueher kaputt: ohne Faehigkeit keine Bewegung) ---
	hud._overlay.visible = false
	var ui = world.get_node("CanvasLayer/inGameUi")
	check(Glob.CurStatus == Glob.Status.Nothing, "Laufen ist zu Beginn gewaehlt")
	var from: Vector2i = s.players[0]["pos"]
	var tap_target := from
	for o in HexMap.NEIGHBOR_OFFSETS:
		var c: Vector2i = from + o
		if session.map.is_walkable(c) and not s.occupied_cells(0).has(c):
			tap_target = c
			break
	var terrain: TileMapLayer = session.terrain
	var screen: Vector2 = world.get_canvas_transform() * terrain.to_global(terrain.map_to_local(tap_target))
	world._on_tap(screen)
	check(s.players[0]["pos"] == tap_target, "Tipp auf Nachbarfeld bewegt die Figur (%s -> %s)" % [from, tap_target])
	await get_tree().create_timer(0.6).timeout

	# --- Abbauen in der echten Szene: naechsten Baum suchen, hinlaufen lassen, faellen ---
	var tree_id := ""
	for id in session.objects._kinds:
		if ResourceConfig.TREE_KINDS.has(session.objects.kind(id)):
			var cell := WorldObjects.id_cell(id)
			var path := session.map.find_path(s.players[0]["pos"], cell, s.occupied_cells(0), 2)
			if not path.is_empty() and path.size() <= s.players[0]["steps_left"] - 1:
				tree_id = id
				break
	check(tree_id != "", "Baum in Reichweite gefunden")
	if tree_id != "":
		var cell := WorldObjects.id_cell(tree_id)
		var layer: TileMapLayer = session.objects_left if WorldObjects.id_slot(tree_id) == "L" else session.objects_right
		check(layer.get_cell_source_id(cell) != -1, "Baum ist vor dem Faellen sichtbar")
		check(session.request_action(cell, ResourceConfig.ACT_FELL), "Faellen klappt: " + tree_id)
		check(s.players[0]["inv"][ResourceConfig.HOLZ] == ResourceConfig.FELL_WOOD, "Holz im Inventar")
		await get_tree().create_timer(1.2).timeout
		check(layer.get_cell_source_id(cell) == -1, "Gefaellter Baum ist von der Karte verschwunden")
	var bar = world.get_node("CanvasLayer/ResourceBar")
	check(bar._values[ResourceConfig.HOLZ].text == str(ResourceConfig.FELL_WOOD), "Rohstoffleiste zeigt das Holz")

	# --- Aktionsleiste: Umschalten haengt nicht ---
	for st in [Glob.Status.Mine, Glob.Status.Collect, Glob.Status.Mine, Glob.Status.Nothing, Glob.Status.Fish]:
		ui._buttons[st].button_pressed = true
		var pressed := 0
		for b in ui._buttons.values():
			if b.button_pressed:
				pressed += 1
		check(Glob.CurStatus == st and pressed == 1, "Umschalten auf %s: genau ein Knopf aktiv" % st)

	print("Hotseat-Test: %s" % ("OK" if _failures == 0 else "%d Fehler" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)
