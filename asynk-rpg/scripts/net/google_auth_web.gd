## Google-Login für den Web-Export (Browser) über Google Identity Services.
##
## Holt ein OAuth-Access-Token mit Scope drive.file. Funktioniert nur im
## Web-Export (OS.has_feature("web")). Für Android/iOS braucht es später ein
## natives Plugin (siehe docs/drive-poc.md).
##
## Warum ein HTML-Button? Browser blockieren Popups, die nicht direkt aus einem
## Klick-Handler kommen. Godot verarbeitet Eingaben aber erst im nächsten Frame,
## deshalb blendet dieses Skript einen echten HTML-Button über dem Canvas ein,
## dessen Klick das Google-Popup synchron öffnet.
class_name GoogleAuthWeb
extends Node

signal token_received(token: String)
signal auth_failed(reason: String)

const SCOPE := "https://www.googleapis.com/auth/drive.file"

var _waiting := false


static func is_supported() -> bool:
	return OS.has_feature("web")


## Zeigt den Anmelde-Button an. client_id = OAuth-Client-ID (Typ "Webanwendung").
func show_login_button(client_id: String, label: String = "Mit Google anmelden") -> void:
	if not is_supported():
		auth_failed.emit("Nur im Web-Export verfügbar")
		return
	var js := """
(function(){
  window.__asynk_token = null; window.__asynk_err = null;
  function setup(){
    var client = google.accounts.oauth2.initTokenClient({
      client_id: %s, scope: %s,
      callback: function(r){ if (r.error) { window.__asynk_err = r.error; } else { window.__asynk_token = r.access_token; }
                              var b = document.getElementById('asynk-login'); if (b) b.remove(); },
      error_callback: function(e){ window.__asynk_err = (e && e.type) || 'popup_error'; }
    });
    var b = document.createElement('button');
    b.id = 'asynk-login'; b.textContent = %s;
    b.style.cssText = 'position:fixed;top:16px;left:50%%;transform:translateX(-50%%);z-index:1000;padding:12px 20px;font-size:16px;';
    b.onclick = function(){ client.requestAccessToken(); };
    document.body.appendChild(b);
  }
  if (window.google && google.accounts && google.accounts.oauth2) { setup(); return; }
  var s = document.createElement('script');
  s.src = 'https://accounts.google.com/gsi/client'; s.async = true; s.onload = setup;
  s.onerror = function(){ window.__asynk_err = 'gsi_load_failed'; };
  document.head.appendChild(s);
})();
""" % [JSON.stringify(client_id), JSON.stringify(SCOPE), JSON.stringify(label)]
	JavaScriptBridge.eval(js, true)
	_waiting = true


func _process(_delta: float) -> void:
	if not _waiting:
		return
	var token: Variant = JavaScriptBridge.eval("window.__asynk_token", true)
	if token is String and not (token as String).is_empty():
		_waiting = false
		token_received.emit(token)
		return
	var err: Variant = JavaScriptBridge.eval("window.__asynk_err", true)
	if err is String and not (err as String).is_empty():
		_waiting = false
		auth_failed.emit(err)
