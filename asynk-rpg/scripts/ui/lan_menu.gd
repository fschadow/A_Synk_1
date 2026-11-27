extends Control
## Spiel-Menue mit mehreren Seiten (Einstieg ueber Glob.menu_entry):
## - Lobby: Spieler (Menschen/KI) und Einstellungen fuer ein neues Spiel –
##   lokal (Einzelspieler/Hotseat) oder im LAN. Bei einem geladenen Spielstand
##   stehen die Spieler fest; freie Plaetze koennen uebernommen werden, und
##   neue Spieler koennen dazukommen.
## - Laden: Liste der Spielstaende, je "Spielen" (lokal), "Hosten" (LAN), "Löschen".
## - LAN: Spiel eroeffnen, gefundene Spiele im WLAN oder IP von Hand.
## - Plaetze: Beitritt in ein laufendes LAN-Spiel (freier Platz oder neu).

var _pages: Array[Control] = []
var _find_page: VBoxContainer
var _lobby_page: VBoxContainer
var _slot_page: VBoxContainer
var _load_page: VBoxContainer
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _found_box: VBoxContainer
var _found_empty: Label
var _lobby_title: Label
var _lobby_info: Label
var _players_box: VBoxContainer
var _add_row: HBoxContainer
var _add_edit: LineEdit
var _ai_button: Button
var _settings_box: GridContainer
var _time_option: OptionButton
var _season_option: OptionButton
var _start_button: Button
var _wait_label: Label
var _lobby_back: Button
var _slot_box: VBoxContainer
var _saves_box: VBoxContainer
var _load_status: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().set_quit_on_go_back(false)
	_build()
	Net.lobby_changed.connect(_refresh_lobby)
	Net.status_changed.connect(_on_status)
	Net.joined.connect(_show_lobby)
	Net.choose_slot.connect(_show_slots)
	Net.discovery.hosts_changed.connect(_refresh_found)
	match Glob.menu_entry:
		Glob.MENU_NEW:
			Net.start_local(_player_name())
			_show_lobby()
		Glob.MENU_LOAD:
			_show_load()
		Glob.MENU_SLOTS:
			_show_slots()
		_:
			if Net.is_networked() and not Net.lobby.get("running", false):
				_show_lobby()
			else:
				_show_find()


func _exit_tree() -> void:
	Net.discovery.stop_search()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _build() -> void:
	var pages := MenuStyle.screen(self)

	# --- LAN: Suchen ---
	_find_page = _new_page(pages)
	MenuStyle.title(_find_page, "LAN-Spiel")
	MenuStyle.label(_find_page, "Dein Name", 18, true)
	_name_edit = MenuStyle.line_edit(_find_page, "Name", str(Net.load_setting("name", "Spieler")))
	_name_edit.max_length = 20
	MenuStyle.button(_find_page, "Spiel eröffnen", _on_host)
	MenuStyle.label(_find_page, "Offene Spiele im WLAN", 18, true)
	_found_box = VBoxContainer.new()
	_found_box.add_theme_constant_override("separation", 8)
	_find_page.add_child(_found_box)
	_found_empty = MenuStyle.label(_find_page, "Suche läuft …", 18, true)
	MenuStyle.label(_find_page, "Oder IP-Adresse des Hosts", 18, true)
	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	_find_page.add_child(ip_row)
	_ip_edit = MenuStyle.line_edit(ip_row, "z. B. 192.168.1.20", str(Net.load_setting("last_ip", "")))
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.text_submitted.connect(func(_t): _join(_ip_edit.text))
	MenuStyle.button(ip_row, "Verbinden", func(): _join(_ip_edit.text), 140, 20)
	_status = _status_label(_find_page)
	MenuStyle.button(_find_page, "Zurück", _back)

	# --- Lobby ---
	_lobby_page = _new_page(pages)
	_lobby_title = MenuStyle.title(_lobby_page, "Lobby")
	_lobby_info = MenuStyle.label(_lobby_page, "", 18, true)
	_lobby_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_info.custom_minimum_size.x = 420
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	_lobby_page.add_child(_players_box)
	_add_row = HBoxContainer.new()
	_add_row.add_theme_constant_override("separation", 8)
	_lobby_page.add_child(_add_row)
	_add_edit = MenuStyle.line_edit(_add_row, "Name weiterer Spieler")
	_add_edit.max_length = 20
	_add_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_edit.text_submitted.connect(func(_t): _add_player())
	MenuStyle.button(_add_row, "Hinzufügen", _add_player, 130, 18)
	_ai_button = MenuStyle.button(_add_row, "+ KI", func(): Net.add_ai_player(), 70, 18)
	_settings_box = GridContainer.new()
	_settings_box.columns = 2
	_settings_box.add_theme_constant_override("h_separation", 12)
	_settings_box.add_theme_constant_override("v_separation", 8)
	_lobby_page.add_child(_settings_box)
	_time_option = _option_row("Zeit pro Zug", Net.TURN_TIMES.map(_time_text),
		func(i): Net.set_turn_time(Net.TURN_TIMES[i]))
	_season_option = _option_row("Jahreszeit wechselt alle", Net.SEASON_LENGTHS.map(func(r): return "%d Runden" % r),
		func(i): Net.set_season_length(Net.SEASON_LENGTHS[i]))
	_start_button = MenuStyle.button(_lobby_page, "Spiel starten", func(): Net.start_game())
	_wait_label = MenuStyle.label(_lobby_page, "Warte, bis der Host das Spiel startet …", 18, true)
	_lobby_back = MenuStyle.button(_lobby_page, "Zurück", _back)

	# --- Plaetze (laufendes LAN-Spiel) ---
	_slot_page = _new_page(pages)
	MenuStyle.title(_slot_page, "Spiel läuft schon")
	MenuStyle.label(_slot_page, "Freien Platz übernehmen oder neu einsteigen:", 20, true)
	_slot_box = VBoxContainer.new()
	_slot_box.add_theme_constant_override("separation", 8)
	_slot_page.add_child(_slot_box)
	MenuStyle.button(_slot_page, "Abbrechen", _back)

	# --- Spiel laden ---
	_load_page = _new_page(pages)
	MenuStyle.title(_load_page, "Spiel laden")
	_saves_box = VBoxContainer.new()
	_saves_box.add_theme_constant_override("separation", 14)
	_load_page.add_child(_saves_box)
	_load_status = _status_label(_load_page)
	MenuStyle.button(_load_page, "Zurück", _back)


