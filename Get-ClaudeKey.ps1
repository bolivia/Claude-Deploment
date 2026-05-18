#Requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms

# ============================================================
# KONFIGURATION — muss identisch mit Manage-ClaudeKeys.ps1 sein
# ============================================================
$AES_KEY = [byte[]](
    # TODO: Eigenen 32-Byte AES-256-Schluessel eintragen (identisch in Manage-ClaudeKeys.ps1!)
    # Erzeugen: [byte[]]::new(32) | ForEach-Object { Get-Random -Maximum 256 }
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

    # --- configLibrary-Dateien fuer Claude Desktop schreiben ---
    # Beide Pfade werden identisch beschrieben (LocalAppData + AppData/Roaming)
    $configId  = '00000000-0000-0000-0000-000000000000'
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false

    $meta = [ordered]@{
        appliedId = $configId
        entries   = @(
            [ordered]@{ id = $configId; name = 'Default' }
        )
    }
    $config = [ordered]@{
        disableDeploymentModeChooser = $true
        inferenceProvider            = 'gateway'
        inferenceGatewayBaseUrl      = $LiteLLMUrl
        inferenceGatewayApiKey       = $key
    }
    $metaJson   = $meta   | ConvertTo-Json -Depth 3
    $configJson = $config | ConvertTo-Json -Depth 2

    $libraryDirs = @(
        Join-Path $env:LOCALAPPDATA 'Claude-3p\configLibrary'
        Join-Path $env:APPDATA      'Claude-3p\configLibrary'
    )

    foreach ($libraryDir in $libraryDirs) {
        if (-not (Test-Path $libraryDir)) {
            New-Item -ItemType Directory -Path $libraryDir -Force | Out-Null
        }

        $metaPath   = Join-Path $libraryDir '_meta.json'
        $configPath = Join-Path $libraryDir "$configId.json"

        [System.IO.File]::WriteAllText($metaPath,   $metaJson,   $utf8NoBom)
        [System.IO.File]::WriteAllText($configPath, $configJson, $utf8NoBom)
        Write-Log "configLibrary geschrieben: $libraryDir"
    }

} catch {
    Write-Log "Fehler (catch): $_"
    exit 0
}
