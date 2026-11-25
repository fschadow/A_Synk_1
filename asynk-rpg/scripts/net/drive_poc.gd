## Testoberfläche für den Drive-Proof-of-Concept (Szene scenes/drive_poc.tscn).
##
## Ablauf mit zwei Google-Konten A und B (z. B. zwei Browserfenster):
##  1. Beide: API-Key eintragen. A: anmelden (Web) oder Token einfügen (Desktop).
##  2. A: "Meine Zugdatei anlegen" -> Datei-ID erscheint im Log, A schickt sie an B.
##  3. B: Datei-ID eintragen, "Mitspielerdatei lesen" -> Inhalt von A erscheint,
##     obwohl B nur drive.file bzw. gar kein Token hat.
##  4. A: "Zug schreiben", B: "Auf Änderung prüfen" -> Version steigt.
extends Control

var drive: DriveClient
var auth: GoogleAuthWeb
var my_file_id := ""
var last_seen_version := ""
var move_counter := 0

var api_key_edit: LineEdit
var client_id_edit: LineEdit
var token_edit: LineEdit
var other_id_edit: LineEdit
var log_label: RichTextLabel


func _ready() -> void:
	drive = DriveClient.new()
	add_child(drive)
	auth = GoogleAuthWeb.new()
	add_child(auth)
	auth.token_received.connect(_on_token)
	auth.auth_failed.connect(func(r: String) -> void: _log("Login fehlgeschlagen: " + r))
	_build_ui()
	_log("Plattform: %s, Web-Login möglich: %s" % [OS.get_name(), GoogleAuthWeb.is_supported()])


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)

	api_key_edit = _field(box, "API-Key (zum Lesen)")
	client_id_edit = _field(box, "OAuth-Client-ID (Web)")
	token_edit = _field(box, "Access-Token (Desktop-Test: aus OAuth Playground einfügen)")
	other_id_edit = _field(box, "Datei-ID des Mitspielers")

	var row := HFlowContainer.new()
	box.add_child(row)
	_button(row, "Anmelden (Web)", _on_login)
	_button(row, "Meine Zugdatei anlegen", _on_create)
	_button(row, "Zug schreiben", _on_write_move)
	_button(row, "Mitspielerdatei lesen", _on_read_other)
	_button(row, "Auf Änderung prüfen", _on_poll_other)

	log_label = RichTextLabel.new()
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.scroll_following = true
	log_label.selection_enabled = true
	box.add_child(log_label)


func _field(parent: Node, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	parent.add_child(e)
	return e


func _button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _log(msg: String) -> void:
	print(msg)
	if log_label:
		log_label.append_text(msg + "\n")


func _sync_credentials() -> void:
	drive.api_key = api_key_edit.text.strip_edges()
	if not token_edit.text.strip_edges().is_empty():
		drive.access_token = token_edit.text.strip_edges()


func _on_login() -> void:
	auth.show_login_button(client_id_edit.text.strip_edges())
	_log("Bitte den eingeblendeten Google-Button oben anklicken.")


func _on_token(token: String) -> void:
	token_edit.text = token
	_log("Angemeldet, Token erhalten (%d Zeichen)." % token.length())


func _on_create() -> void:
	_sync_credentials()
	var content := {"game": "asynk-poc", "player": "A", "moves": []}
	my_file_id = await drive.create_json_file("asynk-poc-moves.json", content)
	if my_file_id.is_empty():
		_log("Anlegen fehlgeschlagen (Token gültig?).")
		return
	_log("Datei angelegt: " + my_file_id)
	var shared := await drive.share_anyone_with_link(my_file_id)
	_log("Freigabe 'jeder mit Link': %s" % ("OK" if shared else "FEHLER"))
	_log("Diese ID an den Mitspieler schicken: " + my_file_id)


func _on_write_move() -> void:
	_sync_credentials()
	if my_file_id.is_empty():
		_log("Erst eigene Zugdatei anlegen.")
		return
	move_counter += 1
	var moves := []
	for i in move_counter:
		moves.append({"n": i + 1, "action": "move", "to": [i, i]})
	var ok := await drive.update_json_file(my_file_id, {"game": "asynk-poc", "player": "A", "moves": moves})
	_log("Zug %d geschrieben: %s" % [move_counter, "OK" if ok else "FEHLER"])


func _on_read_other() -> void:
	_sync_credentials()
	var data: Variant = await drive.read_public_json(other_id_edit.text.strip_edges())
	if data == null:
		_log("Lesen fehlgeschlagen.")
		return
	_log("Mitspielerdatei: " + JSON.stringify(data))


func _on_poll_other() -> void:
	_sync_credentials()
	var meta: Variant = await drive.get_public_version(other_id_edit.text.strip_edges())
	if meta == null:
		_log("Abfrage fehlgeschlagen.")
		return
	var v := str(meta.get("version", ""))
	_log("Version %s (geändert %s)%s" % [v, meta.get("modifiedTime", "?"),
		"  -> NEU, bitte neu lesen" if v != last_seen_version and last_seen_version != "" else ""])
	last_seen_version = v
