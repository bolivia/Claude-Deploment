#Requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms

# ============================================================
# KONFIGURATION — muss identisch mit Manage-ClaudeKeys.ps1 sein
# ============================================================
$AES_KEY = [byte[]](
    # TODO: Eigenen 32-Byte AES-256-Schluessel eintragen (identisch in Manage-ClaudeKeys.ps1!)
    0, 0, 0, 0,  0, 0, 0, 0,
    0, 0, 0, 0,  0, 0, 0, 0,
    0, 0, 0, 0,  0, 0, 0, 0,
    0, 0, 0, 0,  0, 0, 0, 0
)

$KeyFilePath  = "\\corp.local\NETLOGON\ClaudeDeployment\claude_keys.dat"
$LiteLLMUrl   = "https://litellm.example-corp.com"
$ClaudeModel  = "vertex_ai/claude-sonnet-4-6"
# ============================================================

function Decrypt-Key([string]$Base64) {
    try {
        $data   = [Convert]::FromBase64String($Base64)
        $iv     = $data[0..15]
        $cipher = $data[16..($data.Length - 1)]
        $aes    = [System.Security.Cryptography.Aes]::Create()
        $aes.Key     = $AES_KEY
        $aes.IV      = $iv
        $aes.Mode    = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $dec   = $aes.CreateDecryptor()
        $plain = $dec.TransformFinalBlock($cipher, 0, $cipher.Length)
        $aes.Dispose()
        [System.Text.Encoding]::UTF8.GetString($plain)
    } catch { $null }
}

function Write-Log([string]$Msg) {
    Write-Host "$(Get-Date -Format 'HH:mm:ss')  $Msg"
}

Write-Log "Skript gestartet"

# UPN via whoami /upn (Entra-joined, kein lokales AD noetig)
$upn = $null
try {
    $raw = whoami /upn 2>$null
    # Nur uebernehmen wenn es wie eine E-Mail-Adresse aussieht
    if ($raw -and $raw.Trim() -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        $upn = $raw.Trim()
    }
} catch {}

# Fallback: dsregcmd /status
if (-not $upn -or $upn -eq '') {
    try {
        $dsreg = dsregcmd /status 2>$null
        $match = $dsreg | Select-String 'UserPrincipalName\s*:\s*(\S+@\S+)'
        if ($match) { $upn = $match.Matches.Groups[1].Value.Trim() }
    } catch {}
}

Write-Log "UPN ermittelt: '$upn'"
if (-not $upn -or $upn -eq '') { Write-Log "Abbruch: kein UPN gefunden"; exit 0 }

# Key aus verschluesselter Datei lesen
try {
    if (-not (Test-Path $KeyFilePath)) {
        Write-Log "Abbruch: Datei nicht gefunden: $KeyFilePath"
        exit 0
    }

    $rawContent = Get-Content $KeyFilePath -Raw -Encoding UTF8
    if (-not $rawContent -or $rawContent.Trim() -eq '') {
        Write-Log "Abbruch: Datei ist leer: $KeyFilePath"
        exit 0
    }
    $json  = $rawContent | ConvertFrom-Json
    $entry = $json.users | Where-Object { $_.upn -ieq $upn } | Select-Object -First 1
    if (-not $entry) {
        Write-Log "Abbruch: UPN '$upn' nicht in der Datei enthalten"
        exit 0
    }

    $key = Decrypt-Key $entry.key
    if (-not $key) {
        Write-Log "Abbruch: Entschluesselung fehlgeschlagen"
        exit 0
    }

    # --- Claude-Prozesse im Userkontext beenden ---
    $currentSession = (Get-Process -Id $PID).SessionId
    $claudeProcs = Get-Process -Name 'claude' -ErrorAction SilentlyContinue |
                   Where-Object { $_.SessionId -eq $currentSession }
    if ($claudeProcs) {
        $claudeProcs | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Log "$($claudeProcs.Count) claude.exe-Prozess(e) beendet"
        Start-Sleep -Seconds 1
    } else {
        Write-Log "Keine claude.exe-Prozesse gefunden"
    }

    # --- App-Cache loeschen ---
    $cacheDir = Join-Path $env:LOCALAPPDATA 'Packages\Claude_pzs8sxrjxfjjc\LocalCache'
    if (Test-Path $cacheDir) {
        Remove-Item -Path $cacheDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "App-Cache geloescht: $cacheDir"
    } else {
        Write-Log "App-Cache nicht gefunden (wird uebersprungen)"
    }

    # --- settings.json fuer Claude Code / Cowork schreiben ---
    $claudeDir    = Join-Path $env:APPDATA 'Claude-3p'
    $settingsPath = Join-Path $claudeDir 'claude_desktop_config.json'

    if (-not (Test-Path $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    }

    $settings = [ordered]@{
        deploymentMode   = '3p'
        enterpriseConfig = [ordered]@{
            inferenceProvider            = 'gateway'
            inferenceGatewayBaseUrl      = $LiteLLMUrl
            inferenceGatewayApiKey       = $key
            inferenceGatewayAuthScheme   = 'bearer'
            inferenceModels              = "[`"$ClaudeModel`"]"
            disableDeploymentModeChooser = 'true'
        }
        _cfprefsMigrated = $true
        preferences      = [ordered]@{
            coworkScheduledTasksEnabled  = $true
            ccdScheduledTasksEnabled     = $false
            sidebarMode                  = 'task'
            bypassPermissionsModeEnabled = $true
            coworkWebSearchEnabled       = $true
        }
    }

    $json = $settings | ConvertTo-Json -Depth 3
    # UTF-8 ohne BOM schreiben (Set-Content -Encoding UTF8 wuerde BOM hinzufuegen)
    [System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding $false))

    Write-Log "claude_desktop_config.json erfolgreich geschrieben: $settingsPath"

} catch {
    Write-Log "Fehler (catch): $_"
    exit 0
}
