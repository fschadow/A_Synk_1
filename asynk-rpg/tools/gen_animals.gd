extends SceneTree
## Zeichnet Platzhalter-Grafiken fuer die Tier-Doerfer:
##   assets/npc/Portraits.png  6 Portraets (je 256x256, nebeneinander) fuer den Dialog
##   assets/npc/Doerfer.png    6 Dorf-Kacheln (je 256x256) fuer die Karte:
##                             Huetten + kleine Tierfigur, Boden bei y = 150
## Reihenfolge wie Villages.ANIMALS. Zum Uebermalen gedacht.
##   godot --headless --path asynk-rpg -s res://tools/gen_animals.gd

const S := 2  # Supersampling fuer weiche Kanten
const SIZE := 256

## Farben je Tier: [Fell, Fell hell, Kleidung, Akzent]
const LOOKS := {
	"fuchs": [Color("d9762a"), Color("fff1e0"), Color("3f6e8c"), Color("e8c872")],
	"dachs": [Color("6e6a66"), Color("f2f0ea"), Color("7a4a2a"), Color("c0392b")],
	"hase": [Color("c9b49a"), Color("fbf4ea"), Color("6f9a3a"), Color("f0a8c8")],
	"baer": [Color("7a5032"), Color("c89a6a"), Color("8c2f39"), Color("e8c872")],
	"igel": [Color("8a6a4a"), Color("f0dcc0"), Color("4f7f9f"), Color("e8a040")],
	"eule": [Color("9a7a5a"), Color("efe0c8"), Color("5a6e3a"), Color("f2c230")],
}
const ORDER := ["fuchs", "dachs", "hase", "baer", "igel", "eule"]
const OUTLINE := Color("2a1d16")

var _img: Image


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/npc"))
	var portraits := Image.create(SIZE * 6, SIZE, false, Image.FORMAT_RGBA8)
	var villages := Image.create(SIZE * 6, SIZE, false, Image.FORMAT_RGBA8)
	portraits.fill(Color(0, 0, 0, 0))
	villages.fill(Color(0, 0, 0, 0))
	for i in ORDER.size():
		var animal: String = ORDER[i]
		portraits.blit_rect(_portrait(animal), Rect2i(0, 0, SIZE, SIZE), Vector2i(i * SIZE, 0))
		villages.blit_rect(_village(animal, i), Rect2i(0, 0, SIZE, SIZE), Vector2i(i * SIZE, 0))
	portraits.save_png(ProjectSettings.globalize_path("res://assets/npc/Portraits.png"))
	villages.save_png(ProjectSettings.globalize_path("res://assets/npc/Doerfer.png"))
	print("gespeichert: assets/npc/Portraits.png, assets/npc/Doerfer.png")
	quit()


# ---------------------------------------------------------- Zeichenhilfen

func _canvas() -> void:
	_img = Image.create(SIZE * S, SIZE * S, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0))


func _finish() -> Image:
	_img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return _img


func _blend(x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= _img.get_width() or y >= _img.get_height():
		return
	var dst := _img.get_pixel(x, y)
	var a := c.a + dst.a * (1.0 - c.a)
	if a <= 0.0:
		return
	var rgb := (Color(c.r, c.g, c.b) * c.a + Color(dst.r, dst.g, dst.b) * dst.a * (1.0 - c.a)) / a
	_img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))


## Gefuellte Ellipse (Koordinaten in 256er-Einheiten), optional gedreht (Grad).
func ellipse(cx: float, cy: float, rx: float, ry: float, c: Color, rot := 0.0, outline := 0.0) -> void:
	if outline > 0.0:
		ellipse(cx, cy, rx + outline, ry + outline, OUTLINE, rot)
	var r := deg_to_rad(rot)
	var cr := cos(r)
	var sr := sin(r)
	var m := maxf(rx, ry)
	for y in range(int((cy - m) * S), int((cy + m) * S) + 1):
		for x in range(int((cx - m) * S), int((cx + m) * S) + 1):
			var dx := x / float(S) - cx
			var dy := y / float(S) - cy
			var u := dx * cr + dy * sr
			var v := -dx * sr + dy * cr
			if (u * u) / (rx * rx) + (v * v) / (ry * ry) <= 1.0:
				_blend(x, y, c)


## Gefuelltes Vieleck (Punkte in 256er-Einheiten).
func poly(points: Array, c: Color, outline := 0.0) -> void:
	if outline > 0.0:
		var center := Vector2.ZERO
		for p in points:
			center += p
		center /= points.size()
		var big := []
		for p in points:
			big.append(p + (p - center).normalized() * outline)
		poly(big, OUTLINE)
	var pts := PackedVector2Array()
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for p in points:
		pts.append(p * S)
		minp = minp.min(p * S)
		maxp = maxp.max(p * S)
	for y in range(int(minp.y), int(maxp.y) + 1):
		for x in range(int(minp.x), int(maxp.x) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x, y), pts):
				_blend(x, y, c)


