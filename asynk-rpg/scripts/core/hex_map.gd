class_name HexMap
extends RefCounted
## Reine Kartendaten fuer die Spiellogik: welche Hex-Felder begehbar sind
## und wie man von A nach B kommt. Kennt keine Nodes und keine Grafik.
##
## Koordinaten sind dieselben wie in der TileMapLayer (Layout "Diamond Down",
## Offset-Achse vertikal). In diesem Layout hat jedes Feld immer dieselben
## sechs Nachbar-Versaetze, egal in welcher Zeile es liegt.

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1),
]

## Felder der Karte: Vector2i -> true
var _cells: Dictionary = {}
## Gelaendeart je Feld (Terrain.*); fehlt ein Feld, ist es Wiese.
var _types: Dictionary = {}
## Fluesse: Feld -> naechstes Feld flussabwaerts (fuer die Anzeige).
var flow: Dictionary = {}


static func from_cells(cells: Array) -> HexMap:
	var m := HexMap.new()
	for c in cells:
		m._cells[c] = true
	return m


## Aus dem Kartengenerator: Feld -> Gelaendeart.
static func from_types(types: Dictionary, p_flow: Dictionary = {}) -> HexMap:
	var m := HexMap.new()
	for c in types:
		m._cells[c] = true
		if types[c] != Terrain.GRASS:
			m._types[c] = types[c]
	m.flow = p_flow
	return m


## Liegt das Feld auf der Karte? (Ob man es betreten kann, entscheidet
## GameRules.step_cost je nach Gelaende und Jahreszeit.)
func is_walkable(cell: Vector2i) -> bool:
	return _cells.has(cell)


func kind_at(cell: Vector2i) -> String:
	return _types.get(cell, Terrain.GRASS)


func is_land(cell: Vector2i) -> bool:
	var k := kind_at(cell)
	return _cells.has(cell) and (k == Terrain.GRASS or k == Terrain.BEACH)


func cells() -> Array:
	return _cells.keys()


func cell_count() -> int:
	return _cells.size()


func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for o in NEIGHBOR_OFFSETS:
		var n := cell + o
		if is_walkable(n):
			result.append(n)
	return result


func are_neighbors(a: Vector2i, b: Vector2i) -> bool:
	return NEIGHBOR_OFFSETS.has(b - a)


## Kuerzester Weg. Liefert die Felder NACH dem Start bis einschliesslich Ziel,
## oder [] wenn es keinen Weg gibt.
## blocked: Felder, die nicht betreten werden duerfen (z.B. andere Figuren).
## max_steps: Budget (-1 = unbegrenzt).
## cost: Callable(cell) -> Schritte zum Betreten (0 = gesperrt); ohne = 1 je Feld.
func find_path(from: Vector2i, to: Vector2i, blocked: Array = [], max_steps: int = -1,
		cost: Callable = Callable()) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if from == to or not is_walkable(to) or blocked.has(to):
		return empty
	var came := _search(from, blocked, max_steps, cost, to)
	if not came.has(to):
		return empty
	var path: Array[Vector2i] = []
	var c := to
	while c != from:
		path.push_front(c)
		c = came[c]
	return path


## Summe der Schritte fuer einen Weg (ohne Startfeld).
func path_cost(path: Array, cost: Callable = Callable()) -> int:
	var total := 0
	for c in path:
		total += cost.call(c) if cost.is_valid() else 1
	return total


## Alle Felder, die mit hoechstens max_steps erreichbar sind, nach Entfernung
## sortiert (Startfeld zuerst). Fuer die KI und die Startfelder.
func reachable(from: Vector2i, blocked: Array = [], max_steps: int = -1, cost: Callable = Callable()) -> Array[Vector2i]:
	var dist := {}
	_search(from, blocked, max_steps, cost, Vector2i(2147483647, 0), dist)
	# Nach Entfernung, bei Gleichstand in Entdeckungsreihenfolge (stabil).
	var by_dist := {}
	var top := 0
	for c in dist:
		var d: int = dist[c]
		if not by_dist.has(d):
			by_dist[d] = []
		by_dist[d].append(c)
		top = maxi(top, d)
	var out: Array[Vector2i] = []
	for d in top + 1:
		for c in by_dist.get(d, []):
			out.append(c)
	return out


## Dijkstra (bei Kosten 1 wie Breitensuche). Liefert "kam von"-Tabelle,
## fuellt optional dist_out.
func _search(from: Vector2i, blocked: Array, max_steps: int, cost: Callable, target: Vector2i,
		dist_out: Dictionary = {}) -> Dictionary:
	var came := {from: from}
	var dist := dist_out
	dist[from] = 0
	# Einfache Prioritaetsliste nach Kosten (Kosten sind klein: 1..3).
	var buckets := {0: [from]}
	var current := 0
	var max_cost := 0
	while current <= max_cost:
		var bucket: Array = buckets.get(current, [])
		var i := 0
		while i < bucket.size():
			var cur: Vector2i = bucket[i]
			i += 1
			if dist[cur] != current:
				continue
			if cur == target:
				return came
			for n in neighbors(cur):
				if blocked.has(n):
					continue
				var step: int = cost.call(n) if cost.is_valid() else 1
				if step <= 0:
					continue
				var nd := current + step
				if max_steps >= 0 and nd > max_steps:
					continue
				if not dist.has(n) or nd < dist[n]:
					dist[n] = nd
					came[n] = cur
					if not buckets.has(nd):
						buckets[nd] = []
					buckets[nd].append(n)
					max_cost = maxi(max_cost, nd)
		buckets.erase(current)
		current += 1
	return came
