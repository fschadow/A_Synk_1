extends Node
#Resource
#class_name Globals

## Faehigkeit in der Aktionsleiste. Nothing = Laufen.
## (Neue Werte nur hinten anhaengen, die Zahlen stehen evtl. in Szenen.)
enum Status {Nothing,Lumber,Mine,Fish,Collect}
var CurStatus := Status.Nothing
var MouseOnUI : bool

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_SCENE := "res://scenes/node_2d.tscn"
const LAN_SCENE := "res://scenes/lan_menu.tscn"

## Vom Startmenue gesetzt: true = "Neues Spiel" (alten Spielstand verwerfen),
## false = "Weiterspielen" (gespeicherten Spielstand laden).
var start_new_game := false

## Status -> Aktion in den Spielregeln (ResourceConfig.ACT_*)
func action_for(status: Status) -> String:
	match status:
		Status.Collect: return ResourceConfig.ACT_COLLECT
		Status.Lumber: return ResourceConfig.ACT_FELL
		Status.Mine: return ResourceConfig.ACT_MINE
		Status.Fish: return ResourceConfig.ACT_FISH
	return ResourceConfig.ACT_WALK

func _init() -> void:
	CurStatus = Status.Nothing


## Wechselt ins Spiel. new_game = true startet ein frisches Spiel.
func start_game(new_game: bool) -> void:
	start_new_game = new_game
	_reset_ui_state()
	get_tree().change_scene_to_file(GAME_SCENE)


## Wechselt in ein LAN-Spiel. Den Spielstand liefert Net (Host/Client).
func start_lan_game() -> void:
	start_new_game = false
	_reset_ui_state()
	get_tree().change_scene_to_file(GAME_SCENE)


## Zurueck ins Hauptmenue. Ein laufendes LAN-Spiel wird dabei verlassen.
func go_to_menu() -> void:
	_reset_ui_state()
	if Net.is_active():
		Net.leave()
	get_tree().change_scene_to_file(MENU_SCENE)


func _reset_ui_state() -> void:
	MouseOnUI = false
	CurStatus = Status.Nothing
