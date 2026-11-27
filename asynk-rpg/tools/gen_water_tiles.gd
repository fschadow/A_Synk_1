extends SceneTree
## Erzeugt die Wasser-Tiles im gemalten Stil der vorhandenen Gelaende-Tiles
## (Hexfeld 256x128 mit flacher Ober-/Unterkante, Mitte bei (128,129) in
## einer 256er-Kachel, 3 px schwarzer Rand, weiche Farbe ueber den Rand).
##
##   godot --headless --path asynk-rpg -s res://tools/gen_water_tiles.gd
##
## Ergebnis (zum Uebermalen in Krita gedacht):
##   assets/tiles/Tiles-Wasser.png  Zeilen = Art (siehe Terrain.WATER_ROWS),
##                                  Spalten 0-3 = Fruehling..Winter, 4 = gefroren
##   assets/tiles/Tiles-Fluss.png   Zeilen = Fliessrichtung 0-5 (N, NO, SO, S, SW, NW),
##                                  Spalten 0-3 = Fruehling..Winter, 4 = gefroren
##   assets/tiles/templates/hex_vorlage.png  leere Kachel mit Hexrand
##
## Gleicher Seed = gleiches Bild; zum Neuerzeugen einfach nochmal starten.

const CELL := 256
const CX := 128.0
const CY := 129.0
const HALF_H := 64.0
const SPILL := 22.0
const FROZEN := 4

## Fluss-Richtungen als Bildschirmwinkel (Grad, 0 = rechts, im Uhrzeigersinn):
## N, NO, SO, S, SW, NW (Nachbar-Mittelpunkte eines Hexfelds mit flacher Oberkante).
const RIVER_ANGLES := [-90.0, -18.43, 18.43, 90.0, 161.57, 198.43]

