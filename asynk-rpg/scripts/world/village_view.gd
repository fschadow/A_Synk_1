class_name VillageView
extends Node
## Zeigt die Tier-Doerfer auf der Karte (Huetten + Tierfigur aus
## assets/npc/Doerfer.png). Sortiert sich mit Baeumen und Figuren nach
## der Hoehe (Objects-Knoten mit y_sort). Aendert den Spielstand nie.

const SHEET := preload("res://assets/npc/Doerfer.png")
## Boden in der Grafik liegt bei y = 150 (siehe tools/gen_animals.gd).
const GROUND_Y := 150.0
const SORT_OFFSET := 10.0
## Die Grafik ist kleiner gezeichnet als ein Feld: etwas vergroessern.
const SCALE := 1.5

var _session: GameSession
var _sprites: Array[Sprite2D] = []


func _ready() -> void:
	_session = get_tree().get_first_node_in_group(GameSession.GROUP) as GameSession
	if _session:
		_session.game_started.connect(func(_s): rebuild())


func rebuild() -> void:
	for s in _sprites:
		s.queue_free()
	_sprites.clear()
	var parent := _session.objects_left.get_parent() as Node2D
	for id in _session.objects.ids():
		var kind := _session.objects.kind(id)
		if not Villages.is_village(kind):
			continue
		var i := Villages.animal_index(kind)
		var sprite := Sprite2D.new()
		sprite.texture = SHEET
		sprite.region_enabled = true
		sprite.region_rect = Rect2(i * 256, 0, 256, 256)
		var cell := WorldObjects.id_cell(id)
		var center := parent.to_local(_session.terrain.to_global(_session.terrain.map_to_local(cell)))
		sprite.position = center + Vector2(0, SORT_OFFSET)
		sprite.scale = Vector2(SCALE, SCALE)
		sprite.offset = Vector2(0, 128.0 - GROUND_Y - SORT_OFFSET / SCALE)
		sprite.name = "Village_%d_%d" % [cell.x, cell.y]
		parent.add_child(sprite)
		_sprites.append(sprite)


func count() -> int:
	return _sprites.size()
