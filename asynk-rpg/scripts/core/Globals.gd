extends Node
#Resource
#class_name Globals

enum Status {Nothing,Lumber,Mine,Fish}
var CurStatus := Status.Nothing
var MouseOnUI : bool

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_SCENE := "res://scenes/node_2d.tscn"

## Vom Startmenue gesetzt: true = "Neues Spiel" (alten Spielstand verwerfen),
## false = "Weiterspielen" (gespeicherten Spielstand laden).
var start_new_game := false

func _init() -> void:
	CurStatus = Status.Nothing


## Wechselt ins Spiel. new_game = true startet ein frisches Spiel.
func start_game(new_game: bool) -> void:
	start_new_game = new_game
	_reset_ui_state()
	get_tree().change_scene_to_file(GAME_SCENE)


func go_to_menu() -> void:
	_reset_ui_state()
	get_tree().change_scene_to_file(MENU_SCENE)


func _reset_ui_state() -> void:
	MouseOnUI = false
	CurStatus = Status.Nothing
