class_name MapPainter
extends Node
## Zeichnet die Karte in die TileMap-Ebenen und haelt sie zur Jahreszeit
## passend. Aendert den Spielstand nie, hoert nur auf die GameSession.
## - Generierte Karte (MapGen): Boden, Wasser, Fluesse, Baeume, Steine malen.
## - Jahreszeitenwechsel: Boden/Wasser/Eis und Baeume (Bluete -> Aepfel ->
##   Herbstlaub -> kahl) austauschen; das gilt auch fuer die gemalte
##   Standardkarte.

## Fertig gemalt (ResourceView frischt dann gefaellte/leere Objekte auf).
signal painted(state: GameState)

const GROUND_SOURCE := 1
const WATER_SOURCE := 10
const RIVER_SOURCE := 11
const OBJECT_SOURCE_LEFT := 0
const OBJECT_SOURCE_RIGHT := 2

## Boden je Jahreszeit (Tiles-Teraing.png): Fruehling, Sommer, Herbst, Winter.
const GROUND := [Vector2i(0, 1), Vector2i(2, 0), Vector2i(4, 0), Vector2i(6, 0)]
const GROUND_SPRING_ALT := Vector2i(0, 0)
const PUDDLE := [Vector2i(1, 1), Vector2i(3, 1), Vector2i(5, 1), Vector2i(7, 1)]
## Baum je Jahreszeit (Tiles-Objeckte_O-R.png).
const TREE := [Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0), Vector2i(6, 0)]
const STONE := Vector2i(0, 1)
## Nachbar-Versatz -> Fluss-Richtung im Atlas (N, NO, SO, S, SW, NW).
const FLOW_DIR := {Vector2i(-1, -1): 0, Vector2i(0, -1): 1, Vector2i(1, 0): 2,
	Vector2i(1, 1): 3, Vector2i(0, 1): 4, Vector2i(-1, 0): 5}

var _session: GameSession
var _generated := false
## Zuletzt gemalt: [Jahreszeit, Winterhaerte]
var _painted_for := [-2, -2]


func _ready() -> void:
	_session = get_tree().get_first_node_in_group(GameSession.GROUP) as GameSession
	if _session == null:
		return
	_session.map_ready.connect(_on_map_ready)
	_session.game_started.connect(_refresh)
	_session.turn_started.connect(func(_p, s): _refresh(s))


func _on_map_ready(_gen: Dictionary) -> void:
	_generated = true
	_painted_for = [-2, -2]
	_session.terrain.clear()
	_session.objects_left.clear()
	_session.objects_right.clear()


func _refresh(state: GameState) -> void:
	var season := state.season()
	var winter := state.winter_level()
	if not _generated and season < 0:
		return  # Gemalte Karte ohne Jahreszeiten: so lassen, wie sie ist.
	var key := [season, winter if season == Terrain.WINTER else -1]
	if key == _painted_for:
		return
	_painted_for = key
	var show_season := season if season >= 0 else Terrain.SUMMER
	_paint_terrain(state, show_season, winter)
	_paint_objects(state, show_season, season >= 0)
	painted.emit(state)


func _paint_terrain(state: GameState, season: int, winter: int) -> void:
	var layer := _session.terrain
	var map := _session.map
	if not _generated:
		# Gemalte Karte: jede Kachel auf die Variante der Jahreszeit setzen.
		for c in layer.get_used_cells():
			var coords := layer.get_cell_atlas_coords(c)
			if layer.get_cell_source_id(c) != GROUND_SOURCE:
				continue
			var target: Vector2i = PUDDLE[season] if PUDDLE.has(coords) else _ground(c, season)
			if target != coords:
				layer.set_cell(c, GROUND_SOURCE, target)
		return
	for c in map.cells():
		var kind := map.kind_at(c)
		var frozen := Terrain.is_frozen(kind, season, winter)
		var col := 4 if frozen else season
		match kind:
			Terrain.GRASS:
				var has_puddle := _session.objects.kind(WorldObjects.make_id(c, WorldObjects.SLOT_TERRAIN)) != ""
				layer.set_cell(c, GROUND_SOURCE, PUDDLE[season] if has_puddle else _ground(c, season))
			Terrain.RIVER:
				var next: Vector2i = map.flow.get(c, c + Vector2i(1, 1))
				layer.set_cell(c, RIVER_SOURCE, Vector2i(col, FLOW_DIR.get(next - c, 3)))
			_:
				var row := Terrain.WATER_ROWS.find(kind)
				if row >= 0:
					layer.set_cell(c, WATER_SOURCE, Vector2i(col, row))


func _ground(c: Vector2i, season: int) -> Vector2i:
	# Im Fruehling zwei Varianten mischen, damit die Wiese nicht eintoenig wirkt.
	if season == Terrain.SPRING and (hash(c) % 3) == 0:
		return GROUND_SPRING_ALT
	return GROUND[season]


func _paint_objects(state: GameState, season: int, seasonal: bool) -> void:
	var objects := _session.objects
	for id in objects.ids():
		var slot := WorldObjects.id_slot(id)
		if slot != WorldObjects.SLOT_LEFT and slot != WorldObjects.SLOT_RIGHT:
			continue
		var layer := _session.objects_left if slot == WorldObjects.SLOT_LEFT else _session.objects_right
		var source := OBJECT_SOURCE_LEFT if slot == WorldObjects.SLOT_LEFT else OBJECT_SOURCE_RIGHT
		var cell := WorldObjects.id_cell(id)
		if state.is_gone(id):
			layer.erase_cell(cell)
			continue
		var kind := objects.kind(id)
		var coords: Vector2i = STONE
		if ResourceConfig.is_tree(kind):
			coords = TREE[season] if seasonal else ResourceConfig.OBJECT_ATLAS.find_key(kind)
		layer.set_cell(cell, source, coords)
