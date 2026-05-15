# Claude Cowork – Deployment-Anleitung

> IT-Dokumentation: LiteLLM Key-Verwaltung und automatische Cowork-Konfiguration per Anmeldeskript

| | Pfad |
|---|---|
| **Admin-Tool & Arbeitsdatei** | `\\fileserver\shares\Claude Deployment\` |
| **Deployment-Ziel (Netlogon)** | `\\corp.local\netlogon\login-scripts\ClaudeDeployment\` |
| **LiteLLM Gateway** | `https://litellm.ai.example-corp.de` |

---

## 1 – Überblick & Funktionsweise

Das System verteilt automatisch LiteLLM API-Keys an Benutzer und konfiguriert Claude Code / Cowork ohne manuellen Eingriff. Es besteht aus zwei Komponenten:

| Komponente | Zweck | Datei |
|---|---|---|
| **Admin-Tool (GUI)** | Keys erstellen, löschen, Budget anpassen – kommuniziert direkt mit der LiteLLM API | `Manage-ClaudeKeys.ps1` |
| **Anmeldeskript** | Läuft bei jedem Login, liest Key, zeigt MessageBox und schreibt die Cowork-Konfiguration | `Get-ClaudeKey.ps1` |

### Workflow Admin (bei jeder Änderung)

1. Admin-Tool starten, Keys bearbeiten (erstellen / löschen / Budget)
2. Beim Schließen erinnert das Tool: **claude_keys.dat manuell vom Dateiserver ins Netlogon kopieren**
3. Quelle: `\\fileserver\shares\Claude Deployment\claude_keys.dat`
4. Ziel: `\\corp.local\netlogon\login-scripts\ClaudeDeployment\claude_keys.dat`

### Was passiert beim Benutzer-Login

1. UPN ermitteln via `whoami /upn` (Entra-joined, kein lokales AD erforderlich)
2. Verschlüsselten Key aus `claude_keys.dat` im Netlogon lesen und entschlüsseln
3. MessageBox mit API-Key und Budget anzeigen
4. `%USERPROFILE%\.claude\settings.json` erstellen / überschreiben — Cowork sofort einsatzbereit

> **Info:** Hat ein Benutzer keinen Eintrag in der Datenbank, passiert beim Login nichts – kein Fehler-Popup, kein Abbruch des Anmeldevorgangs.

---

## 2 – Voraussetzungen

| Anforderung | Details |
|---|---|
| **Betriebssystem** | Windows 10 / 11, Microsoft Entra-joined (kein lokales AD erforderlich) |
| **PowerShell** | Version 5.1 oder neuer (standardmäßig vorhanden) |
| **Netzwerk (Admin)** | Zugriff auf `\\fileserver\shares\` und Schreibrecht auf `...\ClaudeDeployment\` |
| **Netzwerk (Client)** | Lesezugriff auf `\\corp.local\netlogon\` (Standard für Domänen-Benutzer) |
| **Internet (Admin-PC)** | HTTPS-Zugriff auf `https://litellm.ai.example-corp.de` |

---

## 3 – Admin-Tool starten

```
\\fileserver\shares\Claude Deployment\Start-KeyManager.cmd
```

Doppelklick auf `Start-KeyManager.cmd` genügt. Die Datei umgeht automatisch die PowerShell-ExecutionPolicy. Die Arbeitsdatei `claude_keys.dat` wird auf dem Dateiserver gespeichert und bearbeitet.

> **Achtung:** Niemals die `.ps1`-Datei direkt per Doppelklick starten – die ExecutionPolicy blockiert dies in den meisten Umgebungen.

> **Wichtig nach jeder Änderung:** Das Tool erinnert beim Schließen daran, die Datei manuell ins Netlogon zu kopieren. Erst danach erhalten Benutzer beim Login den aktualisierten Key.
>
> - Von: `\\fileserver\shares\Claude Deployment\claude_keys.dat`
> - Nach: `\\corp.local\netlogon\login-scripts\ClaudeDeployment\claude_keys.dat`

---

## 4 – Neuen Benutzer anlegen

1. Admin-Tool starten (siehe Abschnitt 3)
2. Klick auf **[+ Hinzufügen]**
3. UPN des Benutzers eingeben, z. B. `max.mustermann@example-corp.de`
4. Budget in USD festlegen (Standard: 50,00 USD)
5. Klick auf **[Erstellen]**

Das Tool führt danach automatisch folgende Schritte aus:

| Aktion | Details |
|---|---|
| LiteLLM API-Aufruf | `POST /key/generate` mit UPN als `user_id`, Budget und `key_alias = "ClaudeDeployTool_<UPN>"` |
| Key speichern | Key wird AES-256-verschlüsselt in `claude_keys.dat` gespeichert |
| Bestätigung | Der erstellte Key wird zur Kontrolle einmalig im Klartext angezeigt |

> **Hinweis:** Beim nächsten Login des Benutzers erhält er den Key automatisch per MessageBox und Cowork wird konfiguriert – **sofern die Datei bereits ins Netlogon kopiert wurde**.