var _noise := FastNoiseLite.new()
var _fine := FastNoiseLite.new()
var _edge := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_noise.seed = 1337
	_noise.frequency = 0.012
	_noise.fractal_octaves = 3
	_fine.seed = 4242
	_fine.frequency = 0.09
	_edge.seed = 777
	_edge.frequency = 0.05
	var t0 := Time.get_ticks_msec()

	var water := _atlas()
	for row in Terrain.WATER_ROWS.size():
		var kind: String = Terrain.WATER_ROWS[row]
		for season in 5:
			if season == FROZEN and not Terrain.FREEZES.has(kind):
				continue
			_paint_tile(water, Vector2i(season, row), kind, season, 0.0)
	_save(water, "res://assets/tiles/Tiles-Wasser.png")

	var river := _atlas()
	for dir in 6:
		for season in 5:
			_paint_tile(river, Vector2i(season, dir), Terrain.RIVER, season, RIVER_ANGLES[dir])
	_save(river, "res://assets/tiles/Tiles-Fluss.png")

	var tpl := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	tpl.fill(Color(0, 0, 0, 0))
	for y in CELL:
		for x in CELL:
			if absf(_hex_dist(x, y)) < 1.6:
				tpl.set_pixel(x, y, Color.BLACK)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/tiles/templates"))
	_save(tpl, "res://assets/tiles/templates/hex_vorlage.png")
	print("Fertig in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


func _atlas() -> Image:
	var img := Image.create(CELL * 8, CELL * 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


func _save(img: Image, path: String) -> void:
	img.save_png(ProjectSettings.globalize_path(path))
	print("gespeichert: ", path)


## Abstand zum Hexrand (negativ = innen), Hexfeld mit flacher Ober-/Unterkante.
static func _hex_dist(x: float, y: float) -> float:
	var dx := absf(x - CX)
	var dy := absf(y - CY)
	var d_flat := dy - HALF_H
	var d_slant := (dx + dy - 128.0) * 0.7071
	return maxf(d_flat, d_slant)


# --------------------------------------------------------------- Farben

## Jahreszeiten-Farbton fuer Wasser: [hell, mittel, dunkel].
func _water_colors(kind: String, season: int) -> Array:
	var base: Array = {
		Terrain.FLAT: [Color("bfe6d8"), Color("8fd0c4"), Color("5fae9f")],
		Terrain.SHALLOW: [Color("8fe0dc"), Color("3fb3c0"), Color("2a8a9e")],
		Terrain.DEEP: [Color("4f9fd0"), Color("2a6fae"), Color("1d4f86")],
		Terrain.OCEAN: [Color("3a6fa8"), Color("1f4a80"), Color("10305a")],
		Terrain.POND: [Color("7fb8a0"), Color("4f8f78"), Color("2f6050")],
		Terrain.LAKE: [Color("6fb0d0"), Color("3a80b0"), Color("245a88")],
		Terrain.RIVER: [Color("9fd4e0"), Color("4a9cc0"), Color("2a6f98")],
	}[kind]
	var tint: Color = [Color(0.92, 1.05, 0.95), Color(1.05, 1.08, 1.0), Color(0.9, 0.88, 0.8), Color(0.78, 0.82, 0.9)][season]
	var out := []
	for c in base:
		out.append(Color(c.r * tint.r, c.g * tint.g, c.b * tint.b))
	return out


## Uferfarbe (Gras) je Jahreszeit, passend zu den gemalten Boden-Tiles.
func _grass(season: int) -> Array:
	return [
		[Color("6f9a2a"), Color("3b6400"), Color("2a4a08")],
		[Color("7faa3a"), Color("4d6f2c"), Color("2f4a18")],
		[Color("a8a840"), Color("7f8c25"), Color("5a5a18")],
		[Color("f2f2ff"), Color("d6d8fa"), Color("a8aed8")],
		[Color("f2f2ff"), Color("d6d8fa"), Color("a8aed8")],
	][season]


func _sand(season: int) -> Array:
	var s := [Color("f2dfa8"), Color("e0c27a"), Color("b8975a")]
	if season == 3:
		s = [Color("f4f2ea"), Color("ddd6c0"), Color("b0a890")]
	elif season == 2:
		s = [Color("e8d49a"), Color("cfb070"), Color("a08050")]
	return s


func _ice() -> Array:
	return [Color("f4fbff"), Color("cfe6f4"), Color("8fb4d0")]


static func _mix3(cols: Array, t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	if t < 0.5:
		return (cols[0] as Color).lerp(cols[1], t * 2.0)
	return (cols[1] as Color).lerp(cols[2], (t - 0.5) * 2.0)


# --------------------------------------------------------------- Malen

func _paint_tile(img: Image, slot: Vector2i, kind: String, season: int, angle_deg: float) -> void:
	_rng.seed = hash([kind, season, angle_deg])
	var ox := slot.x * CELL
	var oy := slot.y * CELL
	var seed_off := Vector2(_rng.randf() * 1000.0, _rng.randf() * 1000.0)
	var a := deg_to_rad(angle_deg)
	var flow := Vector2(cos(a), sin(a))
	var frozen := season == FROZEN
	# Ein paar Farbtupfer (Seerosen, Laub, Muscheln) vorab festlegen.
	var dots := []
	for i in 14:
		dots.append(Vector3(CX + _rng.randf_range(-90, 90), CY + _rng.randf_range(-44, 44), _rng.randf_range(4, 9)))
	for y in CELL:
		for x in CELL:
			var d := _hex_dist(x, y)
			var alpha := 1.0
			if d > 0.0:
				# Weiche, ausgefranste Farbe ueber den Rand wie bei den gemalten Tiles.
				var n := (_edge.get_noise_2d(x + seed_off.x, y + seed_off.y) + 1.0) * 0.5
				alpha = clampf(1.0 - d / (SPILL * (0.35 + n)), 0.0, 1.0)
				if alpha <= 0.02:
					continue
			var c := _pixel(kind, season, frozen, x, y, d, seed_off, flow, dots)
			if absf(d) < 1.6:
				c = Color(0.02, 0.02, 0.02)
				alpha = 1.0
			c.a = alpha
			img.set_pixel(ox + x, oy + y, c)


func _pixel(kind: String, season: int, frozen: bool, x: float, y: float, d: float,
		off: Vector2, flow: Vector2, dots: Array) -> Color:
	var px := x + off.x
	var py := y + off.y
	# Pinselstriche: Rauschen in einer Richtung gestreckt.
	var stroke := (_noise.get_noise_2d(px * 0.45, py * 1.7) + 1.0) * 0.5
	var fine := _fine.get_noise_2d(px, py) * 0.08

	if kind == Terrain.BEACH:
		var s := _sand(season)
		var c := _mix3(s, stroke * 0.8 + fine + 0.1)
		# Wellenspur zum Wasser hin (unten) und Kiesel/Muscheln
		var wet := smoothstep(20.0, 60.0, y - CY + stroke * 20.0)
		c = c.lerp(Color("c9b27a") if season != 3 else Color("c8c8c8"), wet * 0.35)
		if season == 3 and stroke > 0.62:
			c = c.lerp(Color("ffffff"), 0.7)
		for dot in dots.slice(0, 6):
			if Vector2(x, y).distance_to(Vector2(dot.x, dot.y)) < dot.z * 0.35:
				c = c.lerp(Color("f8f0e0"), 0.8)
		return c

	var shore := 0.0  # 1 = Ufergras (Teich/See)
	if kind == Terrain.POND or kind == Terrain.LAKE:
		var r := Vector2((x - CX) / 128.0, (y - CY) / 64.0).length()
		var limit := (0.62 if kind == Terrain.POND else 0.8) + _edge.get_noise_2d(px * 2.0, py * 2.0) * 0.12
		shore = smoothstep(limit - 0.03, limit + 0.05, r)
		if d > -6.0:
			shore = 1.0

	var col: Color
	if frozen:
		var ice := _ice()
		col = _mix3(ice, stroke * 0.7 + fine)
		# Risse im Eis
		var crack := absf(_edge.get_noise_2d(px * 1.3, py * 2.6))
		if crack < 0.025:
			col = col.lerp(Color("6f94b4"), 0.8)
		if _noise.get_noise_2d(px * 0.8, py * 0.8) > 0.35:
			col = col.lerp(Color("ffffff"), 0.6)  # Schneeverwehung
	else:
		var w := _water_colors(kind, season)
		var t := stroke
		if kind == Terrain.RIVER:
			# Striche entlang der Fliessrichtung
			var u := Vector2(x - CX, y - CY).dot(flow)
			var v := Vector2(x - CX, y - CY).dot(Vector2(-flow.y, flow.x))
			t = (_noise.get_noise_2d(u * 0.22 + off.x, v * 1.6 + off.y) + 1.0) * 0.5
			# Stroemung in der Mitte heller, zu den Ufern dunkler
			var mid := clampf(absf(v) / 60.0, 0.0, 1.0)
			col = _mix3(w, t * 0.6 + mid * 0.2 + fine)
			# Pinsel-Wellen als "V", dessen Spitze flussabwaerts zeigt
			var wobble := _edge.get_noise_2d(u * 0.4 + off.x, v * 0.4) * 6.0
			var chevron := fposmod((u + absf(v) * 0.75 + wobble) / 30.0 + off.y * 0.01, 1.0)
			var broken := _fine.get_noise_2d(u * 0.12 + off.x, v * 0.12) > -0.15
			if chevron < 0.16 and absf(v) < 52.0 and broken:
				col = col.lerp(Color("eef9ff"), 0.75 * (1.0 - chevron / 0.16))
			# Kein Ufer im Tile: Flussfelder fuellen das ganze Hex, damit sie in
			# jeder Richtung aneinanderpassen; das Ufer bilden die Nachbarfelder.
		else:
			# Tiefere Mitte, hellerer Rand
			var depth := clampf(1.0 + d / 50.0, 0.0, 1.0)
			col = _mix3(w, t * 0.6 + depth * 0.35 + fine)
			if kind == Terrain.FLAT:
				col = col.lerp(_mix3(_sand(season), stroke), 0.3)
			# Lichtreflexe / Wellenkaemme
			var crest := (_noise.get_noise_2d(px * 0.3, py * 2.8) + 1.0) * 0.5
			var crest_limit := 0.8 if kind == Terrain.OCEAN else 0.84
			if crest > crest_limit:
				col = col.lerp(Color("f4fbff"), 0.55 if kind == Terrain.OCEAN else 0.4)
		# Seerosen (Fruehling/Sommer) bzw. Laub (Herbst) auf ruhigem Wasser
		if kind == Terrain.POND or kind == Terrain.LAKE or kind == Terrain.FLAT:
			for dot in dots:
				var dd := Vector2(x, y).distance_to(Vector2(dot.x, dot.y * 1.0))
				if dd < dot.z:
					if season <= 1 and kind != Terrain.FLAT:
						col = Color("4f8a2a").lerp(Color("78b040"), dd / dot.z)
						if season == 0 and dd < dot.z * 0.3:
							col = Color("f0a8c8")
					elif season == 2 and dd < dot.z * 0.6:
						col = Color("d07020").lerp(Color("a04010"), dd / dot.z)

	if shore > 0.0:
		var g := _grass(season)
		var gc := _mix3(g, stroke + fine)
		# Schilf am Ufer
		if season < 3 and absf(_fine.get_noise_2d(px * 3.0, py * 0.4)) < 0.04:
			gc = gc.lerp(Color("2a3a10"), 0.6)
		col = col.lerp(gc, shore)
	return col
