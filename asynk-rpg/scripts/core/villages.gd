class_name Villages
extends RefCounted
## Tier-Doerfer: vermenschlichte Tiere, die auf einem Feld ein Dorf haben und
## Auftraege vergeben. Reine Daten + Logik (ohne Szene).
##
## Ein Dorf ist ein Kartenobjekt mit ID "x,y,V" und Art "village_<tier>".
## Auftraege werden pro Spieler der Reihe nach angeboten; abgegebene stehen
## im Spielstand (Spieler-Feld "quests"). Das Format ist absichtlich einfach,
## damit spaeter mehr dazukommen kann (Bedingungen, Ketten, Jahreszeiten …):
##   {"id", "text", "want": {Rohstoff: Menge}, "reward": {Rohstoff: Menge}}

const KIND_PREFIX := "village_"

## Reihenfolge = Spalte in assets/npc/Portraits.png und Doerfer.png.
const ANIMALS := [
	{"id": "fuchs", "name": "Frida Fuchs", "village": "Fuchsbau",
		"greeting": "Na sieh mal einer an, Besuch! Im Fuchsbau ist immer etwas zu tun."},
	{"id": "dachs", "name": "Dietrich Dachs", "village": "Dachshügel",
		"greeting": "Hm? Ach, du bist es. Ich grabe gerade einen neuen Gang – willst du helfen?"},
	{"id": "hase", "name": "Hanna Hase", "village": "Hasenwinkel",
		"greeting": "Hallo hallo! Schön, dass du vorbeihoppelst!"},
	{"id": "baer", "name": "Bruno Bär", "village": "Bärenhöhle",
		"greeting": "Brumm. Willkommen in der Bärenhöhle. Hast du zufällig etwas Leckeres dabei?"},
	{"id": "igel", "name": "Ida Igel", "village": "Igelhain",
		"greeting": "Oh! Entschuldige die Stacheln. Ich sammle gerade Vorräte für den Winter."},
	{"id": "eule", "name": "Otto Eule", "village": "Eulenruh",
		"greeting": "Huhu. Die Nacht ist lang, und ein weiser Vogel braucht so manches."},
]

const QUESTS := {
	"fuchs": [
		{"id": "fuchs_1", "text": "Mein Bau braucht ein neues Dach. Bringst du mir Äste?",
			"want": {ResourceConfig.AESTE: 3}, "reward": {ResourceConfig.OBST: 2}},
		{"id": "fuchs_2", "text": "Für den Winter brauche ich Holz zum Heizen.",
			"want": {ResourceConfig.HOLZ: 2}, "reward": {ResourceConfig.FISCH: 2}},
	],
	"dachs": [
		{"id": "dachs_1", "text": "Meine Gänge stürzen ein! Steine würden sie stützen.",
			"want": {ResourceConfig.STEIN: 2}, "reward": {ResourceConfig.HOLZ: 2}},
		{"id": "dachs_2", "text": "Weiches Laub für mein Bett wäre herrlich.",
			"want": {ResourceConfig.LAUB: 3}, "reward": {ResourceConfig.STEIN: 2}},
	],
	"hase": [
		{"id": "hase_1", "text": "Ich habe solchen Hunger auf etwas Süßes. Hast du Obst?",
			"want": {ResourceConfig.OBST: 2}, "reward": {ResourceConfig.LAUB: 3}},
		{"id": "hase_2", "text": "Für mein Nest suche ich Laub.",
			"want": {ResourceConfig.LAUB: 2}, "reward": {ResourceConfig.AESTE: 3}},
	],
	"baer": [
		{"id": "baer_1", "text": "Fisch! Ich brauche Fisch, bevor ich mich zum Winterschlaf lege.",
			"want": {ResourceConfig.FISCH: 2}, "reward": {ResourceConfig.HOLZ: 3}},
		{"id": "baer_2", "text": "Meine Höhle braucht einen Eingang aus Stein.",
			"want": {ResourceConfig.STEIN: 3}, "reward": {ResourceConfig.OBST: 3}},
	],
	"igel": [
		{"id": "igel_1", "text": "Ein bisschen Obst für meinen Wintervorrat?",
			"want": {ResourceConfig.OBST: 1}, "reward": {ResourceConfig.AESTE: 2}},
		{"id": "igel_2", "text": "Ich baue mir einen Laubhaufen zum Überwintern.",
			"want": {ResourceConfig.LAUB: 4}, "reward": {ResourceConfig.FISCH: 2}},
	],
	"eule": [
		{"id": "eule_1", "text": "Für meinen Nistplatz brauche ich feste Äste.",
			"want": {ResourceConfig.AESTE: 2}, "reward": {ResourceConfig.STEIN: 2}},
		{"id": "eule_2", "text": "Ein Fisch zum Abendessen wäre sehr freundlich.",
			"want": {ResourceConfig.FISCH: 1}, "reward": {ResourceConfig.OBST: 2}},
	],
}


static func is_village(kind: String) -> bool:
	return kind.begins_with(KIND_PREFIX)


static func animal_index(kind: String) -> int:
	var id := kind.trim_prefix(KIND_PREFIX)
	for i in ANIMALS.size():
		if ANIMALS[i]["id"] == id:
			return i
	return -1


static func animal(kind: String) -> Dictionary:
	var i := animal_index(kind)
	return ANIMALS[i] if i >= 0 else {}


static func quest_by_id(quest_id: String) -> Dictionary:
	for list in QUESTS.values():
		for q in list:
			if q["id"] == quest_id:
				return q
	return {}


## Naechster Auftrag dieses Dorfs fuer den Spieler ({} = alle erledigt).
static func current_quest(state: GameState, kind: String, player: int) -> Dictionary:
	var done: Array = state.players[player].get("quests", [])
	for q in QUESTS.get(kind.trim_prefix(KIND_PREFIX), []):
		if not done.has(q["id"]):
			return q
	return {}


static func items_text(items: Dictionary) -> String:
	var parts := []
	for item in items:
		parts.append("%d %s" % [items[item], ResourceConfig.ITEM_NAMES[item]])
	return ", ".join(parts)


## Doerfer verteilen: auf freier Wiese, mit Abstand zueinander und zum Start.
## land_ok(cell) -> bool, free(cell) -> bool (kein anderes Objekt).
static func place(cells: Array, land_ok: Callable, free: Callable, start: Vector2i, count: int,
		rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var chosen: Array[Vector2i] = []
	var candidates := cells.duplicate()
	# Mischen mit dem eigenen RNG (reproduzierbar)
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = t
	for c in candidates:
		if chosen.size() >= count:
			break
		if not land_ok.call(c) or not free.call(c):
			continue
		if MapGen.cell_pos(c).distance_to(MapGen.cell_pos(start)) < 3.0:
			continue
		var spaced := true
		for other in chosen:
			if MapGen.cell_pos(c).distance_to(MapGen.cell_pos(other)) < 7.0:
				spaced = false
				break
		if not spaced:
			continue
		chosen.append(c)
		var kind: String = KIND_PREFIX + ANIMALS[(chosen.size() - 1) % ANIMALS.size()]["id"]
		out[WorldObjects.make_id(c, WorldObjects.SLOT_VILLAGE)] = kind
	return out
