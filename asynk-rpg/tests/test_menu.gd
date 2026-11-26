extends Node
## Integrationstest fuer das Startmenue: Menue -> Neues Spiel -> Hauptmenue ->
## Weiterspielen. Ausfuehren mit:
##   godot --headless --path asynk-rpg res://tests/test_menu.tscn
## Achtung: ueberschreibt user://savegame.json.

var _failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		printerr("FEHLER: ", what)


func _ready() -> void:
	_run.call_deferred()


func _buttons(root: Node) -> Dictionary:
	var out := {}
	for b in root.find_children("*", "Button", true, false):
		out[b.text] = b
	return out


func _wait_for_scene(path: String) -> Node:
	for i in 30:
		await get_tree().process_frame
		var cur := get_tree().current_scene
		if cur and cur.scene_file_path == path:
			# Session startet per call_deferred: noch ein paar Frames abwarten.
			for j in 3:
				await get_tree().process_frame
			return cur
	return null


func _run() -> void:
	# Dieser Test-Knoten darf beim Szenenwechsel nicht mit entfernt werden.
	get_tree().current_scene = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSession.SAVE_PATH))

	# 1. Menue ohne Spielstand: "Weiterspielen" ausgeblendet.
	get_tree().change_scene_to_file(Glob.MENU_SCENE)
	var menu := await _wait_for_scene(Glob.MENU_SCENE)
	check(menu != null, "Menue wurde nicht geladen")
	var b := _buttons(menu)
	for t in ["Weiterspielen", "Neues Spiel", "Google Drive verbinden", "Einstellungen", "Zurück"]:
		check(b.has(t), "Button fehlt: " + t)
	check(not b["Weiterspielen"].visible, "Weiterspielen sichtbar ohne Spielstand")

	# 2. Drive-Platzhalter oeffnen und zurueck.
	b["Google Drive verbinden"].pressed.emit()
	check(b["Zurück"].is_visible_in_tree(), "Drive-Seite nicht sichtbar")
	b["Zurück"].pressed.emit()
	check(b["Neues Spiel"].is_visible_in_tree(), "Zurueck zur Hauptseite klappt nicht")

	# 3. Neues Spiel -> Spielszene mit frischem Spiel.
	b["Neues Spiel"].pressed.emit()
	var game := await _wait_for_scene(Glob.GAME_SCENE)
	check(game != null, "Spielszene wurde nicht geladen")
	var session := get_tree().get_first_node_in_group(GameSession.GROUP) as GameSession
	check(session != null and session.state != null, "Keine GameSession/kein Spielstand")
	check(session.state.round_number == 1, "Neues Spiel startet nicht in Runde 1")
	session.request_end_turn()
	var player_after := session.state.current_player
	check(GameSession.has_savegame(), "Spielstand wurde nicht gespeichert")

	# 4. Zurueck ins Menue: jetzt mit "Weiterspielen".
	Glob.go_to_menu()
	menu = await _wait_for_scene(Glob.MENU_SCENE)
	b = _buttons(menu)
	check(b["Weiterspielen"].visible, "Weiterspielen fehlt trotz Spielstand")

	# 5. Weiterspielen laedt den Stand (Spieler 2 ist dran).
	b["Weiterspielen"].pressed.emit()
	await _wait_for_scene(Glob.GAME_SCENE)
	session = get_tree().get_first_node_in_group(GameSession.GROUP) as GameSession
	check(session.state.current_player == player_after, "Weiterspielen hat den Spielstand nicht geladen")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSession.SAVE_PATH))
	print("Menue-Test: ", "OK" if _failures == 0 else "%d Fehler" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
