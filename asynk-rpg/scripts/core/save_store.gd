class_name SaveStore
extends RefCounted
## Mehrere Spielstaende, eine Datei pro Spiel in user://saves/<id>.json.
## Jedes Geraet speichert jedes Spiel mit, an dem es teilnimmt (auch als
## LAN-Client). So kann spaeter jeder den Spielstand lokal fortsetzen oder
## als LAN-Spiel hosten.
##
## Dateiinhalt: {"version", "updated" (Unix-Zeit), "lobby": Dictionary,
##               "state": GameState.to_dict()}

## Ordner der Spielstaende (Tests stellen einen eigenen Ordner ein).
static var dir := "user://saves"
const VERSION := 1


static func path_for(id: String) -> String:
	return "%s/%s.json" % [dir, id.validate_filename()]


static func save(id: String, state: GameState, lobby: Dictionary) -> void:
	if id == "" or state == null:
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var data := {
		"version": VERSION,
		"updated": Time.get_unix_time_from_system(),
		"lobby": lobby,
		"state": state.to_dict(),
	}
	var f := FileAccess.open(path_for(id), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


## {"state": GameState, "lobby": Dictionary} oder {} wenn kaputt/fehlt.
static func read(id: String) -> Dictionary:
	var p := path_for(id)
	if not FileAccess.file_exists(p):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not data is Dictionary or not data.get("state") is Dictionary or not data.get("lobby") is Dictionary:
		return {}
	var state := GameState.from_dict(data["state"])
	if state == null:
		return {}
	var lobby: Dictionary = data["lobby"]
	if lobby.get("players", []).size() != state.players.size():
		return {}
	return {"state": state, "lobby": lobby, "updated": float(data.get("updated", 0))}


static func delete(id: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(id)))


## Alle Spielstaende, neueste zuerst:
## [{"id", "title", "detail", "updated", "lan"}]
static func list() -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for file in d.get_files():
		if not file.ends_with(".json"):
			continue
		var id := file.get_basename()
		var data := read(id)
		if data.is_empty():
			continue
		var state: GameState = data["state"]
		var lobby: Dictionary = data["lobby"]
		var names := []
		for p in state.players:
			names.append(p["name"])
		var when := Time.get_datetime_string_from_unix_time(int(data["updated"]) + _tz_offset(), true)
		out.append({
			"id": id,
			"title": ", ".join(names),
			"detail": "%s · Runde %d · %s" % ["LAN" if lobby.get("lan", false) else "Lokal", state.round_number, when.left(16)],
			"updated": data["updated"],
			"lan": lobby.get("lan", false),
		})
	out.sort_custom(func(a, b): return a["updated"] > b["updated"])
	return out


static func latest_id() -> String:
	var l := list()
	return l[0]["id"] if not l.is_empty() else ""


static func has_any() -> bool:
	return latest_id() != ""


static func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


## Alle Spielstaende im aktuellen Ordner loeschen (nur fuer Tests).
static func clear_all() -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for file in d.get_files():
		d.remove(file)
