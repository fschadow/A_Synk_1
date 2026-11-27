class_name WorldObjects
extends RefCounted
## Reine Kartendaten: welche abbaubaren Objekte (Baeume, Steine, Pfuetzen) wo
## stehen. Wie HexMap kennt diese Klasse keine Nodes; der Zustand (Vorrat,
## gefaellt) steht im GameState.
##
## Jedes Objekt hat eine ID "x,y,S" mit S = Slot:
##   L = Objekt-Ebene links (O-L), R = Objekt-Ebene rechts (O-R), T = Boden (Pfuetze),
##   W = Gewaesser (Fischgrund; Art = Gelaendeart, gefischt wird vom Nachbarfeld),
##   V = Tier-Dorf (siehe Villages)

const SLOT_LEFT := "L"
const SLOT_RIGHT := "R"
const SLOT_TERRAIN := "T"
const SLOT_WATER := "W"
const SLOT_VILLAGE := "V"
const SLOTS: Array[String] = [SLOT_LEFT, SLOT_RIGHT, SLOT_TERRAIN, SLOT_WATER, SLOT_VILLAGE]

## id -> Objektart (ResourceConfig.KIND_*)
var _kinds: Dictionary = {}


static func make_id(cell: Vector2i, slot: String) -> String:
	return "%d,%d,%s" % [cell.x, cell.y, slot]


static func id_cell(id: String) -> Vector2i:
	var parts := id.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


static func id_slot(id: String) -> String:
	return id.split(",")[2]


## Aus den TileMap-Ebenen der Szene lesen.
static func from_layers(terrain: TileMapLayer, left: TileMapLayer, right: TileMapLayer) -> WorldObjects:
	var w := WorldObjects.new()
	for pair in [[left, SLOT_LEFT], [right, SLOT_RIGHT]]:
		var layer: TileMapLayer = pair[0]
		if layer == null:
			continue
		for c in layer.get_used_cells():
			var kind = ResourceConfig.OBJECT_ATLAS.get(layer.get_cell_atlas_coords(c))
			if kind != null:
				w._kinds[make_id(c, pair[1])] = kind
	if terrain:
		for c in terrain.get_used_cells():
			if ResourceConfig.PUDDLE_ATLAS.has(terrain.get_cell_atlas_coords(c)):
				w._kinds[make_id(c, SLOT_TERRAIN)] = ResourceConfig.KIND_PUDDLE
	return w


## Fuer Tests: {"x,y,S": kind}
static func from_dict(kinds: Dictionary) -> WorldObjects:
	var w := WorldObjects.new()
	w._kinds = kinds.duplicate()
	return w


func set_kind(id: String, k: String) -> void:
	_kinds[id] = k


func ids() -> Array:
	return _kinds.keys()


func kind(id: String) -> String:
	return _kinds.get(id, "")


func ids_at(cell: Vector2i) -> Array[String]:
	var out: Array[String] = []
	for slot in SLOTS:
		var id := make_id(cell, slot)
		if _kinds.has(id):
			out.append(id)
	return out


func count() -> int:
	return _kinds.size()
