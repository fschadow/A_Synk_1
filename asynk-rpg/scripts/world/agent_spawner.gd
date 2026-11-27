class_name AgentSpawner
extends Node
## Sorgt dafuer, dass es fuer jeden Spieler im GameState eine Figur gibt
## (bis zu 20 im LAN-Spiel). Die Szene enthaelt zwei Figuren; weitere werden
## als Kopie der ersten erzeugt und bekommen eine eigene Ringfarbe.

## Ringfarben der Spieler, Index = Spielernummer.
const COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0, 0.85), Color(0.95, 0.3, 0.25, 0.85), Color(0.3, 0.8, 0.35, 0.85),
	Color(0.95, 0.85, 0.2, 0.85), Color(0.65, 0.35, 0.9, 0.85), Color(1.0, 0.55, 0.15, 0.85),
	Color(0.2, 0.85, 0.85, 0.85), Color(0.95, 0.45, 0.75, 0.85), Color(0.95, 0.95, 0.95, 0.85),
	Color(0.15, 0.15, 0.15, 0.85), Color(0.55, 0.35, 0.2, 0.85), Color(0.65, 0.95, 0.2, 0.85),
	Color(0.15, 0.2, 0.6, 0.85), Color(0.1, 0.55, 0.5, 0.85), Color(0.55, 0.1, 0.2, 0.85),
	Color(0.5, 0.5, 0.1, 0.85), Color(0.75, 0.7, 1.0, 0.85), Color(1.0, 0.65, 0.55, 0.85),
	Color(0.55, 0.55, 0.55, 0.85), Color(0.85, 0.65, 0.1, 0.85),
]

## Vorlage fuer neue Figuren (die erste Figur der Szene).
@export var template: Node2D


static func color_for(index: int) -> Color:
	return COLORS[index % COLORS.size()]


func _ready() -> void:
	var session := get_tree().get_first_node_in_group(GameSession.GROUP) as GameSession
	if session:
		session.game_started.connect(_on_game_started)


func _on_game_started(state: GameState) -> void:
	if template == null:
		return
	var existing := {}
	for agent in get_tree().get_nodes_in_group("hex_agents"):
		existing[agent.player_index] = agent
	for i in state.players.size():
		if existing.has(i):
			existing[i].get_parent().visible = true
			continue
		var body: Node2D = template.duplicate()
		body.unique_name_in_owner = false
		body.name = "Player%d" % (i + 1)
		var agent = body.get_node("HexAgent")
		agent.player_index = i
		agent.marker_color = color_for(i)
		template.get_parent().add_child(body)
		agent._on_game_started(state)
