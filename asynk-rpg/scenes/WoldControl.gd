extends Node2D
## Eingabe fuer die Spielwelt: Ziehen/Zoomen bewegt die Kamera, ein kurzer
## Klick/Tipp auf ein Feld wird je nach gewaehlter Faehigkeit zum Laufen oder
## Abbauen an die GameSession geschickt.

@onready var Camera := %Camera2D
@onready var Session: GameSession = %GameSession
@onready var Hud := %TurnHud
@onready var Ui := $CanvasLayer/inGameUi
var StartMousPos: Vector2
var _fell_dialog: ConfirmationDialog
var _pending_fell := Vector2i.ZERO
var _start_zoom: Vector2
var _cam_tween: Tween


func _ready() -> void:
	_start_zoom = Camera.zoom
	Session.turn_started.connect(_on_turn_started)
	Hud.focus_requested.connect(focus_on_player)
	# Android-Zurueck-Taste fuehrt im Spiel ins Hauptmenue statt die App zu schliessen.
	get_tree().set_quit_on_go_back(false)
	_fell_dialog = ConfirmationDialog.new()
	_fell_dialog.title = "Baum fällen"
	_fell_dialog.dialog_text = "Der Baum ist danach für immer weg.\nTrotzdem fällen?"
	_fell_dialog.ok_button_text = "Fällen"
	_fell_dialog.cancel_button_text = "Abbrechen"
	_fell_dialog.confirmed.connect(func(): Session.request_action(_pending_fell, ResourceConfig.ACT_FELL))
	$CanvasLayer.add_child(_fell_dialog)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Glob.go_to_menu()


func _input(event: InputEvent) -> void:
	if Hud.is_blocking() or _fell_dialog.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_HOME]:
		focus_on_player()
		return
	if Input.is_action_just_pressed("MOUSE_BUTTON_LEFT") or (event is InputEventScreenTouch and event.pressed):
		StartMousPos = event.position
	if Input.is_action_just_released("MOUSE_BUTTON_LEFT") and StartMousPos.distance_to(event.position) < 10:
		_on_tap(event.position)
	else:
		Camera.moveCamera(event)


func _on_tap(screen_pos: Vector2) -> void:
	if Ui.covers(screen_pos) or Hud.covers(screen_pos) or _any_unit_moving():
		return
	var world_pos := get_canvas_transform().affine_inverse() * screen_pos
	var cell: Vector2i = Session.terrain.local_to_map(Session.terrain.to_local(world_pos))
	var action: String = Glob.action_for(Glob.CurStatus)
	if action == ResourceConfig.ACT_FELL:
		# Erst pruefen, ob Faellen ueberhaupt ginge, dann nachfragen.
		var plan := GameRules.make_action_at(Session.state, Session.map, Session.objects, cell, action)
		if plan.has("error"):
			Session.move_rejected.emit(plan["error"])
			return
		_pending_fell = cell
		_fell_dialog.popup_centered()
		return
	Session.request_action(cell, action)


func _any_unit_moving() -> bool:
	for agent in get_tree().get_nodes_in_group("hex_agents"):
		if agent.isMoving:
			return true
	return false


func _on_turn_started(player_index: int, state: GameState) -> void:
	# Kamera auf die Figur des Spielers setzen, der jetzt dran ist.
	var cell: Vector2i = state.players[player_index]["pos"]
	Camera.position = Session.terrain.to_global(Session.terrain.map_to_local(cell))


## Kamera weich zur Figur des aktiven Spielers fahren und den Zoom auf den
## Startwert zuruecksetzen (Button "Zur Figur" bzw. Leertaste/Pos1).
func focus_on_player() -> void:
	var target := _current_player_position()
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_cam_tween.tween_property(Camera, "position", target, 0.4)
	_cam_tween.tween_property(Camera, "zoom", _start_zoom, 0.4)


func _current_player_position() -> Vector2:
	# Die sichtbare Figur nehmen (laeuft sie gerade, dorthin, wo sie gerade ist).
	for agent in get_tree().get_nodes_in_group("hex_agents"):
		if agent.player_index == Session.state.current_player:
			return agent.get_parent().global_position
	var cell: Vector2i = Session.state.current()["pos"]
	return Session.terrain.to_global(Session.terrain.map_to_local(cell))
