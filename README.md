# Claude Deployment – Deployment-Anleitung

> IT-Dokumentation: LiteLLM Key-Verwaltung und automatische Claude-Konfiguration per Anmeldeskript

| | Pfad |
|---|---|
| **Admin-Tool & Arbeitsdatei** | `\\fileserver\shares\Claude Deployment\` |
| **Deployment-Ziel (Netlogon)** | `\\corp.local\NETLOGON\ClaudeDeployment\` |
| **LiteLLM Gateway** | `https://litellm.example-corp.com` |

---

## 1 – Überblick & Funktionsweise

Das System verteilt automatisch LiteLLM API-Keys an Benutzer und konfiguriert Claude Desktop ohne manuellen Eingriff. Es besteht aus zwei Komponenten:

| Komponente | Zweck | Datei |
|---|---|---|
| **Admin-Tool (GUI)** | Keys erstellen, löschen, Budget anpassen – kommuniziert direkt mit der LiteLLM API | `Manage-ClaudeKeys.ps1` |
| **Anmeldeskript** | Läuft bei jedem Login, liest Key, beendet Prozesse, leert Cache und schreibt die Claude-Konfiguration (zwei Dateien im configLibrary-Ordner) | `Get-ClaudeKey.ps1` |

### Workflow Admin (bei jeder Änderung)

1. Admin-Tool starten, Keys bearbeiten (erstellen / löschen / Budget)
2. Beim Schließen erinnert das Tool: **claude_keys.dat manuell vom Dateiserver ins Netlogon kopieren**
3. Quelle: `\\fileserver\shares\Claude Deployment\claude_keys.dat`
4. Ziel: `\\corp.local\NETLOGON\ClaudeDeployment\claude_keys.dat`

### Was passiert beim Benutzer-Login