---

## 5 – Budget eines Benutzers anpassen

1. Benutzer in der Liste auswählen (Klick auf die Zeile)
2. Klick auf **[Budget anpassen]**
3. Neuen Betrag eingeben und **[Aktualisieren]** klicken

Das Budget wird sofort per `POST /key/update` in LiteLLM aktualisiert und gleichzeitig in der lokalen Datei gespeichert. Kein erneuter Login des Benutzers erforderlich.

---

## 6 – Benutzer und Key löschen

1. Benutzer in der Liste auswählen
2. Klick auf **[Löschen]** oder **Entf**-Taste drücken
3. Sicherheitsabfrage mit **[Ja]** bestätigen

Das Tool ruft `POST /key/delete` auf – der Key ist damit sofort ungültig – und entfernt den Eintrag aus der Datei.

> **Achtung:** Dieser Vorgang ist nicht rückgängig zu machen. Der Benutzer benötigt danach einen neuen Key (erneut über + Hinzufügen anlegen). Sollte die LiteLLM-API beim Löschen nicht erreichbar sein, fragt das Tool, ob der Eintrag trotzdem lokal entfernt werden soll.

---

## 7 – Anmeldeskript einbinden (GPO)

GPO-Pfad: **Benutzerkonfiguration → Windows-Einstellungen → Skripts → Anmelden**

| | |
|---|---|
| **Programm** | `powershell.exe` |
| **Parameter** | `-WindowStyle Hidden -ExecutionPolicy Bypass -File "\\corp.local\netlogon\login-scripts\ClaudeDeployment\Get-ClaudeKey.ps1"` |

> **Info:** `-WindowStyle Hidden` verhindert, dass ein PowerShell-Fenster aufgeht. Die MessageBox erscheint trotzdem, da sie über Windows Forms läuft.

---

## 8 – Erzeugte Konfiguration beim Benutzer

Das Anmeldeskript schreibt bei jedem Login folgende Datei (wird überschrieben, damit Key-Änderungen immer ankommen):

```
%USERPROFILE%\.claude\settings.json
```

Inhalt (Beispiel):

```json
{
  "inferenceProvider":                 "gateway",
  "inferenceGatewayBaseUrl":           "https://litellm.ai.example-corp.de",
  "inferenceGatewayApiKey":            "sk-...",
  "model":                             "vertex_ai/claude-sonnet-4-6",
  "effortLevel":                       "medium",
  "autoUpdatesChannel":                "latest",
  "skipDangerousModePermissionPrompt": true,
  "enabledPlugins": {
    "frontend-design@claude-plugins-official": true
  }
}
```

---

## 9 – Dateien im Überblick

### `\\fileserver\shares\Claude Deployment\`

| Datei | Rolle | Beschreibung |
|---|---|---|
| `Manage-ClaudeKeys.ps1` | ADMIN | Admin-GUI – Keys erstellen, löschen, Budget anpassen |
| `Start-KeyManager.cmd` | ADMIN | Starter – ExecutionPolicy Bypass, immer diesen verwenden |
| `claude_keys.dat` | ADMIN | AES-256-verschlüsselte Key-Datenbank (Arbeitskopie) |

⬇ *nach jeder Änderung manuell kopieren* ⬇

### `\\corp.local\netlogon\login-scripts\ClaudeDeployment\`

| Datei | Rolle | Beschreibung |
|---|---|---|
| `Get-ClaudeKey.ps1` | GPO | Anmeldeskript – Key anzeigen und settings.json schreiben |
| `claude_keys.dat` | DATEN | Kopie der Key-Datenbank – muss nach jeder Änderung manuell hierher kopiert werden |

### `%USERPROFILE%\.claude\` (pro Benutzer)

| Datei | Beschreibung |
|---|---|
| `settings.json` | Cowork-Konfiguration – wird bei jedem Login vom Anmeldeskript überschrieben |

---

## 10 – Fehlerbehebung

| Problem | Ursache | Lösung |
|---|---|---|
| **GUI startet nicht** | PowerShell ExecutionPolicy blockiert | Immer `Start-KeyManager.cmd` verwenden, nie `.ps1` direkt |
| **Authentication Error: Only proxy admin …** | Kein Master Key eingetragen | `Manage-ClaudeKeys.ps1` Zeile 18: LITELLM_MASTER_KEY aus den Hosting-Umgebungsvariablen eintragen |
| **Kein Popup beim Login** | UPN nicht in `claude_keys.dat` | Benutzer über **+ Hinzufügen** im Admin-Tool anlegen |
| **Änderungen kommen nicht an** | `claude_keys.dat` nicht ins Netlogon kopiert | Datei manuell vom Dateiserver ins Netlogon kopieren |
| **Cowork verbindet sich nicht** | `settings.json` fehlt oder veraltet | Benutzer ab- und wieder anmelden |
| **Datei nicht erreichbar** | Netzwerkproblem / Netlogon-Share nicht verfügbar | Verbindung zu `\\corp.local\netlogon\` prüfen. Skript bricht still ab – kein Einfluss auf Login |
