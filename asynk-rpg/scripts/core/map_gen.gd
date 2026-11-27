class_name MapGen
extends RefCounted
## Erzeugt Karten aus Seed + Vorlage + Groesse. Gleiche Einstellungen ergeben
## auf jedem Geraet dieselbe Karte, deshalb reicht es im LAN, nur die
## Einstellungen zu verschicken. Reine Logik, ohne Szene.
##
## Ergebnis von generate():
##   {"types": {Vector2i: Terrain.*}, "flow": {Fluss-Feld: naechstes Feld},
##    "objects": {id: kind} (Baeume, Steine, Pfuetzen, Fischgruende, Doerfer),
##    "start": Vector2i (Startfeld, Land in der Naehe der Mitte)}
##
## Koordinaten wie in der TileMapLayer: Feld (x, y) liegt auf dem Bildschirm bei
## (192*(x-y), 63.5*(x+y)). Eine rechteckige Karte hat Spalten u = x-y und
## Zeilen v = x+y (u und v haben dieselbe Paritaet).

const PRESET_STANDARD := "standard"
const PRESET_CONTINENTS := "continents"
const PRESET_ISLANDS := "islands"
const PRESET_PANGAEA := "pangaea"
const PRESET_INLAND := "inland"
const PRESET_COAST := "coast"
## Reihenfolge in der Lobby. "standard" = die handgemalte Karte der Szene.
const PRESETS := [PRESET_STANDARD, PRESET_CONTINENTS, PRESET_ISLANDS, PRESET_PANGAEA, PRESET_INLAND, PRESET_COAST]
const PRESET_NAMES := {
	PRESET_STANDARD: "Standardkarte (gemalt)", PRESET_CONTINENTS: "Kontinente",
	PRESET_ISLANDS: "Inseln", PRESET_PANGAEA: "Pangäa", PRESET_INLAND: "Binnenland mit Seen",
	PRESET_COAST: "Küste",
}
const SIZES := {"small": 40, "medium": 70, "large": 100, "huge": 150}
const SIZE_ORDER := ["small", "medium", "large", "huge"]
const SIZE_NAMES := {"small": "Klein (40×40)", "medium": "Mittel (70×70)", "large": "Groß (100×100)", "huge": "Riesig (150×150)"}

## Hoehen-Grenzen fuer das Meer (darunter) bis Wiese (darueber).
const LEVELS := [[-0.45, Terrain.OCEAN], [-0.26, Terrain.DEEP], [-0.11, Terrain.SHALLOW],
	[-0.04, Terrain.FLAT], [0.03, Terrain.BEACH]]


static func default_settings() -> Dictionary:
	return {"preset": PRESET_STANDARD, "size": "medium", "seed": 0}


static func is_generated(settings: Dictionary) -> bool:
	return str(settings.get("preset", PRESET_STANDARD)) != PRESET_STANDARD


## Feld -> ungefaehre Bildschirmposition in "Feldbreiten" (fuer das Rauschen).
static func cell_pos(c: Vector2i) -> Vector2:
	return Vector2((c.x - c.y) * 1.0, (c.x + c.y) * 0.33)


