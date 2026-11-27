class_name MenuStyle
extends RefCounted
## Gemeinsames Aussehen fuer Startmenue und LAN-Lobby (dunkelgruene Knoepfe,
## Panel mit runden Ecken). Alles im Code, ohne Theme-Datei.

const BG_COLOR := Color("1d2a24")
const PANEL_COLOR := Color("2b3d33")
const BUTTON_COLOR := Color("3f5a4a")
const BUTTON_HOVER := Color("527561")
const BUTTON_PRESSED := Color("2f4538")
const BUTTON_DISABLED := Color("34443b")
const ACCENT := Color("e8c872")
const TEXT_DIM := Color("b9c8bd")


## Vollbild-Hintergrund + zentriertes Panel. Liefert den Container im Panel.
static func screen(parent: Control) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_COLOR
	panel_style.set_corner_radius_all(16)
	panel_style.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var pages := VBoxContainer.new()
	panel.add_child(pages)
	return pages


static func page(parent: Container, separation := 12) -> VBoxContainer:
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", separation)
	parent.add_child(p)
	return p


static func title(parent: Container, text: String, size := 36) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	parent.add_child(l)
	return l


static func label(parent: Container, text := "", size := 22, dim := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if dim:
		l.add_theme_color_override("font_color", TEXT_DIM)
	parent.add_child(l)
	return l


static func button(parent: Container, text: String, action: Callable, min_width := 360.0, size := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 64 if size >= 24 else 48)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", button_style(BUTTON_COLOR))
	b.add_theme_stylebox_override("hover", button_style(BUTTON_HOVER))
	b.add_theme_stylebox_override("pressed", button_style(BUTTON_PRESSED))
	b.add_theme_stylebox_override("disabled", button_style(BUTTON_DISABLED))
	var focus := button_style(BUTTON_HOVER)
	focus.border_color = ACCENT
	focus.set_border_width_all(2)
	b.add_theme_stylebox_override("focus", focus)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


static func line_edit(parent: Container, placeholder: String, text := "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.custom_minimum_size = Vector2(0, 52)
	e.add_theme_font_size_override("font_size", 22)
	parent.add_child(e)
	return e


static func button_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(10)
	s.set_content_margin_all(12)
	return s
