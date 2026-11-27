extends Control
## Startmenue: Weiterspielen, Neues Spiel, LAN-Spiel, Google Drive,
## Einstellungen, Beenden. Die Oberflaeche wird im Code gebaut (Stil aus
## MenuStyle), damit sie ohne Editor-Klickerei angepasst werden kann.

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
	# Meldung aus dem Netzwerk (z. B. "Verbindung zum Host verloren") anzeigen.
	if Net.last_error != "":
		_show_info("LAN-Spiel", Net.last_error)
		Net.last_error = ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _info_page and _info_page.visible:
			_show_main()
		else:
			get_tree().quit()


func _build() -> void:
	var pages := MenuStyle.screen(self)

	# --- Hauptseite ---
	_main_page = MenuStyle.page(pages)
	MenuStyle.title(_main_page, "AsynkRPG", 48)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	_main_page.add_child(spacer)

	_continue_button = MenuStyle.button(_main_page, "Weiterspielen", func(): Glob.start_game(false))
	_new_button = MenuStyle.button(_main_page, "Neues Spiel", _on_new_game)
	MenuStyle.button(_main_page, "LAN-Spiel", func(): get_tree().change_scene_to_file(Glob.LAN_SCENE))
	MenuStyle.button(_main_page, "Google Drive verbinden", func(): _show_info(
		"Google Drive",
		"Kommt bald.\n\nHier kannst du später dein Google-Drive-Konto\nverbinden, um mit Freunden über geteilte\nZugdateien zu spielen."))
	MenuStyle.button(_main_page, "Einstellungen", func(): _show_info(
		"Einstellungen",
		"Hier gibt es noch nichts einzustellen.\n\nTon, Sprache und mehr folgen später."))
	if OS.get_name() != "Web":
		MenuStyle.button(_main_page, "Beenden", func(): get_tree().quit())

	# --- Unterseite (Drive / Einstellungen / Meldungen) ---
	_info_page = MenuStyle.page(pages, 20)
	_info_title = MenuStyle.title(_info_page, "")
	_info_text = MenuStyle.label(_info_page)
	_info_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuStyle.button(_info_page, "Zurück", _show_main)


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