## Seite in einem eigenen Scrollbereich (bis zu 20 Spieler / viele Spielstaende).
func _new_page(parent: Container) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(500, mini(640, int(get_viewport_rect().size.y) - 100))
	parent.add_child(scroll)
	var page := MenuStyle.page(scroll)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages.append(page)
	return page


func _status_label(parent: Container) -> Label:
	var l := MenuStyle.label(parent, "", 18)
	l.add_theme_color_override("font_color", Color(1, 0.75, 0.4))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 360
	return l


func _option_row(text: String, items: Array, on_select: Callable) -> OptionButton:
	MenuStyle.label(_settings_box, text, 20)
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", 20)
	for item in items:
		o.add_item(item)
	o.item_selected.connect(on_select)
	_settings_box.add_child(o)
	return o


static func _time_text(secs: int) -> String:
	if secs <= 0:
		return "Ohne Limit"
	if secs < 60:
		return "%d Sekunden" % secs
	return "1 Minute" if secs == 60 else "%d Minuten" % (secs / 60)


# ------------------------------------------------------------------ Seiten

func _show_page(page: Control) -> void:
	for p in _pages:
		p.get_parent().visible = p == page
	if page == _find_page:
		Net.discovery.start_search()
		_refresh_found()
	else:
		Net.discovery.stop_search()


func _show_find() -> void:
	_show_page(_find_page)


func _show_lobby() -> void:
	_show_page(_lobby_page)
	_refresh_lobby()


func _show_slots() -> void:
	_show_page(_slot_page)
	for c in _slot_box.get_children():
		c.queue_free()
	for i in Net.free_slots():
		var idx: int = i
		var p := Net.player_entry(i)
		MenuStyle.button(_slot_box, "Als %s weiterspielen%s" % [p["name"], " (KI spielt gerade)" if p["ai"] else ""],
			func(): Net.claim(idx))
	if Net.players().size() < Net.MAX_PLAYERS:
		MenuStyle.button(_slot_box, "Als neuer Spieler einsteigen", func(): Net.join_as_new())


func _show_load() -> void:
	_show_page(_load_page)
	for c in _saves_box.get_children():
		c.queue_free()
	var saves := SaveStore.list()
	if saves.is_empty():
		MenuStyle.label(_saves_box, "Noch keine Spielstände.", 20, true)
	for entry in saves:
		_saves_box.add_child(_save_row(entry))


