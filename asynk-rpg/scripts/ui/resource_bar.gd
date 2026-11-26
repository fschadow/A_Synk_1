extends Control
## Rohstoff-Leiste oben links: zeigt das Inventar des Spielers, der gerade
## am Zug ist. Hoert nur auf die GameSession.

const SHEET := preload("res://assets/ui/Sprite sheet for Basic Pack.png")

var _session: GameSession
var _title: Label
var _values := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_session = get_tree().get_first_node_in_group(GameSession.GROUP) as GameSession
	if _session:
		_session.game_started.connect(_refresh)
		_session.move_applied.connect(func(_m, s): _refresh(s))
		_session.turn_started.connect(func(_p, s): _refresh(s))


func _build() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxTexture.new()
	bg.texture = SHEET
	bg.region_rect = Rect2(153, 57, 30, 30)
	bg.texture_margin_left = 7
	bg.texture_margin_top = 7
	bg.texture_margin_right = 7
	bg.texture_margin_bottom = 7
	bg.content_margin_left = 16
	bg.content_margin_right = 16
	bg.content_margin_top = 10
	bg.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_color_override("font_color", Color("5a3b2a"))
	_title.add_theme_font_size_override("font_size", 14)
	box.add_child(_title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	box.add_child(grid)
	for item in ResourceConfig.ITEMS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_label := Label.new()
		name_label.text = ResourceConfig.ITEM_NAMES[item]
		name_label.add_theme_color_override("font_color", Color("5a3b2a"))
		name_label.add_theme_font_size_override("font_size", 18)
		row.add_child(name_label)
		var value := Label.new()
		value.add_theme_color_override("font_color", Color("2d1d14"))
		value.add_theme_font_size_override("font_size", 18)
		row.add_child(value)
		grid.add_child(row)
		_values[item] = value


func _refresh(state: GameState) -> void:
	var me := state.current()
	_title.text = "Rohstoffe · %s" % me["name"]
	for item in _values:
		var n: int = me["inv"][item]
		var label: Label = _values[item]
		label.text = "%d" % n if n < ResourceConfig.CARRY_LIMIT else "%d (voll)" % n
