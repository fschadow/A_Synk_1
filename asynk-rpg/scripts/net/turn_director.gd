class_name TurnDirector
extends Node
## Laeuft nur auf dem Host eines LAN-Spiels (Kind von Net):
## - Zuguhr: ist die Zeit um, endet der Zug automatisch.
## - KI: vertritt Spieler, fuer die der Host "KI uebernimmt" gewaehlt hat.
## - Pause: fehlt der Spieler, der dran ist, steht die Uhr.
## Aendert den Spielstand nur ueber GameSession.submit().

## Pause zwischen zwei KI-Aktionen, damit man zusehen kann.
const AI_DELAY := 0.6

var _session: GameSession
## Wird bei jedem Zugwechsel erhoeht; laufende KI-Schleifen brechen dann ab.
var _turn_token := 0
## Zug, fuer den gerade eine KI-Schleife laeuft (-1 = keine).
var _ai_token := -1
var _paused := false


func attach(s: GameSession) -> void:
	detach()
	_session = s
	s.turn_started.connect(_on_turn_started)
	Net.lobby_changed.connect(_reevaluate)
	_on_turn_started(s.state.current_player, s.state)


func detach() -> void:
	if _session and is_instance_valid(_session) and _session.turn_started.is_connected(_on_turn_started):
		_session.turn_started.disconnect(_on_turn_started)
	if Net.lobby_changed.is_connected(_reevaluate):
		Net.lobby_changed.disconnect(_reevaluate)
	_session = null
	_turn_token += 1
	_ai_token = -1
	_paused = false


func _on_turn_started(_player: int, state: GameState) -> void:
	_turn_token += 1
	_paused = Net.is_paused(state)
	if Net.turn_time() > 0:
		Net.set_clock(Net.turn_time(), not _paused)
	_reevaluate.call_deferred()


## Nach Lobby-Aenderungen (Spieler weg/zurueck, KI an/aus) neu bewerten.
func _reevaluate() -> void:
	if _session == null or _session.state == null:
		return
	var state := _session.state
	var paused := Net.is_paused(state)
	if paused != _paused:
		_paused = paused
		if Net.turn_time() > 0:
			var left := Net.time_left()
			if not paused and left <= 0.0:
				left = Net.turn_time()
			Net.set_clock(left, not paused)
	if not paused and Net.is_ai(state.current_player) and _ai_token != _turn_token:
		_run_ai()


func _process(_delta: float) -> void:
	if _session == null or _paused or Net.turn_time() <= 0 or not Net.clock_running():
		return
	if Net.time_left() <= 0.0:
		# Zeit abgelaufen: Zug fuer den Spieler beenden, der dran ist.
		Net.set_clock(0.0, false)
		_session.try_submit(GameRules.make_end_turn(_session.state))


func _run_ai() -> void:
	var token := _turn_token
	_ai_token = token
	while true:
		await get_tree().create_timer(AI_DELAY).timeout
		if not _ai_still_on(token):
			break
		while _any_unit_moving():
			await get_tree().process_frame
		if not _ai_still_on(token):
			break
		var state := _session.state
		var moves := SimpleAI.next_moves(state, _session.map, _session.objects)
		var ok := not moves.is_empty()
		for m in moves:
			if _session.try_submit(m) != "":
				ok = false
				break
		if not ok:
			_ai_token = -1
			_session.try_submit(GameRules.make_end_turn(state))
			return
	if _ai_token == token:
		_ai_token = -1


func _ai_still_on(token: int) -> bool:
	return _session != null and token == _turn_token and Net.is_ai(_session.state.current_player) \
		and not Net.is_paused(_session.state)


func _any_unit_moving() -> bool:
	for agent in get_tree().get_nodes_in_group("hex_agents"):
		if agent.isMoving:
			return true
	return false
