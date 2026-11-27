class_name VillageDialog
extends Control
## Dialog im Tier-Dorf: Portraet, Begruessung und der aktuelle Auftrag fuer
## den Spieler, der dran ist. "Abgeben" schickt den Zug an die GameSession.

const PORTRAITS := preload("res://assets/npc/Portraits.png")

var _session: GameSession
var _village_id := ""
var _portrait: TextureRect
var _title: Label
var _greeting: Label
var _quest: Label
var _status: Label
var _give: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 600  # ueber Rohstoffleiste und Aktionsleiste
	visible = false
	_build()
	_session = get_tree().get_first_node_in_group(GameSession.GROUP) as GameSession
	if _session:
		_session.move_applied.connect(func(_m, _s): if visible: _refresh())
		_session.turn_started.connect(func(_p, _s): if visible: _refresh())
		_session.move_rejected.connect(func(r): if visible: _status.text = r)


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f3e8d0")
	style.border_color = Color("6b4428")
	style.set_border_width_all(4)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(180, 180)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_portrait)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size.x = 360
	row.add_child(col)
	_title = _label(col, 24, Color("5a3b2a"))
	_greeting = _label(col, 18, Color("2d1d14"))
	var sep := HSeparator.new()
	col.add_child(sep)
	_quest = _label(col, 18, Color("2d1d14"))
	_status = _label(col, 16, Color("a0402a"))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	col.add_child(buttons)
	_give = Button.new()
	_give.text = "Abgeben"
	_give.add_theme_font_size_override("font_size", 20)
	_give.pressed.connect(func(): _session.request_quest(_village_id))
	buttons.add_child(_give)
	var close_button := Button.new()
	close_button.text = "Schließen"
	close_button.add_theme_font_size_override("font_size", 20)
	close_button.pressed.connect(close)
	buttons.add_child(close_button)


func _label(parent: Container, size: int, color: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func open(village_id: String) -> void:
	_village_id = village_id
	var kind := _session.objects.kind(village_id)
	var a := Villages.animal(kind)
	var atlas := AtlasTexture.new()
	atlas.atlas = PORTRAITS
	atlas.region = Rect2(Villages.animal_index(kind) * 256, 0, 256, 256)
	_portrait.texture = atlas
	_title.text = "%s · %s" % [a["name"], a["village"]]
	_greeting.text = "„%s“" % a["greeting"]
	_status.text = ""
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _refresh() -> void:
	var state := _session.state
	var kind := _session.objects.kind(_village_id)
	var me := state.current()
	var q := Villages.current_quest(state, kind, state.current_player)
	if q.is_empty():
		_quest.text = "Danke für deine Hilfe, %s! Mehr Aufträge gibt es bald." % me["name"]
		_give.visible = false
		_status.text = ""
		return
	var have := []
	for item in q["want"]:
		have.append("%d %s" % [me["inv"][item], ResourceConfig.ITEM_NAMES[item]])
	_quest.text = "Auftrag für %s:\n%s\n\nGesucht: %s  (du hast %s)\nBelohnung: %s" % [
		me["name"], q["text"], Villages.items_text(q["want"]), ", ".join(have), Villages.items_text(q["reward"])]
	_give.visible = true
	var move := GameRules.make_quest(state, _session.objects, _village_id)
	var err := "" if not move.has("error") else str(move["error"])
	if err == "":
		err = GameRules.validate(state, _session.map, move, _session.objects)
	if not Net.controls(state.current_player):
		err = "%s ist gerade nicht dran." % me["name"]
	_give.disabled = err != ""
	_status.text = err
