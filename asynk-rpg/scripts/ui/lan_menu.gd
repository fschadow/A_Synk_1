extends Control
## LAN-Menue mit drei Seiten:
## 1. Suchen: Name eingeben, Spiel eroeffnen, gefundene Spiele im WLAN oder
##    IP von Hand, gespeichertes LAN-Spiel fortsetzen.
## 2. Lobby: alle Spieler, eigene Spieler hinzufuegen (Hotseat), Host stellt
##    die Zugzeit ein und startet.
## 3. Platz waehlen: Beitritt in ein laufendes Spiel, freien Spieler uebernehmen.

var _find_page: VBoxContainer
var _lobby_page: VBoxContainer
var _slot_page: VBoxContainer
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _found_box: VBoxContainer
var _found_empty: Label
var _resume_button: Button
var _lobby_info: Label
var _players_box: VBoxContainer
var _add_row: HBoxContainer
var _add_edit: LineEdit
var _time_option: OptionButton
var _start_button: Button
var _wait_label: Label
var _slot_box: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().set_quit_on_go_back(false)
	_build()
	Net.lobby_changed.connect(_refresh_lobby)
	Net.status_changed.connect(_on_status)
	Net.joined.connect(_show_lobby)
	Net.choose_slot.connect(_show_slots)
	Net.discovery.hosts_changed.connect(_refresh_found)
	if Net.is_active() and not Net.lobby.get("running", false):
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

	# --- Seite 1: Suchen ---
	_find_page = MenuStyle.page(_wrap_scroll(pages))
	MenuStyle.title(_find_page, "LAN-Spiel")
	MenuStyle.label(_find_page, "Dein Name", 18, true)
	_name_edit = MenuStyle.line_edit(_find_page, "Name", str(Net.load_setting("name", "Spieler")))
	_name_edit.max_length = 20
	MenuStyle.button(_find_page, "Spiel eröffnen", _on_host)
	_resume_button = MenuStyle.button(_find_page, "Gespeichertes LAN-Spiel fortsetzen", _on_resume)
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
	_status = MenuStyle.label(_find_page, "", 18)
	_status.add_theme_color_override("font_color", Color(1, 0.75, 0.4))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 360
	MenuStyle.button(_find_page, "Zurück", _back)

	# --- Seite 2: Lobby ---
	_lobby_page = MenuStyle.page(_wrap_scroll(pages))
	MenuStyle.title(_lobby_page, "Lobby")
	_lobby_info = MenuStyle.label(_lobby_page, "", 18, true)
	_lobby_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_info.custom_minimum_size.x = 420
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	_lobby_page.add_child(_players_box)
	_add_row = HBoxContainer.new()
	_add_row.add_theme_constant_override("separation", 8)
	_lobby_page.add_child(_add_row)
	_add_edit = MenuStyle.line_edit(_add_row, "Weiterer Spieler an diesem Gerät")
	_add_edit.max_length = 20
	_add_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_edit.text_submitted.connect(func(_t): _add_player())
	MenuStyle.button(_add_row, "Hinzufügen", _add_player, 150, 20)
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 12)
	_lobby_page.add_child(time_row)
	MenuStyle.label(time_row, "Zeit pro Zug", 20)
	_time_option = OptionButton.new()
	_time_option.add_theme_font_size_override("font_size", 20)
	for secs in Net.TURN_TIMES:
		_time_option.add_item(_time_text(secs))
	_time_option.item_selected.connect(func(i): Net.set_turn_time(Net.TURN_TIMES[i]))
	time_row.add_child(_time_option)
	_start_button = MenuStyle.button(_lobby_page, "Spiel starten", func(): Net.start_game())
	_wait_label = MenuStyle.label(_lobby_page, "Warte, bis der Host das Spiel startet …", 18, true)
	MenuStyle.button(_lobby_page, "Lobby verlassen", _leave_lobby)

	# --- Seite 3: Platz waehlen ---
	_slot_page = MenuStyle.page(pages)
	MenuStyle.title(_slot_page, "Spiel läuft schon")
	MenuStyle.label(_slot_page, "Welchen Spieler möchtest du übernehmen?", 20, true)
	_slot_box = VBoxContainer.new()
	_slot_box.add_theme_constant_override("separation", 8)
	_slot_page.add_child(_slot_box)
	MenuStyle.button(_slot_page, "Abbrechen", _leave_lobby)


