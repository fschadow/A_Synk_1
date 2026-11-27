class_name LanDiscovery
extends Node
## Findet offene Spiele im lokalen Netz per UDP:
## - Der Host lauscht auf DISCOVERY_PORT und beantwortet Suchanfragen mit
##   einer kurzen Beschreibung seines Spiels (JSON).
## - Ein suchendes Geraet schickt jede Sekunde eine Anfrage an die
##   Broadcast-Adressen und sammelt die Antworten in `hosts`.
## Klappt das nicht (manche WLANs blockieren Broadcasts), bleibt die
## IP-Eingabe von Hand.

signal hosts_changed

const QUERY := "ASYNK_SEARCH/1"
const GAME_TAG := "AsynkRPG"
const QUERY_INTERVAL := 1.0
## Nach so vielen Millisekunden ohne Antwort verschwindet ein Spiel aus der Liste.
const HOST_TIMEOUT_MS := 4000

var port := 47001
## ip -> {"info": Dictionary, "seen": int (msec)}
var hosts := {}

var _host_udp: PacketPeerUDP
var _info_func: Callable
var _search_udp: PacketPeerUDP
var _next_query := 0.0


func is_searching() -> bool:
	return _search_udp != null


## Host: ab jetzt Suchanfragen beantworten. info_func liefert das Dictionary.
func start_host(info_func: Callable) -> bool:
	stop_host()
	_host_udp = PacketPeerUDP.new()
	if _host_udp.bind(port) != OK:
		push_warning("LanDiscovery: Port %d belegt, Spiel ist nur per IP erreichbar" % port)
		_host_udp = null
		return false
	_info_func = info_func
	return true


func stop_host() -> void:
	if _host_udp:
		_host_udp.close()
	_host_udp = null


func start_search() -> void:
	stop_search()
	_search_udp = PacketPeerUDP.new()
	_search_udp.set_broadcast_enabled(true)
	if _search_udp.bind(0) != OK:
		push_warning("LanDiscovery: Suche konnte nicht starten")
		_search_udp = null
		return
	_next_query = 0.0
	hosts.clear()
	hosts_changed.emit()


func stop_search() -> void:
	if _search_udp:
		_search_udp.close()
	_search_udp = null


func stop() -> void:
	stop_host()
	stop_search()


## Gefundene Spiele als Liste [{ip, info}], sortiert nach IP.
func host_list() -> Array:
	var out := []
	var ips := hosts.keys()
	ips.sort()
	for ip in ips:
		out.append({"ip": ip, "info": hosts[ip]["info"]})
	return out


func _process(delta: float) -> void:
	_poll_host()
	_poll_search(delta)


func _poll_host() -> void:
	if _host_udp == null:
		return
	while _host_udp.get_available_packet_count() > 0:
		var text := _host_udp.get_packet().get_string_from_utf8()
		var ip := _host_udp.get_packet_ip()
		var from_port := _host_udp.get_packet_port()
		if text != QUERY or ip == "":
			continue
		var info: Dictionary = _info_func.call()
		info["game"] = GAME_TAG
		_host_udp.set_dest_address(ip, from_port)
		_host_udp.put_packet(JSON.stringify(info).to_utf8_buffer())


func _poll_search(delta: float) -> void:
	if _search_udp == null:
		return
	_next_query -= delta
	if _next_query <= 0.0:
		_next_query = QUERY_INTERVAL
		for target in broadcast_targets():
			_search_udp.set_dest_address(target, port)
			_search_udp.put_packet(QUERY.to_utf8_buffer())

	var changed := false
	var now := Time.get_ticks_msec()
	while _search_udp.get_available_packet_count() > 0:
		var text := _search_udp.get_packet().get_string_from_utf8()
		var ip := _search_udp.get_packet_ip()
		var info = JSON.parse_string(text)
		if not info is Dictionary or info.get("game", "") != GAME_TAG:
			continue
		# Dasselbe Geraet antwortet evtl. ueber Loopback und WLAN: echte IP bevorzugen.
		if ip.begins_with("127.") and _has_other_entry_for(info):
			continue
		if not hosts.has(ip) or hosts[ip]["info"] != info:
			changed = true
		hosts[ip] = {"info": info, "seen": now}
	for ip in hosts.keys():
		if now - int(hosts[ip]["seen"]) > HOST_TIMEOUT_MS:
			hosts.erase(ip)
			changed = true
	if changed:
		hosts_changed.emit()


func _has_other_entry_for(info: Dictionary) -> bool:
	for ip in hosts:
		if not ip.begins_with("127.") and hosts[ip]["info"].get("id", "") == info.get("id", ""):
			return true
	return false


## Broadcast-Adressen: allgemein, je lokales Netz (x.y.z.255) und Loopback
## (damit zwei Instanzen auf demselben Rechner sich auch finden).
static func broadcast_targets() -> Array:
	var targets := ["255.255.255.255", "127.0.0.1"]
	for ip in local_ipv4():
		var parts: PackedStringArray = ip.split(".")
		var b := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not targets.has(b):
			targets.append(b)
	return targets


## Eigene IPv4-Adressen im LAN (ohne Loopback und ohne 169.254.x.x).
static func local_ipv4() -> Array:
	var out := []
	for ip in IP.get_local_addresses():
		if ip.count(".") != 3 or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		out.append(ip)
	# Typische Heim-WLANs (192.168.x.x) zuerst, dann 10.x, dann der Rest
	# (172.x sind oft virtuelle Adapter von WSL/Docker/VirtualBox).
	out.sort_custom(func(a, b): return _rank(a) < _rank(b) or (_rank(a) == _rank(b) and a < b))
	return out


static func _rank(ip: String) -> int:
	if ip.begins_with("192.168.56."):
		return 3  # VirtualBox
	if ip.begins_with("192.168."):
		return 0
	if ip.begins_with("10."):
		return 1
	return 2
