class_name SimpleAI
extends RefCounted
## Einfache KI, die einen Spieler vertritt (KI-Mitspieler oder wenn im
## LAN-Spiel jemand die Verbindung verliert): Sie sucht den naechsten Rohstoff,
## laeuft hin und sammelt, baut ab oder fischt. Baeume faellt sie nie.
## Reine Logik, ohne Szene.

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
	var cells := map.reachable(me["pos"], state.occupied_cells(state.current_player),
		steps - ResourceConfig.ACTION_STEP_COST, GameRules.cost_func(state, map))
	var tried := {}
	for cell in cells:
		# Objekte auf dem Feld und Gewaesser daneben (Fischen vom Ufer aus).
		var targets: Array[Vector2i] = [cell]
		for n in map.neighbors(cell):
			if map.kind_at(n) != Terrain.GRASS:
				targets.append(n)
		for t in targets:
			if tried.has(t) or objects.ids_at(t).is_empty():
				continue
			tried[t] = true
			for action in ACTIONS:
				var plan := GameRules.make_action_at(state, map, objects, t, action)
				if not plan.has("error"):
					return plan["moves"]
	return []
