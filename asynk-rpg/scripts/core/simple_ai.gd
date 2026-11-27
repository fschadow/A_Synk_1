class_name SimpleAI
extends RefCounted
## Einfache KI, die einen Spieler vertritt (z. B. wenn im LAN-Spiel jemand
## die Verbindung verliert): Sie sucht den naechsten Rohstoff, laeuft hin und
## sammelt bzw. baut ab. Baeume faellt sie nie. Reine Logik, ohne Szene.

## Reihenfolge, in der die Aktionen an einem Feld probiert werden.
const ACTIONS := [ResourceConfig.ACT_COLLECT, ResourceConfig.ACT_MINE, ResourceConfig.ACT_FISH]


## Die naechsten Zuege fuer den Spieler, der dran ist (Hinlaufen + Abbauen),
## oder [] wenn nichts Sinnvolles mehr geht. Dann soll der Zug enden.
static func next_moves(state: GameState, map: HexMap, objects: WorldObjects) -> Array:
	var me := state.current()
	var steps: int = me["steps_left"]
	if steps < ResourceConfig.ACTION_STEP_COST:
		return []
	# Felder in Reichweite, naechste zuerst. Zum Abbauen braucht es noch einen Schritt.
	var cells := map.reachable(me["pos"], state.occupied_cells(state.current_player), steps - ResourceConfig.ACTION_STEP_COST)
	for cell in cells:
		if objects.ids_at(cell).is_empty():
			continue
		for action in ACTIONS:
			var plan := GameRules.make_action_at(state, map, objects, cell, action)
			if not plan.has("error"):
				return plan["moves"]
	return []