static func generate(settings: Dictionary) -> Dictionary:
	var preset := str(settings.get("preset", PRESET_CONTINENTS))
	var n: int = SIZES.get(str(settings.get("size", "medium")), 70)
	var seed_value := int(settings.get("seed", 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, preset, n])

	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.fractal_octaves = 4
	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 101
	detail.frequency = 0.15
	var lakes := FastNoiseLite.new()
	lakes.seed = seed_value + 202
	lakes.frequency = 0.09
	var forest := FastNoiseLite.new()
	forest.seed = seed_value + 303
	forest.frequency = 0.07

	# Rauschfrequenz je Vorlage: wenige grosse oder viele kleine Landmassen.
	noise.frequency = {PRESET_CONTINENTS: 2.2, PRESET_ISLANDS: 5.0, PRESET_PANGAEA: 1.6,
		PRESET_INLAND: 2.0, PRESET_COAST: 2.0}.get(preset, 2.2) / float(n)

	var cells: Array[Vector2i] = []
	var height := {}
	for u in n:
		for r in n:
			var v := 2 * r + (u % 2)
			var c := Vector2i((u + v) / 2, (v - u) / 2)
			# Verschieben, damit die Kartenmitte bei (0, 0) liegt.
			c -= Vector2i(3 * n / 4, n / 4)
			cells.append(c)
			var nx := (u / float(n - 1)) * 2.0 - 1.0
			var ny := (r / float(n - 1)) * 2.0 - 1.0
			var p := cell_pos(c)
			var e := noise.get_noise_2d(p.x, p.y) + detail.get_noise_2d(p.x, p.y) * 0.12
			var d := sqrt(nx * nx + ny * ny)
			var edge := maxf(absf(nx), absf(ny))
			match preset:
				PRESET_PANGAEA:
					e = e * 0.55 + 0.5 - 1.25 * d * d
				PRESET_CONTINENTS:
					e = e * 1.1 + 0.05 - 0.9 * pow(edge, 6.0)
				PRESET_ISLANDS:
					e = e * 1.0 - 0.12 - 0.8 * pow(edge, 6.0)
				PRESET_INLAND:
					e = 0.45 + e * 0.25 - 0.8 * pow(edge, 12.0)
				PRESET_COAST:
					e = nx * 0.85 + e * 0.55 - 0.6 * pow(absf(ny), 10.0) * (1.0 if nx > 0.3 else 0.0)
			height[c] = e

	var types := {}
	for c in cells:
		types[c] = _classify(height[c])

	# Binnenseen und Teiche auf dem Land
	var lake_limit := -0.42 if preset == PRESET_INLAND else -0.55
	for c in cells:
		if types[c] == Terrain.GRASS and height[c] > 0.08:
			var p := cell_pos(c)
			if lakes.get_noise_2d(p.x, p.y) < lake_limit:
				types[c] = Terrain.LAKE
	# Sehr kleine Seen (1-2 Felder) werden Teiche
	for comp in _components(types, Terrain.LAKE):
		if comp.size() <= 2:
			for c in comp:
				types[c] = Terrain.POND
	var ponds := maxi(2, n * n / 600)
	for i in ponds:
		var c: Vector2i = cells[rng.randi() % cells.size()]
		if types[c] == Terrain.GRASS and _count_kind(types, c, Terrain.GRASS) >= 5:
			types[c] = Terrain.POND

	# Fluesse: von hohen Stellen bergab bis zum Wasser
	var flow := {}
	var land := cells.filter(func(c): return types[c] == Terrain.GRASS and height[c] > 0.3)
	var rivers := maxi(1, n / 12)
	for i in rivers:
		if land.is_empty():
			break
		var start: Vector2i = land[rng.randi() % land.size()]
		_carve_river(start, types, height, flow, rng, n * 3)

	var objects := _place_objects(cells, types, rng, forest)
	var start_cell := _start_cell(types)
	return {"types": types, "flow": flow, "objects": objects, "start": start_cell}


static func _classify(e: float) -> String:
	for level in LEVELS:
		if e < level[0]:
			return level[1]
	return Terrain.GRASS


