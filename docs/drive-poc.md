# Drive-Proof-of-Concept: Mitspieler-Dateien lesen mit minimalen Rechten

## Ergebnis der Recherche

**Das Konzept funktioniert, aber nicht über `drive.file` allein.**

- `drive.file` gibt der App nur Zugriff auf Dateien, die sie selbst angelegt hat
  oder die der Nutzer ihr über den Google Picker bzw. "Öffnen mit" gezeigt hat.
  Eine Datei, die Spieler A angelegt und mit B geteilt hat, sieht Bs App damit
  **nicht** automatisch, auch wenn sie aus derselben App stammt.
- Breitere Scopes (`drive`, `drive.readonly`, `drive.metadata*`) sind
  "restricted": Sie brauchen eine Restricted-Scope-Verifizierung, eventuell eine
  kostenpflichtige Sicherheitsprüfung, und nur bestimmte App-Typen (Backup,
  Produktivität, Reporting) sind überhaupt zugelassen. Für ein Spiel ist das
  praktisch ausgeschlossen.

**Lösung (in diesem PoC umgesetzt):**

1. Jeder Spieler legt seine Zugdatei mit `drive.file` an (die App hat sie
   erstellt, darf sie also schreiben und freigeben).
2. Die App gibt die Datei als **"Jeder mit dem Link: Leser"** frei
   (`permissions.create` mit `type=anyone, role=reader`).
3. Mitspieler lesen sie **ohne OAuth** über `files.get?alt=media&key=API_KEY`.
   Für das Polling reicht `files.get?fields=version,modifiedTime&key=API_KEY`.

Damit braucht die App nur den nicht-sensiblen Scope `drive.file`. Das heißt
einfache Markenverifizierung des OAuth-Zustimmungsbildschirms, keine
Sicherheitsprüfung. Bis zu 100 Testnutzer gehen sogar ganz ohne Verifizierung.

Geprüft:
- CORS: `www.googleapis.com` antwortet mit `Access-Control-Allow-Origin` für
  fremde Origins, also klappt das Lesen auch im Web-Export.
- Godot 4.5 headless erreicht die Drive-API mit `HTTPRequest` und bekommt eine
  saubere JSON-Antwort (getestet mit ungültigem Key, ergibt 400 "API key not valid").

Noch **nicht** geprüft (braucht ein echtes Google-Cloud-Projekt und zwei Konten):
- Kompletter Ablauf A schreibt, B liest. Testanleitung siehe unten.

## Nachteile und Gegenmittel

- **Wer die Datei-ID kennt, kann mitlesen.** Die ID ist lang und zufällig, also
  praktisch nicht zu erraten. Bei geheimen Informationen (Nebel des Krieges,
  Handkarten) den Inhalt mit einem Spielschlüssel verschlüsseln, der nur im
  Einladungslink steht.
- **Google-Workspace-Konten** (Firma, Schule) können "jeder mit Link" per
  Admin-Richtlinie verbieten. Normale Gmail-Konten sind nicht betroffen.
- **Der API-Key steckt in der App** und ist damit öffentlich. In der Cloud
  Console auf die Drive-API beschränken, für Web auf die eigene Domain
  (HTTP-Referrer) und für Android auf Paketname plus Signatur.
- **Kontingent:** Alle Lesezugriffe zählen gegen das Kontingent des
  Cloud-Projekts. Polling deshalb sparsam (z. B. beim App-Start und alle paar
  Minuten) und nur `version` abfragen.

## Alternativen, falls das nicht reicht

- **Google Picker:** B wählt As Datei einmal im Picker aus, danach hat Bs App
  per `drive.file` Zugriff. Funktioniert gut im Browser. Auf Android/iOS gibt
  es keinen nativen Picker, nur über eine WebView, das ist umständlich.
- **Kleiner Relay-Server** (Cloudflare Worker, Firebase): speichert nur die
  Datei-IDs und verschickt Push-Benachrichtigungen. Brauchen wir für echte
  Push-Nachrichten ohnehin irgendwann.
- **`drive.appdata`:** nicht geeignet, der App-Ordner kann nicht geteilt werden.

## Anmeldung je Plattform

| Plattform | Weg | Status |
|---|---|---|
| Browser (Web-Export) | Google Identity Services Token-Client über `JavaScriptBridge` | im PoC (`google_auth_web.gd`) |
| Desktop (Test) | Token aus dem OAuth 2.0 Playground einfügen; später Loopback-Redirect | im PoC (Textfeld) |
| Android | Plugin mit Androids `AuthorizationClient` (Google Identity), liefert Access-Token für `drive.file`. Loopback und eigene URI-Schemas sind für Android-Clients nicht erlaubt bzw. standardmäßig gesperrt | offen |
| iOS | Plugin mit GoogleSignIn-SDK | offen |

Hinweis Web: Browser blockieren Popups, die nicht direkt aus einem Klick kommen.
Godot verarbeitet Klicks erst im nächsten Frame, deshalb blendet
`google_auth_web.gd` einen echten HTML-Button ein.

## Dateien

- `asynk-rpg/scripts/net/drive_client.gd`: Datei anlegen, überschreiben,
  freigeben, öffentlich lesen, Version abfragen.
- `asynk-rpg/scripts/net/google_auth_web.gd`: Login im Browser.
- `asynk-rpg/scripts/net/drive_poc.gd` und `asynk-rpg/scenes/drive_poc.tscn`:
  Testoberfläche.

## Testanleitung (ca. 20 Minuten)

1. In der [Google Cloud Console](https://console.cloud.google.com/) ein Projekt
   anlegen und die **Google Drive API** aktivieren.
2. **OAuth-Zustimmungsbildschirm:** Typ "Extern", Status "Testen", Scope
   `.../auth/drive.file`, beide Test-Google-Konten als Testnutzer eintragen.
3. **Anmeldedaten:**
   - API-Schlüssel anlegen, auf die Drive-API beschränken.
   - OAuth-Client-ID Typ "Webanwendung", als autorisierte JavaScript-Quelle
     z. B. `http://localhost:8060` eintragen (Godots Web-Vorschau).
4. In Godot `scenes/drive_poc.tscn` öffnen und per "Remote Debug, In Browser
   ausführen" als Web starten (oder Desktop plus Token aus dem
   [OAuth Playground](https://developers.google.com/oauthplayground/) mit
   Scope `drive.file`).
5. Konto A: API-Key und Client-ID eintragen, "Anmelden", dann
   "Meine Zugdatei anlegen". Die angezeigte Datei-ID kopieren.
6. Konto B (zweites Browserfenster, Inkognito): API-Key eintragen, Datei-ID
   eintragen, "Mitspielerdatei lesen". Erwartet: Inhalt von A erscheint.
7. A: "Zug schreiben". B: "Auf Änderung prüfen", dann erneut lesen.
   Erwartet: neue Version, neuer Zug.
