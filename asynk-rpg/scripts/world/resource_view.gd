extends Node
## Zeigt den Rohstoff-Zustand auf der Karte an: gefaellte Baeume und leere
## Steinhaufen werden aus den Objekt-Ebenen entfernt, leer gesammelte Baeume
## werden blass, bis sie nachgewachsen sind. Veraendert den Spielstand nicht,
## hoert nur auf die GameSession.

## Farbe fuer leer gesammelte Objekte.
const EMPTY_TINT := Color(0.55, 0.55, 0.5, 0.6)

var _session: GameSession
## [TileSetAtlasSource, Atlas-Koordinate] -> ID der blassen Alternativ-Kachel.
var _dim_alts := {}


func _ready() -> void:
	_session = get_tree().get_first_node_in_group(GameSession.GROUP) as GameSession
	if _session == null:
		return
	_session.game_started.connect(_on_game_started)
	_session.move_applied.connect(_on_move_applied)
	_session.turn_started.connect(func(_p, state): _refresh_tint(state))


func _on_game_started(state: GameState) -> void:
	for id in state.resources:
		if state.resources[id]["gone"]:
			_remove(id)
	_refresh_tint(state)


func _on_move_applied(move: Dictionary, state: GameState) -> void:
	if move["type"] != GameRules.TYPE_HARVEST:
		return
	# Warten, bis die Figur angekommen ist, dann erst den Baum/Stein aendern.
	while _any_unit_moving():
		await get_tree().process_frame
	if state.is_gone(move["target"]):
		_remove(move["target"])
	_refresh_tint(state)


## Leer gesammelte Objekte blass zeigen, nachgewachsene wieder normal.
func _refresh_tint(state: GameState) -> void:
	for id in state.resources:
		if state.resources[id]["gone"]:
			continue
		var layer := _layer_for(id)
		if layer == null:
			continue
		var empty := state.resource_amount(id, _session.objects.kind(id)) == 0
		set_dimmed(layer, WorldObjects.id_cell(id), empty)


## true, wenn die Kachel gerade blass gezeigt wird (fuer Tests).
func is_dimmed(layer: TileMapLayer, cell: Vector2i) -> bool:
	return layer.get_cell_alternative_tile(cell) != 0


func set_dimmed(layer: TileMapLayer, cell: Vector2i, dimmed: bool) -> void:
	var source_id := layer.get_cell_source_id(cell)
	if source_id == -1 or is_dimmed(layer, cell) == dimmed:
		return
	var coords := layer.get_cell_atlas_coords(cell)
	var alt := 0
	if dimmed:
		var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null:
			return
		alt = _dim_alternative(source, coords)
	layer.set_cell(cell, source_id, coords, alt)


func _dim_alternative(source: TileSetAtlasSource, coords: Vector2i) -> int:
	var key := [source, coords]
	if _dim_alts.has(key):
		return _dim_alts[key]
	var alt := source.create_alternative_tile(coords)
	var base := source.get_tile_data(coords, 0)
	var data := source.get_tile_data(coords, alt)
	data.texture_origin = base.texture_origin
	data.y_sort_origin = base.y_sort_origin
	data.z_index = base.z_index
	data.modulate = base.modulate * EMPTY_TINT
	_dim_alts[key] = alt
	return alt


func _remove(id: String) -> void:
	var layer := _layer_for(id)
	if layer:
		layer.erase_cell(WorldObjects.id_cell(id))


func _layer_for(id: String) -> TileMapLayer:
	match WorldObjects.id_slot(id):
		WorldObjects.SLOT_LEFT:
			return _session.objects_left
		WorldObjects.SLOT_RIGHT:
			return _session.objects_right
	return null


func _any_unit_moving() -> bool:
	for agent in get_tree().get_nodes_in_group("hex_agents"):
		if agent.isMoving:
			return true
	return false
