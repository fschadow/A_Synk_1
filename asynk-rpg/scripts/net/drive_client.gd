## Minimaler Google-Drive-Client für den asynchronen Mehrspieler-Proof-of-Concept.
##
## Idee: Jeder Spieler schreibt nur seine EIGENE Zugdatei (Scope drive.file,
## die App hat die Datei selbst erstellt). Die Datei wird "jeder mit Link: Leser"
## freigegeben. Mitspieler lesen sie dann OHNE OAuth, nur mit API-Key + Datei-ID.
##
## Schreiben braucht ein OAuth-Access-Token mit Scope
##   https://www.googleapis.com/auth/drive.file
## Lesen fremder Dateien braucht nur einen API-Key des Cloud-Projekts.
class_name DriveClient
extends Node

const API := "https://www.googleapis.com/drive/v3/files"
const UPLOAD := "https://www.googleapis.com/upload/drive/v3/files"
const SCOPE := "https://www.googleapis.com/auth/drive.file"
const BOUNDARY := "asynk_boundary_7f3a"

## OAuth-Access-Token (nur zum Schreiben der eigenen Datei).
var access_token: String = ""
## API-Key aus der Google Cloud Console (nur zum Lesen öffentlicher Dateien).
var api_key: String = ""


## Ergebnis jedes Aufrufs: { ok: bool, code: int, data: Variant, text: String }
func _request(url: String, method: int, headers: PackedStringArray, body: String = "") -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": -1, "data": null, "text": "request() Fehler %d" % err}
	var res: Array = await http.request_completed
	http.queue_free()
	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
	return {"ok": code >= 200 and code < 300, "code": code, "data": data, "text": text}


func _auth_headers(extra: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var h := PackedStringArray(["Authorization: Bearer " + access_token])
	h.append_array(extra)
	return h


## Legt eine neue JSON-Datei im Drive des angemeldeten Spielers an.
## Rückgabe: Datei-ID oder "" bei Fehler.
func create_json_file(file_name: String, content: Dictionary) -> String:
	var meta := JSON.stringify({"name": file_name, "mimeType": "application/json"})
	var body := "--%s\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n%s\r\n" % [BOUNDARY, meta]
	body += "--%s\r\nContent-Type: application/json\r\n\r\n%s\r\n--%s--" % [BOUNDARY, JSON.stringify(content), BOUNDARY]
	var res := await _request(UPLOAD + "?uploadType=multipart&fields=id",
		HTTPClient.METHOD_POST,
		_auth_headers(["Content-Type: multipart/related; boundary=" + BOUNDARY]), body)
	if not res.ok:
		push_warning("create_json_file: %d %s" % [res.code, res.text])
		return ""
	return res.data.get("id", "")


## Überschreibt den Inhalt der eigenen Datei (z. B. nach einem neuen Zug).
func update_json_file(file_id: String, content: Dictionary) -> bool:
	var res := await _request(UPLOAD + "/%s?uploadType=media&fields=id,version" % file_id,
		HTTPClient.METHOD_PATCH,
		_auth_headers(["Content-Type: application/json"]), JSON.stringify(content))
	if not res.ok:
		push_warning("update_json_file: %d %s" % [res.code, res.text])
	return res.ok


## Gibt die Datei als "jeder mit Link: Leser" frei (ohne Mail-Benachrichtigung).
func share_anyone_with_link(file_id: String) -> bool:
	var res := await _request(API + "/%s/permissions?fields=id" % file_id,
		HTTPClient.METHOD_POST,
		_auth_headers(["Content-Type: application/json"]),
		JSON.stringify({"type": "anyone", "role": "reader"}))
	if not res.ok:
		push_warning("share_anyone_with_link: %d %s" % [res.code, res.text])
	return res.ok


## Liest eine öffentlich freigegebene Datei eines Mitspielers – nur mit API-Key.
## Rückgabe: Inhalt als Dictionary oder null.
func read_public_json(file_id: String) -> Variant:
	var res := await _request(API + "/%s?alt=media&key=%s" % [file_id, api_key],
		HTTPClient.METHOD_GET, PackedStringArray())
	if not res.ok:
		push_warning("read_public_json: %d %s" % [res.code, res.text])
		return null
	return res.data


## Billige Abfrage, ob sich eine fremde Datei geändert hat (für Polling).
## Rückgabe: { version, modifiedTime } oder null.
func get_public_version(file_id: String) -> Variant:
	var res := await _request(API + "/%s?fields=version,modifiedTime&key=%s" % [file_id, api_key],
		HTTPClient.METHOD_GET, PackedStringArray())
	if not res.ok:
		push_warning("get_public_version: %d %s" % [res.code, res.text])
		return null
	return res.data
