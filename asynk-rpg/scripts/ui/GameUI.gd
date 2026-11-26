extends Control
## Aktionsleiste unten: Laufen, Sammeln, Holz (faellen), Mine, Fisch.
## Die Knoepfe sind Umschalter in einer ButtonGroup, es ist also immer genau
## einer aktiv. "Aktiv" wird ueber den pressed-Stil angezeigt (helles Icon),
## nicht mehr durch Tauschen von Texturen, das auf dem Handy haengen blieb.

signal ability_changed(status: Glob.Status)

const SHEET := preload("res://assets/ui/Sprite sheet for Basic Pack.png")

## Status -> [Icon inaktiv (braun), Icon aktiv (hell)] im UI-Spritesheet.
## Sammeln hat noch kein eigenes Icon und nutzt vorerst die Giesskanne.
const ICONS := {
	Glob.Status.Nothing: [Rect2(614, 5, 20, 21), Rect2(519, 5, 18, 21)],
	Glob.Status.Collect: [Rect2(678, 5, 20, 21), Rect2(583, 5, 18, 21)],
	Glob.Status.Lumber: [Rect2(614, 37, 20, 21), Rect2(519, 37, 18, 21)],
	Glob.Status.Mine: [Rect2(646, 37, 20, 21), Rect2(551, 37, 18, 21)],
	Glob.Status.Fish: [Rect2(678, 37, 20, 21), Rect2(583, 37, 18, 21)],
}
const TOOLTIPS := {
	Glob.Status.Nothing: "Laufen",
	Glob.Status.Collect: "Sammeln (Äste, Obst, Laub)",
	Glob.Status.Lumber: "Baum fällen (Holz)",
	Glob.Status.Mine: "Steine abbauen",
	Glob.Status.Fish: "Fischen",
}

@onready var _panel: Control = $MarginContainer/VBoxContainer/MarginContainer/NinePatchRect
@onready var _row: HBoxContainer = %Nothing_Button.get_parent()

var _group := ButtonGroup.new()
var _buttons := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons[Glob.Status.Nothing] = %Nothing_Button
	_buttons[Glob.Status.Lumber] = %Lumber_Button
	_buttons[Glob.Status.Mine] = %Mine_Button
	_buttons[Glob.Status.Fish] = %Fish_Button
	# Sammeln-Knopf neu, direkt hinter "Laufen".
	var collect := Button.new()
	collect.name = "Collect_Button"
	collect.custom_minimum_size = %Nothing_Button.custom_minimum_size
	collect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	collect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(collect)
	_row.move_child(collect, %Nothing_Button.get_index() + 1)
	_buttons[Glob.Status.Collect] = collect

	for status in _buttons:
		var b: Button = _buttons[status]
		b.toggle_mode = true
		b.button_group = _group
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = TOOLTIPS[status]
		var off := _style(ICONS[status][0])
		var on := _style(ICONS[status][1])
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("hover", off)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_stylebox_override("disabled", off)
		b.toggled.connect(func(on_now: bool): if on_now: _select(status))
	select(Glob.Status.Nothing)


func _style(region: Rect2) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = SHEET
	s.region_rect = region
	return s


## Faehigkeit von aussen setzen (z. B. nach einem Neustart).
func select(status: Glob.Status) -> void:
	_buttons[status].set_pressed_no_signal(true)
	_select(status)


func _select(status: Glob.Status) -> void:
	Glob.CurStatus = status
	ability_changed.emit(status)


## true, wenn der Bildschirmpunkt auf der Leiste liegt. Funktioniert auch mit
## Touch, wo es kein zuverlaessiges "Maus ist ueber dem Knopf" gibt.
func covers(screen_pos: Vector2) -> bool:
	return visible and _panel.get_global_rect().has_point(screen_pos)


func _input(event: InputEvent) -> void:
	# Beim Druecken festhalten, ob er auf der Leiste begann; die Kamera nutzt das,
	# damit Wischen auf der Leiste die Karte nicht verschiebt.
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		Glob.MouseOnUI = covers(event.position)
