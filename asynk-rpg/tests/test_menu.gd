extends Node
## Integrationstest fuer Menue, lokale Lobby und Spielstaende:
## Menue -> Neues Spiel (Lobby: Mensch + Hotseat-Spieler + KI) -> Spiel, die KI
## spielt ihren Zug -> Hauptmenue -> Weiterspielen -> Spiel laden -> Loeschen.
## Ausfuehren mit:
##   godot --headless --path asynk-rpg res://tests/test_menu.tscn
## Nutzt einen eigenen Spielstand-Ordner (user://test_saves_menu).

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
	for i in 60:
		await get_tree().process_frame
		var cur := get_tree().current_scene
		if cur and cur.scene_file_path == path:
			# Session startet per call_deferred: noch ein paar Frames abwarten.
			for j in 3:
				await get_tree().process_frame
			return cur
	return null


func wait_until(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _run() -> void:
	# Dieser Test-Knoten darf beim Szenenwechsel nicht mit entfernt werden.
	get_tree().current_scene = null
	SaveStore.dir = "user://test_saves_menu"
	SaveStore.clear_all()
	var old_season = Net.load_setting("season_length", Net.DEFAULT_SEASON_LENGTH)

	# 1. Menue ohne Spielstand: "Weiterspielen" und "Spiel laden" ausgeblendet.
	get_tree().change_scene_to_file(Glob.MENU_SCENE)
	var menu := await _wait_for_scene(Glob.MENU_SCENE)
	check(menu != null, "Menue wurde nicht geladen")
	var b := _buttons(menu)
	for t in ["Weiterspielen", "Neues Spiel", "Spiel laden", "LAN-Spiel", "Google Drive verbinden", "Einstellungen", "Zurück"]:
		check(b.has(t), "Button fehlt: " + t)
	check(not b["Weiterspielen"].visible and not b["Spiel laden"].visible, "Weiterspielen/Laden sichtbar ohne Spielstand")
	b["Google Drive verbinden"].pressed.emit()
	check(b["Zurück"].is_visible_in_tree(), "Drive-Seite nicht sichtbar")
	b["Zurück"].pressed.emit()
	check(b["Neues Spiel"].is_visible_in_tree(), "Zurueck zur Hauptseite klappt nicht")

	# 2. Neues Spiel -> lokale Lobby
	b["Neues Spiel"].pressed.emit()
	var lobby_menu := await _wait_for_scene(Glob.LAN_SCENE)
	check(lobby_menu != null, "Lobby wurde nicht geladen")
	check(Net.is_local() and Net.players().size() == 1, "Lokale Lobby mit einem Spieler")
	Net.add_local_player("Ben")
	Net.add_ai_player()
	Net.set_season_length(5)
	check(Net.players().size() == 3 and Net.is_ai(2), "Lobby: 2 Menschen + 1 KI")
	b = _buttons(lobby_menu)
	check(b.has("Spiel starten") and not b["Spiel starten"].disabled, "Start-Knopf aktiv")
	b["Spiel starten"].pressed.emit()

	# 3. Spiel: Menschen beenden, KI spielt selbst
	var game := await _wait_for_scene(Glob.GAME_SCENE)
	check(game != null, "Spielszene wurde nicht geladen")
	var session := get_tree().get_first_node_in_group(GameSession.GROUP) as GameSession
	check(session != null and session.state != null, "Keine GameSession/kein Spielstand")
	if session == null or session.state == null:
		_finish()
		return
	var s := session.state
	check(s.players.size() == 3 and s.round_number == 1, "Neues Spiel: 3 Spieler, Runde 1")
	check(Net.controls(0) and Net.controls(1) and not Net.controls(2), "Hotseat: beide Menschen hier, KI nicht")
	check(session.request_end_turn(), "Spieler 1 beendet")
	check(session.request_end_turn(), "Spieler 2 (Hotseat) beendet")
	check(not session.request_end_turn(), "Fuer die KI darf man nicht beenden")
	check(await wait_until(func(): return s.round_number == 2, 15.0), "KI hat ihren Zug gespielt -> Runde 2")
	check(SaveStore.has_any(), "Spielstand wurde gespeichert")

	# 4. Zurueck ins Menue, Weiterspielen
	Glob.go_to_menu()
	menu = await _wait_for_scene(Glob.MENU_SCENE)
	b = _buttons(menu)
	check(b["Weiterspielen"].visible and b["Spiel laden"].visible, "Weiterspielen/Laden da trotz Spielstand?")
	b["Weiterspielen"].pressed.emit()
	await _wait_for_scene(Glob.GAME_SCENE)
	session = get_tree().get_first_node_in_group(GameSession.GROUP) as GameSession
	check(session.state.round_number == 2 and session.state.players.size() == 3, "Weiterspielen laedt Runde 2 mit 3 Spielern")
	check(Net.is_local() and Net.is_ai(2) and Net.season_length() == 5, "Lobby-Einstellungen mitgeladen (KI, Jahreszeit)")

	# 5. Spiel laden: Liste, Loeschen
	Glob.go_to_menu()
	await _wait_for_scene(Glob.MENU_SCENE)
	Glob.open_game_menu(Glob.MENU_LOAD)
	lobby_menu = await _wait_for_scene(Glob.LAN_SCENE)
	b = _buttons(lobby_menu)
	check(b.has("Spielen") and b.has("Im LAN hosten") and b.has("Löschen"), "Spielstand-Zeile mit allen Knoepfen")
	check(SaveStore.list().size() == 1, "Genau ein Spielstand in der Liste")
	SaveStore.delete(SaveStore.latest_id())
	check(not SaveStore.has_any(), "Spielstand geloescht")

	Net.save_setting("season_length", old_season)
	_finish()


func _finish() -> void:
	Net.leave()
	SaveStore.clear_all()
	print("Menue-Test: ", "OK" if _failures == 0 else "%d Fehler" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