1. UPN ermitteln via `whoami /upn` (Entra-joined, kein lokales AD erforderlich)
2. Verschlüsselten Key aus `claude_keys.dat` im Netlogon lesen und entschlüsseln
3. Laufende `claude.exe`-Prozesse der aktuellen Benutzersitzung beenden
4. App-Cache löschen (`%LOCALAPPDATA%\Packages\Claude_XXXXXXXXXXXXXXXXX\LocalCache`)
5. Zwei Konfigurationsdateien in beide configLibrary-Ordner schreiben — Claude Desktop sofort einsatzbereit
   - `%LOCALAPPDATA%\Claude-3p\configLibrary\`
   - `%APPDATA%\Claude-3p\configLibrary\`

> **Info:** Hat ein Benutzer keinen Eintrag in der Datenbank, passiert beim Login nichts – kein Fehler-Popup, kein Abbruch des Anmeldevorgangs.

---

## 2 – Voraussetzungen

| Anforderung | Details |
|---|---|
| **Betriebssystem** | Windows 10 / 11, Microsoft Entra-joined (kein lokales AD erforderlich) |
| **PowerShell** | Version 5.1 oder neuer (standardmäßig vorhanden) |
| **Netzwerk (Admin)** | Zugriff auf `\\fileserver\shares\` und Schreibrecht auf `...\ClaudeDeployment\` |
| **Netzwerk (Client)** | Lesezugriff auf `\\corp.local\NETLOGON\` (Standard für Domänen-Benutzer) |
| **Internet (Admin-PC)** | HTTPS-Zugriff auf die LiteLLM-Gateway-URL |

---

## 3 – Erstkonfiguration (vor dem ersten Einsatz)

Die folgenden Werte müssen in beiden Skripten auf die eigene Umgebung angepasst werden:

| Skript | Variable | Beschreibung |
|---|---|---|
| beide | `$AES_KEY` | 32 zufällige Bytes (AES-256) – in beiden Skripten **identisch** |
| `Get-ClaudeKey.ps1` | `$KeyFilePath` | UNC-Pfad zu `claude_keys.dat` im Netlogon |
| `Get-ClaudeKey.ps1` | `$LiteLLMUrl` | URL des LiteLLM-Gateways |
| `Manage-ClaudeKeys.ps1` | `$script:DefaultKeyFilePath` | UNC-Pfad zur Arbeitskopie auf dem Dateiserver |
| `Manage-ClaudeKeys.ps1` | `$script:DeployTargetPath` | UNC-Pfad zum Netlogon-Ziel |
| `Manage-ClaudeKeys.ps1` | `$script:LiteLLMUrl` | URL des LiteLLM-Gateways |
| `Manage-ClaudeKeys.ps1` | `$script:LiteLLMMaster` | LiteLLM Master Key |
| `Manage-ClaudeKeys.ps1` | `$script:LiteLLMTeamId` | LiteLLM Team-ID (optional) |

> **AES-Schlüssel erzeugen** (PowerShell): `[byte[]]::new(32) | ForEach-Object { Get-Random -Maximum 256 }`

---

## 4 – Admin-Tool starten

```
\\fileserver\shares\Claude Deployment\Start-KeyManager.cmd
```

Doppelklick auf `Start-KeyManager.cmd` genügt. Die Datei umgeht automatisch die PowerShell-ExecutionPolicy. Die Arbeitsdatei `claude_keys.dat` wird auf dem Dateiserver gespeichert und bearbeitet.

> **Achtung:** Niemals die `.ps1`-Datei direkt per Doppelklick starten – die ExecutionPolicy blockiert dies in den meisten Umgebungen.

> **Wichtig nach jeder Änderung:** Das Tool erinnert beim Schließen daran, die Datei manuell ins Netlogon zu kopieren. Erst danach erhalten Benutzer beim Login den aktualisierten Key.
>
> - Von: `\\fileserver\shares\Claude Deployment\claude_keys.dat`
> - Nach: `\\corp.local\NETLOGON\ClaudeDeployment\claude_keys.dat`

---

## 5 – Neuen Benutzer anlegen

1. Admin-Tool starten (siehe Abschnitt 4)
2. Klick auf **[+ Hinzufügen]**
3. UPN des Benutzers eingeben, z. B. `max.mustermann@example-corp.com`
4. Budget in USD festlegen (Standard: 50,00 USD)
5. Klick auf **[Erstellen]**

Das Tool führt danach automatisch folgende Schritte aus:

| Aktion | Details |
|---|---|
| LiteLLM API-Aufruf | `POST /key/generate` mit `key_alias = "ClaudeDeployTool_<UPN>"`, Budget und `team_id` |
| Key speichern | Key wird AES-256-verschlüsselt in `claude_keys.dat` gespeichert |
| Bestätigung | Der erstellte Key wird zur Kontrolle einmalig im Klartext angezeigt |

> **Hinweis:** Beim nächsten Login des Benutzers erhält er den Key automatisch per MessageBox und Claude wird konfiguriert – **sofern die Datei bereits ins Netlogon kopiert wurde**.

---

## 6 – Budget eines Benutzers anpassen

1. Benutzer in der Liste auswählen (Klick auf die Zeile)
2. Klick auf **[Budget anpassen]**
3. Neuen Betrag eingeben und **[Aktualisieren]** klicken

Das Budget wird sofort per `POST /key/update` in LiteLLM aktualisiert und gleichzeitig in der lokalen Datei gespeichert. Kein erneuter Login des Benutzers erforderlich.

---

## 7 – Benutzer und Key löschen

1. Benutzer in der Liste auswählen
2. Klick auf **[Löschen]** oder **Entf**-Taste drücken
3. Sicherheitsabfrage mit **[Ja]** bestätigen

Das Tool ruft `POST /key/delete` auf – der Key ist damit sofort ungültig – und entfernt den Eintrag aus der Datei.

> **Achtung:** Dieser Vorgang ist nicht rückgängig zu machen. Der Benutzer benötigt danach einen neuen Key (erneut über + Hinzufügen anlegen). Sollte die LiteLLM-API beim Löschen nicht erreichbar sein, fragt das Tool, ob der Eintrag trotzdem lokal entfernt werden soll.

---

## 8 – Anmeldeskript einbinden (GPO)

GPO-Pfad: **Benutzerkonfiguration → Windows-Einstellungen → Skripts → Anmelden**

| | |
|---|---|
| **Programm** | `powershell.exe` |
| **Parameter** | `-WindowStyle Hidden -ExecutionPolicy Bypass -File "\\corp.local\NETLOGON\ClaudeDeployment\Get-ClaudeKey.ps1"` |

> **Info:** `-WindowStyle Hidden` verhindert, dass ein PowerShell-Fenster aufgeht. Das Skript läuft vollständig im Hintergrund – ohne sichtbare Benutzerinteraktion.

---

## 9 – Erzeugte Konfiguration beim Benutzer

Das Anmeldeskript schreibt bei jedem Login **zwei Dateien** in beide folgenden Ordner (werden überschrieben, damit Key-Änderungen immer ankommen). Die Ordner werden automatisch erstellt, falls sie nicht existieren:

```
%LOCALAPPDATA%\Claude-3p\configLibrary\
%APPDATA%\Claude-3p\configLibrary\
```

Beide Pfade erhalten identische Dateien. Vor dem Schreiben werden laufende `claude.exe`-Prozesse beendet und der App-Cache geleert, damit die neue Konfiguration beim nächsten Start sauber übernommen wird.

**Datei 1: `_meta.json`**

```json
{
  "appliedId": "<config-uuid>",
  "entries": [
    {
      "id":   "<config-uuid>",
      "name": "Default"
    }
  ]
}
```

**Datei 2: `<config-uuid>.json`**

```json
{
  "disableDeploymentModeChooser": true,
  "inferenceProvider":            "gateway",
  "inferenceGatewayBaseUrl":      "https://litellm.example-corp.com",
  "inferenceGatewayApiKey":       "sk-..."
}
```

Der entschlüsselte Key steht im Klartext im Feld `inferenceGatewayApiKey`. Beide Dateien werden als UTF-8 ohne BOM geschrieben.

---

## 10 – Dateien im Überblick

### `\\fileserver\shares\Claude Deployment\`

| Datei | Rolle | Beschreibung |
|---|---|---|
| `Manage-ClaudeKeys.ps1` | ADMIN | Admin-GUI – Keys erstellen, löschen, Budget anpassen |
| `Start-KeyManager.cmd` | ADMIN | Starter – ExecutionPolicy Bypass, immer diesen verwenden |
| `claude_keys.dat` | ADMIN | AES-256-verschlüsselte Key-Datenbank (Arbeitskopie) |

⬇ *nach jeder Änderung manuell kopieren* ⬇

### `\\corp.local\NETLOGON\ClaudeDeployment\`

| Datei | Rolle | Beschreibung |
|---|---|---|
| `Get-ClaudeKey.ps1` | GPO | Anmeldeskript – Key anzeigen, Prozesse beenden, Cache löschen, Config schreiben |
| `claude_keys.dat` | DATEN | Kopie der Key-Datenbank – muss nach jeder Änderung manuell hierher kopiert werden |

### `%LOCALAPPDATA%\Claude-3p\configLibrary\` und `%APPDATA%\Claude-3p\configLibrary\` (pro Benutzer)

Beide Pfade erhalten bei jedem Login identische Dateien:

| Datei | Beschreibung |
|---|---|
| `_meta.json` | Index-Datei mit aktiver Konfigurations-ID – wird bei jedem Login überschrieben |
| `<config-uuid>.json` | Claude-Desktop-Konfiguration mit Gateway-URL und API-Key – wird bei jedem Login überschrieben |

---

## 11 – Fehlerbehebung

| Problem | Ursache | Lösung |
|---|---|---|
| **GUI startet nicht** | PowerShell ExecutionPolicy blockiert | Immer `Start-KeyManager.cmd` verwenden, nie `.ps1` direkt |
| **Authentication Error: Only proxy admin …** | Kein Master Key eingetragen | `Manage-ClaudeKeys.ps1`: `$script:LiteLLMMaster` mit dem LiteLLM-Master-Key befüllen |
| **Kein Popup beim Login** | UPN nicht in `claude_keys.dat` | Benutzer über **+ Hinzufügen** im Admin-Tool anlegen |
| **Änderungen kommen nicht an** | `claude_keys.dat` nicht ins Netlogon kopiert | Datei manuell vom Dateiserver ins Netlogon kopieren |
| **Claude Desktop startet nicht / ignoriert Config** | Alter Prozess oder Cache blockiert | Abmelden und neu anmelden – Skript beendet Prozesse und leert Cache automatisch |
| **Datei nicht erreichbar** | Netzwerkproblem / Netlogon-Share nicht verfügbar | Verbindung zu `\\corp.local\NETLOGON\` prüfen. Skript bricht still ab – kein Einfluss auf Login |