func line(a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var steps := int(a.distance_to(b) * 2.0) + 1
	for i in steps + 1:
		var p := a.lerp(b, i / float(steps))
		ellipse(p.x, p.y, width * 0.5, width * 0.5, c)


# ----------------------------------------------------------------- Tiere

## Kopf + Oberkoerper eines Tiers. (cx, cy) = Kopfmitte, k = Groesse (1 = Portraet).
func animal(kind: String, cx: float, cy: float, k: float, body := true) -> void:
	var look: Array = LOOKS[kind]
	var fur: Color = look[0]
	var light: Color = look[1]
	var cloth: Color = look[2]
	var accent: Color = look[3]
	var o := 3.0 * k
	if body:
		# Schultern mit Kleidung (Weste/Jacke) und Halstuch
		ellipse(cx, cy + 95 * k, 70 * k, 48 * k, cloth, 0, o)
		poly([Vector2(cx - 18 * k, cy + 52 * k), Vector2(cx + 18 * k, cy + 52 * k), Vector2(cx, cy + 95 * k)], light)
		ellipse(cx, cy + 50 * k, 30 * k, 11 * k, accent, 0, o * 0.7)
		ellipse(cx - 28 * k, cy + 92 * k, 5 * k, 5 * k, accent)
		ellipse(cx + 28 * k, cy + 92 * k, 5 * k, 5 * k, accent)
	match kind:
		"fuchs":
			poly([Vector2(cx - 50 * k, cy - 20 * k), Vector2(cx - 40 * k, cy - 78 * k), Vector2(cx - 12 * k, cy - 38 * k)], fur, o)
			poly([Vector2(cx + 50 * k, cy - 20 * k), Vector2(cx + 40 * k, cy - 78 * k), Vector2(cx + 12 * k, cy - 38 * k)], fur, o)
			poly([Vector2(cx - 40 * k, cy - 30 * k), Vector2(cx - 37 * k, cy - 62 * k), Vector2(cx - 22 * k, cy - 38 * k)], Color("3a2418"))
			poly([Vector2(cx + 40 * k, cy - 30 * k), Vector2(cx + 37 * k, cy - 62 * k), Vector2(cx + 22 * k, cy - 38 * k)], Color("3a2418"))
			ellipse(cx, cy, 50 * k, 44 * k, fur, 0, o)
			poly([Vector2(cx - 48 * k, cy + 2 * k), Vector2(cx + 48 * k, cy + 2 * k), Vector2(cx, cy + 46 * k)], light)
			ellipse(cx, cy + 30 * k, 7 * k, 5 * k, OUTLINE)
		"dachs":
			ellipse(cx - 40 * k, cy - 30 * k, 12 * k, 12 * k, fur, 0, o)
			ellipse(cx + 40 * k, cy - 30 * k, 12 * k, 12 * k, fur, 0, o)
			ellipse(cx, cy + 4 * k, 50 * k, 46 * k, light, 0, o)
			ellipse(cx - 22 * k, cy - 2 * k, 10 * k, 34 * k, Color("2a2a2a"), -8)
			ellipse(cx + 22 * k, cy - 2 * k, 10 * k, 34 * k, Color("2a2a2a"), 8)
			ellipse(cx, cy + 30 * k, 8 * k, 6 * k, OUTLINE)
		"hase":
			ellipse(cx - 20 * k, cy - 70 * k, 12 * k, 42 * k, fur, -10, o)
			ellipse(cx + 20 * k, cy - 70 * k, 12 * k, 42 * k, fur, 10, o)
			ellipse(cx - 20 * k, cy - 68 * k, 6 * k, 32 * k, look[3], -10)
			ellipse(cx + 20 * k, cy - 68 * k, 6 * k, 32 * k, look[3], 10)
			ellipse(cx, cy, 46 * k, 44 * k, fur, 0, o)
			ellipse(cx, cy + 22 * k, 24 * k, 18 * k, light)
			ellipse(cx, cy + 16 * k, 6 * k, 4 * k, Color("d06080"))
			line(Vector2(cx, cy + 20 * k), Vector2(cx, cy + 30 * k), 2.0 * k, OUTLINE)
		"baer":
			ellipse(cx - 40 * k, cy - 36 * k, 16 * k, 16 * k, fur, 0, o)
			ellipse(cx + 40 * k, cy - 36 * k, 16 * k, 16 * k, fur, 0, o)
			ellipse(cx - 40 * k, cy - 36 * k, 8 * k, 8 * k, light)
			ellipse(cx + 40 * k, cy - 36 * k, 8 * k, 8 * k, light)
			ellipse(cx, cy, 54 * k, 48 * k, fur, 0, o)
			ellipse(cx, cy + 22 * k, 24 * k, 18 * k, light)
			ellipse(cx, cy + 14 * k, 9 * k, 6 * k, OUTLINE)
		"igel":
			# Stacheln hinter dem Kopf
			for i in 11:
				var a := deg_to_rad(-170 + i * 16)
				var base := Vector2(cx, cy - 4 * k)
				poly([base + Vector2(cos(a - 0.25), sin(a - 0.25)) * 40 * k,
					base + Vector2(cos(a), sin(a)) * 74 * k,
					base + Vector2(cos(a + 0.25), sin(a + 0.25)) * 40 * k], Color("4a3424"), o * 0.6)
			ellipse(cx, cy + 6 * k, 44 * k, 40 * k, light, 0, o)
			ellipse(cx, cy + 26 * k, 7 * k, 6 * k, OUTLINE)
		"eule":
			poly([Vector2(cx - 46 * k, cy - 22 * k), Vector2(cx - 44 * k, cy - 64 * k), Vector2(cx - 20 * k, cy - 36 * k)], fur, o)
			poly([Vector2(cx + 46 * k, cy - 22 * k), Vector2(cx + 44 * k, cy - 64 * k), Vector2(cx + 20 * k, cy - 36 * k)], fur, o)
			ellipse(cx, cy, 52 * k, 48 * k, fur, 0, o)
			ellipse(cx - 22 * k, cy - 2 * k, 22 * k, 22 * k, light)
			ellipse(cx + 22 * k, cy - 2 * k, 22 * k, 22 * k, light)
			poly([Vector2(cx - 7 * k, cy + 12 * k), Vector2(cx + 7 * k, cy + 12 * k), Vector2(cx, cy + 28 * k)], Color("e8a040"), o * 0.5)
	# Augen (bei der Eule gross), Wangen
	var eye_r := 9.0 if kind == "eule" else 6.5
	var ey := cy - 4 * k
	for side in [-1, 1]:
		var ex: float = cx + side * 22 * k
		ellipse(ex, ey, eye_r * k, eye_r * k, Color.WHITE, 0, o * 0.6)
		ellipse(ex + 1.5 * k, ey + 1 * k, eye_r * 0.55 * k, eye_r * 0.55 * k, OUTLINE)
		ellipse(ex + 3 * k, ey - 2 * k, 1.8 * k, 1.8 * k, Color.WHITE)
		if kind != "eule":
			ellipse(cx + side * 34 * k, cy + 16 * k, 8 * k, 5 * k, Color(1, 0.5, 0.5, 0.45))


func _portrait(kind: String) -> Image:
	_canvas()
	var look: Array = LOOKS[kind]
	# Medaillon mit Holzrahmen
	ellipse(128, 128, 124, 124, Color("6b4428"))
	ellipse(128, 128, 114, 114, Color("e9dcc0"))
	ellipse(128, 150, 112, 70, (look[2] as Color).lightened(0.55))
	animal(kind, 128, 120, 1.0)
	# Rahmen vorne nochmal, damit die Schultern innen bleiben
	var tmp := _img
	var mask := Image.create(SIZE * S, SIZE * S, false, Image.FORMAT_RGBA8)
	mask.fill(Color(0, 0, 0, 0))
	for y in SIZE * S:
		for x in SIZE * S:
			var d := Vector2(x, y).distance_to(Vector2(128 * S, 128 * S))
			if d > 114 * S and d <= 124 * S:
				tmp.set_pixel(x, y, Color("6b4428").lerp(Color("8a5a36"), clampf((124 * S - d) / (10.0 * S), 0, 1)))
			elif d > 124 * S:
				tmp.set_pixel(x, y, Color(0, 0, 0, 0))
	return _finish()


func _hut(cx: float, ground: float, w: float, roof: Color) -> void:
	# Runde Huette mit Strohdach und Tuer
	ellipse(cx, ground - w * 0.35, w * 0.55, w * 0.42, Color("c8a878"), 0, 2.5)
	ellipse(cx, ground - w * 0.18, w * 0.16, w * 0.24, Color("4a2e1c"))
	poly([Vector2(cx - w * 0.75, ground - w * 0.55), Vector2(cx + w * 0.75, ground - w * 0.55),
		Vector2(cx, ground - w * 1.35)], roof, 2.5)
	for i in 4:
		line(Vector2(cx - w * 0.55 + i * w * 0.37, ground - w * 0.6), Vector2(cx, ground - w * 1.25), 1.5, roof.darkened(0.25))


func _village(kind: String, index: int) -> Image:
	_canvas()
	var look: Array = LOOKS[kind]
	var ground := 150.0
	# Weg und Zaun
	ellipse(128, ground + 6, 96, 22, Color(0.55, 0.42, 0.28, 0.55))
	_hut(78, ground - 4, 58, Color("d8b04a"))
	_hut(168, ground - 14, 46, Color("c89a3a"))
	for i in 7:
		var x := 40.0 + i * 13.0
		line(Vector2(x, ground + 18), Vector2(x, ground + 2), 3.0, Color("6b4428"))
	line(Vector2(36, ground + 8), Vector2(122, ground + 8), 2.5, Color("6b4428"))
	# Fahne mit Tierfarbe
	line(Vector2(206, ground + 8), Vector2(206, ground - 92), 3.0, Color("4a2e1c"))
	poly([Vector2(207, ground - 92), Vector2(240, ground - 82), Vector2(207, ground - 70)], look[3], 2.0)
	# Tierfigur vorne
	ellipse(146, ground + 26, 26, 8, Color(0, 0, 0, 0.25))
	animal(kind, 146, ground - 30, 0.42)
	return _finish()
