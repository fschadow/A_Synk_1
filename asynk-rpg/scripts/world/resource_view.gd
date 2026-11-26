extends Node
## Zeigt den Rohstoff-Zustand auf der Karte an: gefaellte Baeume und leere
## Steinhaufen werden aus den Objekt-Ebenen entfernt. Veraendert den
## Spielstand nicht, hoert nur auf die GameSession.

var _session: GameSession


func _ready() -> void:
	_session = get_tree().get_first_node_in_group(GameSession.GROUP) as GameSession
	if _session == null:
		return
	_session.game_started.connect(_on_game_started)
	_session.move_applied.connect(_on_move_applied)


func _on_game_started(state: GameState) -> void:
	for id in state.resources:
		if state.resources[id]["gone"]:
			_remove(id)


func _on_move_applied(move: Dictionary, state: GameState) -> void:
	if move["type"] != GameRules.TYPE_HARVEST or not state.is_gone(move["target"]):
		return
	# Warten, bis die Figur angekommen ist, dann erst den Baum/Stein entfernen.
	while _any_unit_moving():
		await get_tree().process_frame
	_remove(move["target"])


func _remove(id: String) -> void:
	var layer: TileMapLayer
	match WorldObjects.id_slot(id):
		WorldObjects.SLOT_LEFT:
			layer = _session.objects_left
		WorldObjects.SLOT_RIGHT:
			layer = _session.objects_right
	if layer:
		layer.erase_cell(WorldObjects.id_cell(id))


func _any_unit_moving() -> bool:
	for agent in get_tree().get_nodes_in_group("hex_agents"):
		if agent.isMoving:
			return true
	return false
