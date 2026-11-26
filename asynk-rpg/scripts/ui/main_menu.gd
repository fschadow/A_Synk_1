extends Control
## Startmenue: Weiterspielen, Neues Spiel, Google Drive, Einstellungen, Beenden.
## Die Oberflaeche wird im Code gebaut (wie turn_hud.gd), damit sie ohne
## Editor-Klickerei angepasst werden kann.

const BG_COLOR := Color("1d2a24")
const PANEL_COLOR := Color("2b3d33")
const BUTTON_COLOR := Color("3f5a4a")
const BUTTON_HOVER := Color("527561")
const BUTTON_PRESSED := Color("2f4538")
const ACCENT := Color("e8c872")

var _main_page: VBoxContainer
var _info_page: VBoxContainer
var _info_title: Label
var _info_text: Label
var _continue_button: Button
var _new_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Im Menue schliesst die Android-Zurueck-Taste die App (bzw. schliesst eine Unterseite).
	get_tree().set_quit_on_go_back(false)
	_build()
	_continue_button.visible = GameSession.has_savegame()
	_show_main()
	(_continue_button if _continue_button.visible else _new_button).grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _info_page and _info_page.visible:
			_show_main()
		else:
			get_tree().quit()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_COLOR
	panel_style.set_corner_radius_all(16)
	panel_style.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var pages := VBoxContainer.new()
	panel.add_child(pages)

	# --- Hauptseite ---
	_main_page = VBoxContainer.new()
	_main_page.add_theme_constant_override("separation", 12)
	pages.add_child(_main_page)

	var title := Label.new()
	title.text = "AsynkRPG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", ACCENT)
	_main_page.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	_main_page.add_child(spacer)

	_continue_button = _menu_button(_main_page, "Weiterspielen", func(): Glob.start_game(false))
	_new_button = _menu_button(_main_page, "Neues Spiel", _on_new_game)
	_menu_button(_main_page, "Google Drive verbinden", func(): _show_info(
		"Google Drive",
		"Kommt bald.\n\nHier kannst du später dein Google-Drive-Konto\nverbinden, um mit Freunden über geteilte\nZugdateien zu spielen."))
	_menu_button(_main_page, "Einstellungen", func(): _show_info(
		"Einstellungen",
		"Hier gibt es noch nichts einzustellen.\n\nTon, Sprache und mehr folgen später."))
	if OS.get_name() != "Web":
		_menu_button(_main_page, "Beenden", func(): get_tree().quit())

	# --- Unterseite (Drive / Einstellungen) ---
	_info_page = VBoxContainer.new()
	_info_page.add_theme_constant_override("separation", 20)
	pages.add_child(_info_page)

	_info_title = Label.new()
	_info_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_title.add_theme_font_size_override("font_size", 36)
	_info_title.add_theme_color_override("font_color", ACCENT)
	_info_page.add_child(_info_title)

	_info_text = Label.new()
	_info_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_text.add_theme_font_size_override("font_size", 22)
	_info_page.add_child(_info_text)

	_menu_button(_info_page, "Zurück", _show_main)


func _menu_button(parent: Container, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 64)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_stylebox_override("normal", _button_style(BUTTON_COLOR))
	b.add_theme_stylebox_override("hover", _button_style(BUTTON_HOVER))
	b.add_theme_stylebox_override("pressed", _button_style(BUTTON_PRESSED))
	var focus := _button_style(BUTTON_HOVER)
	focus.border_color = ACCENT
	focus.set_border_width_all(2)
	b.add_theme_stylebox_override("focus", focus)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _button_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(10)
	s.set_content_margin_all(12)
	return s


func _on_new_game() -> void:
	if GameSession.has_savegame():
		var dlg := ConfirmationDialog.new()
		dlg.title = "Neues Spiel"
		dlg.dialog_text = "Der gespeicherte Spielstand wird überschrieben.\nTrotzdem neu anfangen?"
		dlg.ok_button_text = "Neues Spiel"
		dlg.cancel_button_text = "Abbrechen"
		dlg.confirmed.connect(func(): Glob.start_game(true))
		add_child(dlg)
		dlg.popup_centered()
	else:
		Glob.start_game(true)


func _show_main() -> void:
	_info_page.visible = false
	_main_page.visible = true


func _show_info(title: String, text: String) -> void:
	_info_title.text = title
	_info_text.text = text
	_main_page.visible = false
	_info_page.visible = true
	_info_page.get_child(-1).grab_focus()
