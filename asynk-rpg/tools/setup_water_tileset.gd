extends SceneTree
## Traegt die Wasser- und Fluss-Atlanten ins Gelaende-Tileset ein
## (Quelle 10 = Tiles-Wasser.png, 11 = Tiles-Fluss.png). Einmal ausfuehren,
## nachdem neue Kacheln im Atlas dazugekommen sind:
##   godot --headless --path asynk-rpg -s res://tools/setup_water_tileset.gd

const TILESET := "res://Ressurses/tile_set_Teraing.tres"
const WATER_SOURCE := 10
const RIVER_SOURCE := 11


func _initialize() -> void:
	var ts: TileSet = load(TILESET)
	_add(ts, WATER_SOURCE, "res://assets/tiles/Tiles-Wasser.png", Terrain.WATER_ROWS.size())
	_add(ts, RIVER_SOURCE, "res://assets/tiles/Tiles-Fluss.png", 6)
	var err := ResourceSaver.save(ts, TILESET)
	print("gespeichert: ", TILESET, " (", error_string(err), ")")
	quit()


func _add(ts: TileSet, id: int, texture_path: String, rows: int) -> void:
	if ts.has_source(id):
		ts.remove_source(id)
	var src := TileSetAtlasSource.new()
	src.texture = load(texture_path)
	src.texture_region_size = Vector2i(256, 256)
	var img := src.texture.get_image()
	for row in rows:
		for col in 5:
			# Nur Kacheln anlegen, auf denen etwas gemalt ist.
			if img.get_pixel(col * 256 + 128, row * 256 + 129).a > 0.1:
				src.create_tile(Vector2i(col, row))
	ts.add_source(src, id)
	print("Quelle ", id, ": ", src.get_tiles_count(), " Kacheln")