static func _neighbors(types: Dictionary, c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for o in HexMap.NEIGHBOR_OFFSETS:
		if types.has(c + o):
			out.append(c + o)
	return out


static func _count_kind(types: Dictionary, c: Vector2i, kind: String) -> int:
	var k := 0
	for nb in _neighbors(types, c):
		if types[nb] == kind:
			k += 1
	return k


static func _components(types: Dictionary, kind: String) -> Array:
	var seen := {}
	var out := []
	for c in types:
		if types[c] != kind or seen.has(c):
			continue
		var comp := [c]
		seen[c] = true
		var i := 0
		while i < comp.size():
			for nb in _neighbors(types, comp[i]):
				if types[nb] == kind and not seen.has(nb):
					seen[nb] = true
					comp.append(nb)
			i += 1
		out.append(comp)
	return out


static func _carve_river(start: Vector2i, types: Dictionary, height: Dictionary, flow: Dictionary,
		rng: RandomNumberGenerator, max_len: int) -> void:
	var path: Array[Vector2i] = [start]
	var visited := {start: true}
	var cur := start
	for step in max_len:
		var best := Vector2i.ZERO
		var best_h := INF
		var found := false
		for nb in _neighbors(types, cur):
			if visited.has(nb):
				continue
			var h: float = height[nb] + rng.randf() * 0.04
			if h < best_h:
				best_h = h
				best = nb
				found = true
		if not found:
			break
		visited[best] = true
		var t: String = types[best]
		if t != Terrain.GRASS and t != Terrain.BEACH and t != Terrain.RIVER:
			flow[cur] = best  # muendet in Meer/See/Teich
			break
		path.append(best)
		flow[cur] = best
		if t == Terrain.RIVER:
			break  # trifft auf einen anderen Fluss
		cur = best
	if path.size() < 4:
		for c in path:
			flow.erase(c)
		return
	for c in path:
		if types[c] == Terrain.GRASS or types[c] == Terrain.BEACH:
			types[c] = Terrain.RIVER
	# Endet der Fluss im Nichts (Senke), entsteht dort ein Teich.
	var last: Vector2i = path[-1]
	if not flow.has(last):
		types[last] = Terrain.POND


static func _place_objects(cells: Array, types: Dictionary, rng: RandomNumberGenerator, forest: FastNoiseLite) -> Dictionary:
	var objects := {}
	for c in cells:
		var t: String = types[c]
		if t == Terrain.GRASS:
			var p := cell_pos(c)
			var wood := forest.get_noise_2d(p.x, p.y)
			var tree_chance := 0.6 if wood > 0.25 else 0.1
			if rng.randf() < tree_chance:
				objects[WorldObjects.make_id(c, WorldObjects.SLOT_LEFT)] = ResourceConfig.TREE_KINDS[rng.randi() % 4]
			if rng.randf() < 0.06:
				objects[WorldObjects.make_id(c, WorldObjects.SLOT_RIGHT)] = ResourceConfig.KIND_STONE
			elif rng.randf() < 0.02 and not objects.has(WorldObjects.make_id(c, WorldObjects.SLOT_LEFT)):
				objects[WorldObjects.make_id(c, WorldObjects.SLOT_TERRAIN)] = ResourceConfig.KIND_PUDDLE
		elif t == Terrain.BEACH and rng.randf() < 0.05:
			objects[WorldObjects.make_id(c, WorldObjects.SLOT_RIGHT)] = ResourceConfig.KIND_STONE
		elif Terrain.is_water(t):
			# Fischgrund nur dort, wo man vom Land/Ufer hinkommt.
			for nb in _neighbors(types, c):
				var nt: String = types[nb]
				if nt == Terrain.GRASS or nt == Terrain.BEACH or nt == Terrain.FLAT or nt == Terrain.RIVER:
					objects[WorldObjects.make_id(c, WorldObjects.SLOT_WATER)] = t
					break
	return objects


## Startfeld: Wiese moeglichst nah an der Mitte, im groessten Landstueck.
static func _start_cell(types: Dictionary) -> Vector2i:
	var walk := {}
	for c in types:
		var t: String = types[c]
		walk[c] = "land" if t == Terrain.GRASS or t == Terrain.BEACH or t == Terrain.FLAT or t == Terrain.RIVER else "x"
	var biggest: Array = []
	for comp in _components(walk, "land"):
		if comp.size() > biggest.size():
			biggest = comp
	var best := Vector2i.ZERO
	var best_d := INF
	for c in biggest:
		if types[c] != Terrain.GRASS:
			continue
		var d := cell_pos(c).length()
		if d < best_d:
			best_d = d
			best = c
	return best
