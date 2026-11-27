extends Control
## Zeigt an, wer am Zug ist, wie viele Schritte noch uebrig sind, und hat den
## "Zug beenden"-Knopf. Beim Spielerwechsel auf demselben Geraet (Hotseat)
## erscheint ein Uebergabe-Bildschirm, damit der naechste Spieler bewusst
## uebernimmt. Im LAN-Spiel zusaetzlich: Restzeit des Zuges, wer danach dran
## ist, und ein Pausen-Hinweis, wenn der Spieler am Zug die Verbindung
## verloren hat (der Host entscheidet: warten oder KI).
## Veraendert den Spielstand nur ueber die GameSession.

## "Zur Figur" gedrueckt: die Welt soll die Kamera auf die aktive Figur setzen.
signal focus_requested

var _session: GameSession
var _info: Label
var _clock_label: Label
var _hint: Label
var _end_button: Button
var _panel: PanelContainer
var _overlay: ColorRect
var _overlay_label: Label
var _hint_timer: SceneTreeTimer
var _pause_panel: PanelContainer
var _pause_label: Label
var _wait_button: Button
var _ai_button: Button
## Host hat "Weiter warten" gewaehlt (fuer diesen Spieler).
var _waiting_for := -1
## Zuletzt angezeigter Spieler am Uebergabe-Bildschirm (LAN-Hotseat).
var _last_local := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_session = get_tree().get_first_node_in_group(GameSession.GROUP) as GameSession
	if _session:
		_session.game_started.connect(_refresh)
		_session.move_applied.connect(func(_m, s): _refresh(s))
		_session.turn_started.connect(_on_turn_started)
		_session.move_rejected.connect(_show_hint)
	Net.lobby_changed.connect(_on_lobby_changed)


func _on_lobby_changed() -> void:
	if _session and _session.state:
		_refresh(_session.state)


## true, solange der Uebergabe-Bildschirm offen ist: dann keine Eingabe in die Welt.
func is_blocking() -> bool:
	return _overlay.visible


## true, wenn der Bildschirmpunkt auf diesem HUD liegt (wichtig fuer Touch,
## wo es kein "Maus ist ueber dem Knopf" gibt).
func covers(screen_pos: Vector2) -> bool:
	return _overlay.visible or _panel.get_global_rect().has_point(screen_pos) \
		or (_pause_panel.visible and _pause_panel.get_global_rect().has_point(screen_pos))


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.position = Vector2(-16, 16)
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_info = Label.new()
	box.add_child(_info)
	_clock_label = Label.new()
	_clock_label.visible = false
	box.add_child(_clock_label)
	_end_button = Button.new()
	_end_button.text = "Zug beenden"
	_end_button.pressed.connect(func(): _session.request_end_turn())
	box.add_child(_end_button)
	var focus := Button.new()
	focus.text = "Zur Figur"
	focus.pressed.connect(func(): focus_requested.emit())
	focus.mouse_entered.connect(func(): Glob.MouseOnUI = true)
	box.add_child(focus)
	var menu := Button.new()
	menu.text = "Hauptmenü"
	menu.flat = true
	menu.pressed.connect(func(): Glob.go_to_menu())
	menu.mouse_entered.connect(func(): Glob.MouseOnUI = true)
	box.add_child(menu)
	_hint = Label.new()
	_hint.modulate = Color(1, 0.75, 0.4)
	box.add_child(_hint)
	_panel.mouse_entered.connect(func(): Glob.MouseOnUI = true)
	_panel.mouse_exited.connect(func(): Glob.MouseOnUI = false)
	_end_button.mouse_entered.connect(func(): Glob.MouseOnUI = true)

	# --- Pause (LAN: Spieler am Zug hat keine Verbindung) ---
	_pause_panel = PanelContainer.new()
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pause_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause_panel.position.y = 16
	_pause_panel.visible = false
	add_child(_pause_panel)
	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 8)
	_pause_panel.add_child(pbox)
	_pause_label = Label.new()
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.add_theme_font_size_override("font_size", 20)
	pbox.add_child(_pause_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	pbox.add_child(buttons)
	_wait_button = Button.new()
	_wait_button.text = "Weiter warten"
	_wait_button.pressed.connect(func():
		_waiting_for = _session.state.current_player
		_refresh(_session.state))
	buttons.add_child(_wait_button)
	_ai_button = Button.new()
	_ai_button.text = "KI übernimmt"
	_ai_button.pressed.connect(func(): Net.set_ai(_session.state.current_player, true))
	buttons.add_child(_ai_button)

	# --- Uebergabe-Bildschirm (Hotseat) ---
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.8)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var obox := VBoxContainer.new()
	obox.add_theme_constant_override("separation", 24)
	center.add_child(obox)
	_overlay_label = Label.new()
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 32)
	obox.add_child(_overlay_label)
	var go := Button.new()
	go.text = "Los geht's"
	go.add_theme_font_size_override("font_size", 28)
	go.pressed.connect(func(): _overlay.visible = false)
	obox.add_child(go)


func _process(_delta: float) -> void:
	var left := Net.time_left()
	_clock_label.visible = left >= 0.0
	if left >= 0.0:
		var secs := int(ceil(left))
		_clock_label.text = "Zeit: %d:%02d%s" % [secs / 60, secs % 60, "" if Net.clock_running() else " (angehalten)"]
		_clock_label.modulate = Color(1, 0.55, 0.45) if left <= 10.0 and Net.clock_running() else Color.WHITE


func _refresh(state: GameState) -> void:
	var me := state.current()
	var who: String = me["name"]
	if Net.is_active():
		if Net.controls(state.current_player):
			who += " (du)"
		elif Net.is_ai(state.current_player):
			who += " (KI)"
		var next := (state.current_player + 1) % state.players.size()
		_info.text = "Runde %d · %s ist dran\nNoch %d Schritte · danach: %s" % [
			state.round_number, who, me["steps_left"], state.players[next]["name"]]
	else:
		_info.text = "Runde %d · %s ist dran\nNoch %d Schritte" % [state.round_number, who, me["steps_left"]]
	_end_button.disabled = not Net.controls(state.current_player) or Net.is_paused(state)
	_refresh_pause(state)


func _refresh_pause(state: GameState) -> void:
	var paused := Net.is_paused(state)
	_pause_panel.visible = paused
	if not paused:
		_waiting_for = -1
		return
	var who: String = state.current()["name"]
	var decided := _waiting_for == state.current_player
	if Net.is_host():
		_pause_label.text = ("Warte auf %s …" if decided else "%s hat die Verbindung verloren.\nWarten oder die KI spielen lassen?") % who
	else:
		_pause_label.text = "%s hat die Verbindung verloren.\nDer Host entscheidet: warten oder KI." % who
	_wait_button.visible = Net.is_host() and not decided
	_ai_button.visible = Net.is_host()


func _on_turn_started(player_index: int, state: GameState) -> void:
	_refresh(state)
	_hint.text = ""
	var show := false
	if Net.is_active():
		# Nur wenn auf DIESEM Geraet mehrere Spieler sitzen und jetzt ein anderer dran ist.
		if Net.controls(player_index):
			show = Net.local_player_count() > 1 and player_index != _last_local
			_last_local = player_index
	else:
		show = state.players.size() > 1
	if show:
		_overlay_label.text = "%s ist dran\nGib das Gerät weiter." % state.current()["name"]
		_overlay.visible = true


func _show_hint(reason: String) -> void:
	_hint.text = reason
	_hint_timer = get_tree().create_timer(2.5)
	var t := _hint_timer
	t.timeout.connect(func(): if _hint_timer == t: _hint.text = "")