func _wrap_scroll(parent: Container) -> Container:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(460, 0)
	# Bis zu 20 Spieler: die Seite darf nicht hoeher als der Bildschirm werden.
	scroll.custom_minimum_size.y = mini(640, int(get_viewport_rect().size.y) - 100)
	parent.add_child(scroll)
	return scroll


static func _time_text(secs: int) -> String:
	if secs <= 0:
		return "Ohne Limit"
	if secs < 60:
		return "%d Sekunden" % secs
	return "1 Minute" if secs == 60 else "%d Minuten" % (secs / 60)


# ------------------------------------------------------------------ Seiten

func _show_page(page: Control) -> void:
	for p in [_find_page, _lobby_page, _slot_page]:
		p.visible = p == page
	_lobby_page.get_parent().visible = page == _lobby_page
	_find_page.get_parent().visible = page == _find_page
	if page == _find_page:
		Net.discovery.start_search()
		_resume_button.visible = Net.has_lan_save()
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
		MenuStyle.button(_slot_box, "Als %s weiterspielen" % Net.players()[i]["name"], func(): Net.claim(idx))


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
	_found_empty.text = "Suche läuft …" if list.is_empty() else ""
	_found_empty.visible = list.is_empty()


func _refresh_lobby() -> void:
	if not _lobby_page.visible:
		return
	var host := Net.is_host()
	var ips := LanDiscovery.local_ipv4()
	if host:
		_lobby_info.text = "Andere Geräte im selben WLAN finden das Spiel automatisch oder verbinden sich mit: %s" % (
			", ".join(ips) if not ips.is_empty() else "(keine LAN-Adresse gefunden)")
	else:
		_lobby_info.text = "%d von %d Plätzen belegt." % [Net.players().size(), Net.MAX_PLAYERS]
	for c in _players_box.get_children():
		c.queue_free()
	var players := Net.players()
	for i in players.size():
		_players_box.add_child(_player_row(i, players[i], host))
	var full := players.size() >= Net.MAX_PLAYERS
	_add_row.visible = not full
	_time_option.disabled = not host
	_time_option.select(maxi(0, Net.TURN_TIMES.find(Net.turn_time())))
	_start_button.visible = host
	_start_button.disabled = players.size() < 2
	_start_button.text = "Spiel starten" if players.size() >= 2 else "Spiel starten (mind. 2 Spieler)"
	_wait_label.visible = not host


func _player_row(i: int, p: Dictionary, host: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var swatch := ColorRect.new()
	swatch.color = AgentSpawner.color_for(i)
	swatch.custom_minimum_size = Vector2(22, 22)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var tags := []
	if int(p["peer"]) == Net.my_peer():
		tags.append("dieses Gerät")
	elif int(p["peer"]) == 1:
		tags.append("Host")
	var l := MenuStyle.label(row, "%d. %s%s" % [i + 1, p["name"], "  (%s)" % ", ".join(tags) if not tags.is_empty() else ""], 20)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if host or int(p["peer"]) == Net.my_peer():
		var idx := i
		MenuStyle.button(row, "Entfernen", func(): Net.remove_player(idx), 110, 16)
	return row


# --------------------------------------------------------------- Aktionen

func _player_name() -> String:
	var n := _name_edit.text.strip_edges()
	if n == "":
		n = "Spieler"
	Net.save_setting("name", n)
	return n


func _on_host() -> void:
	var err := Net.host_game(_player_name())
	if err != "":
		_on_status(err)
		return
	_show_lobby()


func _on_resume() -> void:
	var err := Net.host_game(_player_name(), true)
	if err != "":
		_on_status(err)


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
	if text != "" and not Net.is_active() and not _find_page.visible:
		_show_find()


func _leave_lobby() -> void:
	Net.leave()
	_show_find()


func _back() -> void:
	if _find_page.visible:
		Net.leave()
		Glob.go_to_menu()
	else:
		_leave_lobby()