func _save_row(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var title := MenuStyle.label(box, entry["title"], 22)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MenuStyle.label(box, entry["detail"], 16, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var id: String = entry["id"]
	MenuStyle.button(row, "Spielen", func(): _load_status.text = Net.load_local(id), 120, 18)
	MenuStyle.button(row, "Im LAN hosten", func(): _host_saved(id), 170, 18)
	MenuStyle.button(row, "Löschen", func(): _confirm_delete(id, entry["title"]), 110, 18)
	return box


func _refresh_found() -> void:
	if not is_instance_valid(_found_box):
		return
	for c in _found_box.get_children():
		c.queue_free()
	var list := Net.discovery.host_list()
	for h in list:
		var info: Dictionary = h["info"]
		var ip: String = h["ip"]
		var text := "%s  ·  %d Spieler%s" % [info.get("host", "?"), int(info.get("players", 0)),
			"  ·  läuft" if info.get("running", false) else ""]
		MenuStyle.button(_found_box, text, func(): _join(ip), 360, 22)
	_found_empty.visible = list.is_empty()


func _refresh_lobby() -> void:
	if not _lobby_page.get_parent().visible:
		return
	var authority := Net.is_authority()
	var resume := Net.is_resume()
	if Net.is_local():
		_lobby_title.text = "Neues Spiel"
		_lobby_info.text = "Ein Spieler = Einzelspieler, mehrere = Hotseat an diesem Gerät. KI-Mitspieler sind möglich."
	elif resume:
		_lobby_title.text = "Spielstand im LAN"
		_lobby_info.text = (_ip_hint() + "\n") if authority else ""
		_lobby_info.text += "Freie Plätze können übernommen werden, neue Spieler steigen am Ende der Reihenfolge ein."
	else:
		_lobby_title.text = "LAN-Lobby"
		_lobby_info.text = _ip_hint() if authority else "%d von %d Plätzen belegt." % [Net.players().size(), Net.MAX_PLAYERS]
	for c in _players_box.get_children():
		c.queue_free()
	var players := Net.players()
	for i in players.size():
		_players_box.add_child(_player_row(i, players[i]))
	_add_row.visible = players.size() < Net.MAX_PLAYERS
	_add_edit.placeholder_text = "Neuer Spieler (steigt neu ein)" if resume else "Name weiterer Spieler"
	_ai_button.visible = authority
	# Zugzeit darf auch beim Fortsetzen geaendert werden, die Jahreszeit-Laenge nicht.
	_time_option.disabled = not authority
	_time_option.select(maxi(0, Net.TURN_TIMES.find(Net.turn_time())))
	_season_option.disabled = not authority or resume
	_season_option.select(maxi(0, Net.SEASON_LENGTHS.find(Net.season_length())))
	_start_button.visible = authority
	_start_button.disabled = not Net.can_start()
	_start_button.text = "Spiel starten" if Net.can_start() or Net.is_local() or resume else "Spiel starten (mind. 2 Spieler)"
	_wait_label.visible = not authority
	_lobby_back.text = "Zurück" if Net.is_local() else "Lobby verlassen"


func _ip_hint() -> String:
	var ips := LanDiscovery.local_ipv4()
	return "Andere Geräte im selben WLAN finden das Spiel automatisch oder verbinden sich mit: %s" % (
		", ".join(ips) if not ips.is_empty() else "(keine LAN-Adresse gefunden)")


func _player_row(i: int, p: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var swatch := ColorRect.new()
	swatch.color = AgentSpawner.color_for(i)
	swatch.custom_minimum_size = Vector2(22, 22)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var mine: bool = int(p["peer"]) == Net.my_peer() and p["connected"] and not p["ai"]
	var tags := []
	if p["ai"]:
		tags.append("KI")
	elif not p["connected"]:
		tags.append("frei")
	elif Net.is_networked() and mine:
		tags.append("dieses Gerät")
	elif Net.is_networked() and int(p["peer"]) == 1:
		tags.append("Host")
	if p.get("new", false):
		tags.append("neu")
	var l := MenuStyle.label(row, "%d. %s%s" % [i + 1, p["name"], "  (%s)" % ", ".join(tags) if not tags.is_empty() else ""], 20)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var idx := i
	if Net.is_resume() and not p.get("new", false):
		if not p["connected"] or (p["ai"] and Net.is_authority()):
			MenuStyle.button(row, "Übernehmen", func(): Net.take_slot(idx), 130, 16)
		elif Net.is_host() and mine:
			MenuStyle.button(row, "Freigeben", func(): Net.free_slot(idx), 120, 16)
	elif Net.is_authority() or mine:
		MenuStyle.button(row, "Entfernen", func(): Net.remove_player(idx), 110, 16)
	return row


# --------------------------------------------------------------- Aktionen

func _player_name() -> String:
	var n := _name_edit.text.strip_edges() if _name_edit else ""
	if n == "":
		n = str(Net.load_setting("name", "Spieler"))
	Net.save_setting("name", n)
	return n


func _on_host() -> void:
	var err := Net.host_game(_player_name())
	if err != "":
		_on_status(err)
		return
	_show_lobby()


func _host_saved(id: String) -> void:
	var err := Net.host_saved(id)
	if err != "":
		_load_status.text = err
		return
	_show_lobby()


func _confirm_delete(id: String, title: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Spielstand löschen"
	dlg.dialog_text = "„%s“ wirklich löschen?\nDas lässt sich nicht rückgängig machen." % title
	dlg.ok_button_text = "Löschen"
	dlg.cancel_button_text = "Abbrechen"
	dlg.confirmed.connect(func():
		SaveStore.delete(id)
		_show_load())
	add_child(dlg)
	dlg.popup_centered()


func _join(ip: String) -> void:
	Net.save_setting("last_ip", ip.strip_edges())
	var err := Net.join(ip, _player_name())
	if err != "":
		_on_status(err)


func _add_player() -> void:
	Net.add_local_player(_add_edit.text)
	_add_edit.text = ""


func _on_status(text: String) -> void:
	_status.text = text
	if _load_page.get_parent().visible:
		_load_status.text = text
	elif text != "" and not Net.is_active() and not _find_page.get_parent().visible:
		_show_find()


func _back() -> void:
	if (_lobby_page.get_parent().visible or _slot_page.get_parent().visible) and Net.is_networked():
		Net.leave()
		_show_find()
		return
	Net.leave()
	Glob.go_to_menu()
