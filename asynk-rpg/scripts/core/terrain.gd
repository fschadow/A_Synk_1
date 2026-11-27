class_name Terrain
extends RefCounted
## Gelaendearten, Jahreszeiten und was sie fuer die Regeln bedeuten
## (Schrittkosten, Schwimmen, Zufrieren, Fischvorrat). Reine Logik.
##
## Schrittkosten (0 = nicht begehbar):
##   Gras, Strand, flaches Wasser: 1 · Fluss: 2
##   Teich, See, seichtes Meer: nur im Sommer schwimmend, 3 Schritte
##   tiefes Meer, Ozean: nie
##   Zugefroren (Winter, je nach Haerte): 1
## Winterhaerte: mild = Teiche frieren · normal = + Seen, Fluesse ·
##               hart = + seichtes und flaches Meer

const GRASS := "grass"
const BEACH := "beach"
const FLAT := "flat"
const SHALLOW := "shallow"
const DEEP := "deep"
const OCEAN := "ocean"
const POND := "pond"
const LAKE := "lake"
const RIVER := "river"

## Zeilen im Wasser-Atlas (Tiles-Wasser.png).
const WATER_ROWS := [BEACH, FLAT, SHALLOW, DEEP, OCEAN, POND, LAKE]
## Arten mit Eis-Variante (Spalte 4 im Atlas).
const FREEZES := [FLAT, SHALLOW, POND, LAKE, RIVER]
const NAMES := {GRASS: "Wiese", BEACH: "Strand", FLAT: "flaches Wasser", SHALLOW: "seichtes Meer",
	DEEP: "tiefes Meer", OCEAN: "Ozean", POND: "Teich", LAKE: "See", RIVER: "Fluss"}

const SPRING := 0
const SUMMER := 1
const AUTUMN := 2
const WINTER := 3
const SEASON_NAMES := ["Frühling", "Sommer", "Herbst", "Winter"]
const WINTER_NAMES := ["milder Winter", "Winter", "harter Winter"]
## Ab welcher Winterhaerte (0 mild, 1 normal, 2 hart) eine Art zufriert.
const FREEZE_LEVEL := {POND: 0, LAKE: 1, RIVER: 1, SHALLOW: 2, FLAT: 2}
## Fische, die ein Gewaesserfeld hergibt, bevor es nachwachsen muss.
const FISH_STOCK := {POND: 1, FLAT: 1, RIVER: 2, LAKE: 2, SHALLOW: 2, DEEP: 3, OCEAN: 3}
const SWIM_COST := 3


static func is_water(kind: String) -> bool:
	return FISH_STOCK.has(kind)


static func is_frozen(kind: String, season: int, winter_level: int) -> bool:
	return season == WINTER and FREEZE_LEVEL.has(kind) and winter_level >= FREEZE_LEVEL[kind]


## Schritte, um das Feld zu betreten (0 = geht nicht). season -1 = ohne Jahreszeiten.
static func move_cost(kind: String, season: int, winter_level: int) -> int:
	if is_frozen(kind, season, winter_level):
		return 1
	match kind:
		GRASS, BEACH, FLAT, "":
			return 1
		RIVER:
			return 2
		POND, LAKE, SHALLOW:
			return SWIM_COST if season == SUMMER else 0
		DEEP, OCEAN:
			return 0
	return 1


## Kann man an diesem Gewaesser gerade fischen? (Nicht auf Eis.)
static func can_fish(kind: String, season: int, winter_level: int) -> bool:
	return is_water(kind) and not is_frozen(kind, season, winter_level)


# ------------------------------------------------------------ Jahreszeiten

## Jahreszeit fuer eine Runde (-1, wenn das Spiel ohne Jahreszeiten laeuft).
static func season_for(round_number: int, season_length: int) -> int:
	if season_length <= 0:
		return -1
	return int((round_number - 1) / season_length) % 4


## Das wievielte Jahr (0, 1, ...).
static func year_for(round_number: int, season_length: int) -> int:
	if season_length <= 0:
		return 0
	return int((round_number - 1) / (season_length * 4))


## Haerte des Winters in diesem Jahr (0 mild, 1 normal, 2 hart), aus dem Seed.
static func winter_level_for(seed_value: int, year: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, year, "winter"])
	var r := rng.randf()
	return 0 if r < 0.3 else (1 if r < 0.75 else 2)
