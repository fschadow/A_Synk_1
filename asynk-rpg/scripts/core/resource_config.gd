class_name ResourceConfig
extends RefCounted
## Alle Zahlen und Zuordnungen rund um Rohstoffe an einer Stelle.
## Zum Balancing nur hier etwas aendern.

# --- Rohstoffe (Schluessel im Inventar) ---
const HOLZ := "holz"
const AESTE := "aeste"
const OBST := "obst"
const LAUB := "laub"
const STEIN := "stein"
const FISCH := "fisch"
const ITEMS: Array[String] = [HOLZ, AESTE, OBST, LAUB, STEIN, FISCH]
const ITEM_NAMES := {
	HOLZ: "Holz", AESTE: "Äste", OBST: "Obst", LAUB: "Laub", STEIN: "Stein", FISCH: "Fisch",
}

## So viel kann ein Spieler hoechstens von jedem Rohstoff tragen.
const CARRY_LIMIT := 10

# --- Faehigkeiten (Knoepfe in der Aktionsleiste) ---
const ACT_WALK := "walk"
const ACT_COLLECT := "collect"  # Aeste + Obst/Laub vom Baum, waechst nach
const ACT_FELL := "fell"        # Baum faellen: Holz, Baum ist fuer immer weg
const ACT_MINE := "mine"        # Steinhaufen abbauen, leer = weg
const ACT_FISH := "fish"        # auf Pfuetzen fischen, waechst nach

## Was es kostet, einmal abzubauen (in Schritten).
const ACTION_STEP_COST := 1

# --- Objektarten auf der Karte ---
const KIND_TREE_BLOSSOM := "tree_blossom"
const KIND_TREE_APPLE := "tree_apple"
const KIND_TREE_AUTUMN := "tree_autumn"
const KIND_TREE_BARE := "tree_bare"
const KIND_STONE := "stone"
const KIND_PUDDLE := "puddle"

## Atlas-Koordinaten in Tiles-Objeckte_O-R.png (Ebenen O-L und O-R) -> Objektart.
const OBJECT_ATLAS := {
	Vector2i(0, 0): KIND_TREE_BLOSSOM,
	Vector2i(2, 0): KIND_TREE_APPLE,
	Vector2i(4, 0): KIND_TREE_AUTUMN,
	Vector2i(6, 0): KIND_TREE_BARE,
	Vector2i(0, 1): KIND_STONE,
}
## Atlas-Koordinaten in Tiles-Teraing.png, auf denen Pfuetzen sind (Fischen).
const PUDDLE_ATLAS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(3, 1), Vector2i(5, 1), Vector2i(7, 1)]

const TREE_KINDS: Array[String] = [KIND_TREE_BLOSSOM, KIND_TREE_APPLE, KIND_TREE_AUTUMN, KIND_TREE_BARE]

## Was "Sammeln" an einem Baum zusaetzlich zu Aesten bringt.
const COLLECT_EXTRA := {
	KIND_TREE_APPLE: OBST,
	KIND_TREE_BLOSSOM: LAUB,
	KIND_TREE_AUTUMN: LAUB,
}

## Startvorrat je Objekt (wie oft man abbauen kann).
const STOCK := {
	KIND_TREE_BLOSSOM: 3,
	KIND_TREE_APPLE: 3,
	KIND_TREE_AUTUMN: 3,
	KIND_TREE_BARE: 3,
	KIND_STONE: 3,
	KIND_PUDDLE: 1,  # Pfuetzen geben nur wenig Fisch
}

## Holz beim Faellen eines Baums.
const FELL_WOOD := 3

## Alle wie viele Runden ein Vorrat um 1 nachwaechst. Steine wachsen nicht nach.
const REGROW_ROUNDS := 3
const REGROWS := {
	KIND_TREE_BLOSSOM: true,
	KIND_TREE_APPLE: true,
	KIND_TREE_AUTUMN: true,
	KIND_TREE_BARE: true,
	KIND_STONE: false,
	KIND_PUDDLE: true,
}


## Passt diese Faehigkeit zu dieser Objektart?
static func action_fits(action: String, kind: String) -> bool:
	match action:
		ACT_COLLECT, ACT_FELL:
			return TREE_KINDS.has(kind)
		ACT_MINE:
			return kind == KIND_STONE
		ACT_FISH:
			return kind == KIND_PUDDLE
	return false


## Was eine Aktion an diesem Objekt einbringt: {item: menge}.
static func yields(action: String, kind: String) -> Dictionary:
	match action:
		ACT_COLLECT:
			var y := {AESTE: 1}
			if COLLECT_EXTRA.has(kind):
				y[COLLECT_EXTRA[kind]] = 1
			return y
		ACT_FELL:
			return {HOLZ: FELL_WOOD}
		ACT_MINE:
			return {STEIN: 1}
		ACT_FISH:
			return {FISCH: 1}
	return {}


static func empty_inventory() -> Dictionary:
	var inv := {}
	for item in ITEMS:
		inv[item] = 0
	return inv
