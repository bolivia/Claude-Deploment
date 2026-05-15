#Requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ============================================================
# KONFIGURATION
# ============================================================
$AES_KEY = [byte[]](
    # TODO: Eigenen 32-Byte AES-256 Schluessel hier eintragen (identisch in Get-ClaudeKey.ps1!)
    0, 0, 0, 0,  0, 0, 0, 0,
    0, 0, 0, 0,  0, 0, 0, 0,
    0, 0, 0, 0,  0, 0, 0, 0,
    0, 0, 0, 0,  0, 0, 0, 0
)

$script:DefaultKeyFilePath = "\\fileserver\shares\Claude Deployment\claude_keys.dat"
$script:DeployTargetPath   = "\\dc01\NETLOGON\login-scripts\ClaudeDeployment\claude_keys.dat"
$script:LiteLLMUrl         = "https://litellm.ai.example-corp.de"
$script:LiteLLMMaster      = "sk-YOUR_MASTER_KEY_HERE"
$script:DefaultBudget      = 50.0
# ============================================================

# ---------- Design tokens ----------

$C = @{
    Primary      = [System.Drawing.Color]::FromArgb(0, 120, 212)
    PrimaryHov   = [System.Drawing.Color]::FromArgb(0, 102, 180)
    PrimaryPrs   = [System.Drawing.Color]::FromArgb(0, 84, 153)
    Danger       = [System.Drawing.Color]::FromArgb(196, 43, 28)
    DangerHov    = [System.Drawing.Color]::FromArgb(255, 240, 238)
    Header       = [System.Drawing.Color]::FromArgb(28, 28, 28)
    HeaderSub    = [System.Drawing.Color]::FromArgb(160, 160, 160)
    Surface      = [System.Drawing.Color]::FromArgb(243, 243, 243)
    White        = [System.Drawing.Color]::White
    Border       = [System.Drawing.Color]::FromArgb(218, 218, 218)
    GridHdr      = [System.Drawing.Color]::FromArgb(246, 246, 246)
    GridHdrText  = [System.Drawing.Color]::FromArgb(60, 60, 60)
    GridAlt      = [System.Drawing.Color]::FromArgb(251, 252, 255)
    GridSel      = [System.Drawing.Color]::FromArgb(0, 120, 212)
    GridSelTxt   = [System.Drawing.Color]::White
    Text         = [System.Drawing.Color]::FromArgb(28, 28, 28)
    SubText      = [System.Drawing.Color]::FromArgb(110, 110, 110)
    StatusBg     = [System.Drawing.Color]::FromArgb(237, 237, 237)
    StatusText   = [System.Drawing.Color]::FromArgb(80, 80, 80)
    Success      = [System.Drawing.Color]::FromArgb(16, 124, 16)
}

$F = @{
    UI    = New-Object System.Drawing.Font('Segoe UI', 9)
    Title = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    Sub   = New-Object System.Drawing.Font('Segoe UI', 8)
    Btn   = New-Object System.Drawing.Font('Segoe UI', 9)
    Grid  = New-Object System.Drawing.Font('Segoe UI', 9)
    Label = New-Object System.Drawing.Font('Segoe UI', 8.5)
}

# ---------- Button factory ----------

function New-Btn {
    param(
        [string]$Text,
        [int]$W = 110,
        [int]$H = 30,
        [ValidateSet('primary','neutral','danger','ghost')]
        [string]$Style = 'neutral'
    )
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $Text
    $b.Width     = $W
    $b.Height    = $H
    $b.Font      = $F.Btn
    $b.FlatStyle = 'Flat'
    $b.Cursor    = [System.Windows.Forms.Cursors]::Hand
    switch ($Style) {
        'primary' {
            $b.BackColor = $C.Primary
            $b.ForeColor = $C.White
            $b.FlatAppearance.BorderSize = 0
            $b.FlatAppearance.MouseOverBackColor = $C.PrimaryHov
            $b.FlatAppearance.MouseDownBackColor = $C.PrimaryPrs
        }
        'neutral' {
            $b.BackColor = $C.White
            $b.ForeColor = $C.Text
            $b.FlatAppearance.BorderSize = 1
            $b.FlatAppearance.BorderColor = $C.Border
            $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
            $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
        }
        'danger' {
            $b.BackColor = $C.White
            $b.ForeColor = $C.Danger
            $b.FlatAppearance.BorderSize = 1
            $b.FlatAppearance.BorderColor = $C.Danger
            $b.FlatAppearance.MouseOverBackColor = $C.DangerHov
            $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(255, 225, 220)
        }
        'ghost' {
            $b.BackColor = [System.Drawing.Color]::Transparent
            $b.ForeColor = $C.SubText
            $b.FlatAppearance.BorderSize = 0
            $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
        }
    }
    $b
}

function New-Sep {
    param([int]$H = 1, [string]$Dock = 'Top')
    $p = New-Object System.Windows.Forms.Panel
    $p.Height    = $H
    $p.Dock      = $Dock
    $p.BackColor = $C.Border
    $p
}

# ---------- Crypto ----------

function Encrypt-Key([string]$Plaintext) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key     = $AES_KEY
    $aes.Mode    = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.GenerateIV()
    $iv     = $aes.IV
    $enc    = $aes.CreateEncryptor()
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($Plaintext)
    $cipher = $enc.TransformFinalBlock($bytes, 0, $bytes.Length)
    $aes.Dispose()
    [Convert]::ToBase64String($iv + $cipher)
}

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

# ---------- Data ----------

$script:UserKeys    = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:CurrentFile = ''
$script:FilterText  = ''

function Load-File([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    try {
        $json = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:UserKeys.Clear()
        foreach ($u in $json.users) {
            $script:UserKeys.Add([PSCustomObject]@{
                UPN    = $u.upn
                Key    = Decrypt-Key $u.key
                Budget = [double]$u.budget
            })
        }
        $script:CurrentFile = $Path
        return $true
    } catch {
        Show-Err "Fehler beim Laden:`n$_"
        return $false
    }
}

function Save-File {
    if (-not $script:CurrentFile) {
        Show-Warn 'Keine Datei ausgewaehlt. Bitte zuerst Oeffnen oder Neue Datei.'
        return $false
    }
    try {
        $users = @($script:UserKeys | ForEach-Object {
            [PSCustomObject]@{ upn = $_.UPN; key = Encrypt-Key $_.Key; budget = $_.Budget }
        })
        [PSCustomObject]@{ version = 1; users = $users } |
            ConvertTo-Json -Depth 3 |
            Set-Content $script:CurrentFile -Encoding UTF8
        return $true
    } catch {
        Show-Err "Fehler beim Speichern:`n$_"
        return $false
    }
}

function Invoke-LiteLLM([string]$Endpoint, [hashtable]$Body) {
    $headers = @{ Authorization = "Bearer $($script:LiteLLMMaster)" }
    Invoke-RestMethod `
        -Uri         "$($script:LiteLLMUrl)$Endpoint" `
        -Method      POST `
        -Headers     $headers `
        -Body        ($Body | ConvertTo-Json) `
        -ContentType "application/json" `
        -ErrorAction Stop
}

function Show-Err([string]$Msg) {
    [System.Windows.Forms.MessageBox]::Show($Msg, 'Fehler',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error)
}

function Show-Warn([string]$Msg) {
    [System.Windows.Forms.MessageBox]::Show($Msg, 'Hinweis',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
}

function Parse-Budget([string]$Text) {
    $val = $script:DefaultBudget
    [double]::TryParse(
        $Text.Replace(',', '.'),
        [System.Globalization.NumberStyles]::Any,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$val) | Out-Null
    $val
}

function Refresh-Grid {
    $grid.Rows.Clear()
    $filter = $script:FilterText.ToLower()
    $n = 0
    foreach ($u in $script:UserKeys) {
        if ($filter -and -not $u.UPN.ToLower().Contains($filter)) { continue }
        $idx = $grid.Rows.Add($u.UPN, $u.Budget.ToString('F2') + ' $', '   ##################')
        $grid.Rows[$idx].Tag = $u
        $n++
    }
    $total = $script:UserKeys.Count
    $shown = if ($filter) { "$n von $total" } else { "$total" }
    $file  = if ($script:CurrentFile) { $script:CurrentFile } else { 'keine Datei geladen' }
    $status.Text = "  $shown Benutzer   |   $file"
}

function Update-Title {
    $suffix = if ($script:CurrentFile) { ' - ' + [System.IO.Path]::GetFileName($script:CurrentFile) } else { '' }
    $form.Text = "Claude LiteLLM Key Manager$suffix"
}

# ================================================================
# FORM
# ================================================================

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Claude LiteLLM Key Manager'
$form.Size            = New-Object System.Drawing.Size(820, 580)
$form.MinimumSize     = New-Object System.Drawing.Size(640, 420)
$form.StartPosition   = 'CenterScreen'
$form.BackColor       = $C.Surface
$form.Font            = $F.UI

# ── Header ──────────────────────────────────────────────────────
$header = New-Object System.Windows.Forms.Panel
$header.Dock      = 'Top'
$header.Height    = 64
$header.BackColor = $C.Header

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = 'Claude LiteLLM Key Manager'
$lblTitle.Font      = $F.Title
$lblTitle.ForeColor = $C.White
$lblTitle.AutoSize  = $true
$lblTitle.Location  = New-Object System.Drawing.Point(20, 12)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text      = $script:LiteLLMUrl
$lblSub.Font      = $F.Sub
$lblSub.ForeColor = $C.HeaderSub
$lblSub.AutoSize  = $true
$lblSub.Location  = New-Object System.Drawing.Point(22, 38)

$header.Controls.AddRange(@($lblTitle, $lblSub))

# ── File bar ────────────────────────────────────────────────────
$fileBar = New-Object System.Windows.Forms.Panel
$fileBar.Dock      = 'Top'
$fileBar.Height    = 48
$fileBar.BackColor = $C.White

$lblFileLbl = New-Object System.Windows.Forms.Label
$lblFileLbl.Text      = 'Datei'
$lblFileLbl.Font      = $F.Label
$lblFileLbl.ForeColor = $C.SubText
$lblFileLbl.AutoSize  = $true
$lblFileLbl.Location  = New-Object System.Drawing.Point(20, 8)

$txtFile = New-Object System.Windows.Forms.TextBox
$txtFile.Text      = $script:DefaultKeyFilePath
$txtFile.Font      = $F.UI
$txtFile.Location  = New-Object System.Drawing.Point(20, 24)
$txtFile.Width     = 500
$txtFile.BorderStyle = 'FixedSingle'
$txtFile.BackColor = $C.Surface

$btnOpen = New-Btn 'Oeffnen ...' -W 90 -Style neutral
$btnOpen.Location = New-Object System.Drawing.Point(528, 22)

$btnNewFile = New-Btn 'Neue Datei' -W 90 -Style neutral
$btnNewFile.Location = New-Object System.Drawing.Point(624, 22)

$fileBar.Controls.AddRange(@($lblFileLbl, $txtFile, $btnOpen, $btnNewFile))

$fileBar.Add_Resize({
    $txtFile.Width       = $fileBar.Width - 230
    $btnOpen.Location    = New-Object System.Drawing.Point(($fileBar.Width - 196), 22)
    $btnNewFile.Location = New-Object System.Drawing.Point(($fileBar.Width - 100), 22)
})

# ── Toolbar ─────────────────────────────────────────────────────
$toolbar = New-Object System.Windows.Forms.Panel
$toolbar.Dock      = 'Top'
$toolbar.Height    = 50
$toolbar.BackColor = $C.White

$btnAdd     = New-Btn '+ Hinzufuegen' -W 120 -Style primary
$btnAdd.Location = New-Object System.Drawing.Point(20, 10)

$btnBudget  = New-Btn 'Budget' -W 80 -Style neutral
$btnBudget.Location = New-Object System.Drawing.Point(148, 10)

$btnShowKey = New-Btn 'Key anzeigen' -W 105 -Style neutral
$btnShowKey.Location = New-Object System.Drawing.Point(234, 10)

$btnDelete  = New-Btn 'Loeschen' -W 85 -Style danger
$btnDelete.Location = New-Object System.Drawing.Point(345, 10)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Font        = $F.UI
$txtSearch.Width       = 200
$txtSearch.BorderStyle = 'FixedSingle'
$txtSearch.ForeColor   = $C.SubText
$txtSearch.Text        = 'Suche ...'
$txtSearch.Anchor      = 'Right'

$btnSave = New-Btn 'Speichern' -W 100 -Style primary
$btnSave.Anchor = 'Right'

$toolbar.Controls.AddRange(@($btnAdd, $btnBudget, $btnShowKey, $btnDelete, $txtSearch, $btnSave))

$toolbar.Add_Resize({
    $btnSave.Location    = New-Object System.Drawing.Point(($toolbar.Width - 110), 10)
    $txtSearch.Location  = New-Object System.Drawing.Point(($toolbar.Width - 320), 13)
})

# ── DataGridView ────────────────────────────────────────────────
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock                         = 'Fill'
$grid.ReadOnly                     = $true
$grid.AllowUserToAddRows           = $false
$grid.AllowUserToDeleteRows        = $false
$grid.SelectionMode                = 'FullRowSelect'
$grid.MultiSelect                  = $false
$grid.AutoSizeColumnsMode          = 'Fill'
$grid.RowHeadersVisible            = $false
$grid.EnableHeadersVisualStyles    = $false
$grid.BorderStyle                  = 'None'
$grid.CellBorderStyle              = 'SingleHorizontal'
$grid.GridColor                    = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grid.BackgroundColor              = $C.White
$grid.Font                         = $F.Grid
$grid.RowTemplate.Height           = 34

# Header style
$grid.ColumnHeadersDefaultCellStyle.BackColor   = $C.GridHdr
$grid.ColumnHeadersDefaultCellStyle.ForeColor   = $C.GridHdrText
$grid.ColumnHeadersDefaultCellStyle.Font        = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
$grid.ColumnHeadersDefaultCellStyle.Padding     = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
$grid.ColumnHeadersHeight                       = 32
$grid.ColumnHeadersHeightSizeMode               = 'DisableResizing'

# Row styles
$grid.DefaultCellStyle.BackColor              = $C.White
$grid.DefaultCellStyle.ForeColor              = $C.Text
$grid.DefaultCellStyle.SelectionBackColor     = $C.GridSel
$grid.DefaultCellStyle.SelectionForeColor     = $C.GridSelTxt
$grid.DefaultCellStyle.Padding                = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
$grid.AlternatingRowsDefaultCellStyle.BackColor = $C.GridAlt

# Columns
$colUPN = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colUPN.HeaderText = 'Benutzer (UPN)'
$colUPN.FillWeight = 55

$colBudget = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colBudget.HeaderText                          = 'Budget'
$colBudget.FillWeight                          = 15
$colBudget.DefaultCellStyle.Alignment         = 'MiddleRight'
$colBudget.DefaultCellStyle.Padding           = New-Object System.Windows.Forms.Padding(0, 0, 14, 0)
$colBudget.HeaderCell.Style.Alignment         = 'MiddleRight'
$colBudget.HeaderCell.Style.Padding           = New-Object System.Windows.Forms.Padding(0, 0, 14, 0)

$colKey = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colKey.HeaderText                         = 'API-Key'
$colKey.FillWeight                         = 30
$colKey.DefaultCellStyle.ForeColor        = [System.Drawing.Color]::FromArgb(140, 140, 140)
$colKey.DefaultCellStyle.Font             = New-Object System.Drawing.Font('Consolas', 8)

$grid.Columns.AddRange($colUPN, $colBudget, $colKey) | Out-Null

# ── Status bar ──────────────────────────────────────────────────
$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Dock      = 'Bottom'
$statusPanel.Height    = 28
$statusPanel.BackColor = $C.StatusBg

$status = New-Object System.Windows.Forms.Label
$status.Dock      = 'Fill'
$status.Font      = $F.Sub
$status.ForeColor = $C.StatusText
$status.TextAlign = 'MiddleLeft'
$status.Text      = '  Bereit'
$statusPanel.Controls.Add($status)

# ── Assemble form ───────────────────────────────────────────────
# Order matters for Dock: add Fill last
$form.Controls.Add($grid)
$form.Controls.Add($statusPanel)
$form.Controls.Add($(New-Sep))
$form.Controls.Add($toolbar)
$form.Controls.Add($(New-Sep))
$form.Controls.Add($fileBar)
$form.Controls.Add($(New-Sep))
$form.Controls.Add($header)

# ================================================================
# EVENTS
# ================================================================

# Search placeholder
$txtSearch.Add_GotFocus({
    if ($txtSearch.Text -eq 'Suche ...') {
        $txtSearch.Text      = ''
        $txtSearch.ForeColor = $C.Text
    }
})
$txtSearch.Add_LostFocus({
    if ($txtSearch.Text -eq '') {
        $txtSearch.Text      = 'Suche ...'
        $txtSearch.ForeColor = $C.SubText
    }
})
$txtSearch.Add_TextChanged({
    $script:FilterText = if ($txtSearch.Text -eq 'Suche ...') { '' } else { $txtSearch.Text }
    Refresh-Grid
})

$btnOpen.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter   = 'Key-Dateien (*.dat)|*.dat|Alle Dateien (*.*)|*.*'
    $dlg.FileName = $txtFile.Text
    if ($dlg.ShowDialog() -eq 'OK') {
        $txtFile.Text = $dlg.FileName
        if (Load-File $dlg.FileName) { Refresh-Grid; Update-Title }
    }
})

$btnNewFile.Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter   = 'Key-Dateien (*.dat)|*.dat'
    $dlg.FileName = 'claude_keys.dat'
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:UserKeys.Clear()
        $script:CurrentFile = $dlg.FileName
        $txtFile.Text = $dlg.FileName
        Save-File | Out-Null
        Refresh-Grid
        Update-Title
    }
})

# ---- Hinzufuegen ----
$btnAdd.Add_Click({
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Benutzer hinzufuegen'
    $dlg.Size            = New-Object System.Drawing.Size(420, 210)
    $dlg.StartPosition   = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.BackColor       = $C.White
    $dlg.Font            = $F.UI

    $l1 = New-Object System.Windows.Forms.Label
    $l1.Text = 'UPN (user@domain.com):'
    $l1.Font = $F.Label; $l1.ForeColor = $C.SubText
    $l1.Location = New-Object System.Drawing.Point(20, 18); $l1.AutoSize = $true

    $tUPN = New-Object System.Windows.Forms.TextBox
    $tUPN.Location = New-Object System.Drawing.Point(20, 36); $tUPN.Width = 370
    $tUPN.BorderStyle = 'FixedSingle'

    $l2 = New-Object System.Windows.Forms.Label
    $l2.Text = 'Budget (USD):'
    $l2.Font = $F.Label; $l2.ForeColor = $C.SubText
    $l2.Location = New-Object System.Drawing.Point(20, 70); $l2.AutoSize = $true

    $tBudget = New-Object System.Windows.Forms.TextBox
    $tBudget.Location = New-Object System.Drawing.Point(20, 88); $tBudget.Width = 130
    $tBudget.Text = $script:DefaultBudget.ToString('F2'); $tBudget.BorderStyle = 'FixedSingle'

    $bOK  = New-Btn 'Erstellen' -W 100 -Style primary
    $bOK.Location = New-Object System.Drawing.Point(210, 135); $bOK.DialogResult = 'OK'
    $dlg.AcceptButton = $bOK

    $bCnl = New-Btn 'Abbrechen' -W 100 -Style neutral
    $bCnl.Location = New-Object System.Drawing.Point(316, 135); $bCnl.DialogResult = 'Cancel'
    $dlg.CancelButton = $bCnl

    $dlg.Controls.AddRange(@($l1,$tUPN,$l2,$tBudget,$bOK,$bCnl))
    if ($dlg.ShowDialog($form) -ne 'OK') { return }

    $upn = $tUPN.Text.Trim()
    if (-not $upn) { Show-Warn 'UPN darf nicht leer sein.'; return }
    if ($script:UserKeys | Where-Object { $_.UPN -ieq $upn }) {
        Show-Warn "UPN '$upn' ist bereits vorhanden."; return
    }
    $budget = Parse-Budget $tBudget.Text

    try {
        $resp   = Invoke-LiteLLM '/key/generate' @{
            user_id = $upn; key_alias = "ClaudeDeployTool_$upn"; max_budget = $budget
        }
        $newKey = $resp.key
    } catch { Show-Err "LiteLLM API-Fehler:`n$_"; return }

    $script:UserKeys.Add([PSCustomObject]@{ UPN = $upn; Key = $newKey; Budget = $budget })
    if (Save-File) {
        Refresh-Grid
        [System.Windows.Forms.MessageBox]::Show(
            "Key erstellt fuer $upn`n`n$newKey`n`nBudget: $($budget.ToString('F2')) USD",
            'Erfolgreich',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})

# ---- Budget anpassen ----
$btnBudget.Add_Click({
    if ($grid.SelectedRows.Count -eq 0) { Show-Warn 'Bitte zuerst einen Benutzer auswaehlen.'; return }
    $sel = $grid.SelectedRows[0].Tag
    if (-not $sel) { return }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Budget anpassen'
    $dlg.Size            = New-Object System.Drawing.Size(360, 175)
    $dlg.StartPosition   = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $C.White; $dlg.Font = $F.UI

    $l1 = New-Object System.Windows.Forms.Label
    $l1.Text = $sel.UPN; $l1.Font = $F.Label; $l1.ForeColor = $C.SubText
    $l1.Location = New-Object System.Drawing.Point(20, 18); $l1.AutoSize = $true

    $l2 = New-Object System.Windows.Forms.Label
    $l2.Text = 'Neues Budget (USD):'; $l2.Font = $F.Label; $l2.ForeColor = $C.SubText
    $l2.Location = New-Object System.Drawing.Point(20, 50); $l2.AutoSize = $true

    $tBudget = New-Object System.Windows.Forms.TextBox
    $tBudget.Location = New-Object System.Drawing.Point(20, 68); $tBudget.Width = 130
    $tBudget.Text = $sel.Budget.ToString('F2'); $tBudget.BorderStyle = 'FixedSingle'

    $bOK  = New-Btn 'Aktualisieren' -W 110 -Style primary
    $bOK.Location = New-Object System.Drawing.Point(140, 108); $bOK.DialogResult = 'OK'
    $dlg.AcceptButton = $bOK

    $bCnl = New-Btn 'Abbrechen' -W 95 -Style neutral
    $bCnl.Location = New-Object System.Drawing.Point(255, 108); $bCnl.DialogResult = 'Cancel'
    $dlg.CancelButton = $bCnl

    $dlg.Controls.AddRange(@($l1,$l2,$tBudget,$bOK,$bCnl))
    if ($dlg.ShowDialog($form) -ne 'OK') { return }

    $newBudget = Parse-Budget $tBudget.Text
    try {
        Invoke-LiteLLM '/key/update' @{ key = $sel.Key; max_budget = $newBudget } | Out-Null
    } catch { Show-Err "LiteLLM API-Fehler:`n$_"; return }

    $sel.Budget = $newBudget
    if (Save-File) { Refresh-Grid }
})

# ---- Key anzeigen ----
$btnShowKey.Add_Click({
    if ($grid.SelectedRows.Count -eq 0) { Show-Warn 'Bitte zuerst einen Benutzer auswaehlen.'; return }
    $sel = $grid.SelectedRows[0].Tag
    if (-not $sel) { return }
    [System.Windows.Forms.MessageBox]::Show(
        "UPN:    $($sel.UPN)`nBudget: $($sel.Budget.ToString('F2')) USD`n`nAPI-Key:`n$($sel.Key)",
        'Key anzeigen',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::None)
})

# ---- Loeschen ----
$btnDelete.Add_Click({
    if ($grid.SelectedRows.Count -eq 0) { Show-Warn 'Bitte zuerst einen Benutzer auswaehlen.'; return }
    $sel = $grid.SelectedRows[0].Tag
    if (-not $sel) { return }

    $r = [System.Windows.Forms.MessageBox]::Show(
        "Benutzer und Key loeschen?`n`n$($sel.UPN)`n`nDer Key wird auch aus LiteLLM entfernt.",
        'Loeschen bestaetigen',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($r -ne 'Yes') { return }

    try {
        Invoke-LiteLLM '/key/delete' @{ keys = @($sel.Key) } | Out-Null
    } catch {
        $r2 = [System.Windows.Forms.MessageBox]::Show(
            "LiteLLM API-Fehler:`n$_`n`nTrotzdem lokal entfernen?",
            'API-Fehler',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r2 -ne 'Yes') { return }
    }

    $script:UserKeys.Remove($sel) | Out-Null
    if (Save-File) { Refresh-Grid }
})

# ---- Speichern ----
$btnSave.Add_Click({
    if (Save-File) {
        $status.Text = '  Gespeichert.'
        $script:_saveTimer = New-Object System.Windows.Forms.Timer
        $script:_saveTimer.Interval = 2500
        $script:_saveTimer.Add_Tick({ Refresh-Grid; $script:_saveTimer.Stop(); $script:_saveTimer.Dispose() })
        $script:_saveTimer.Start()
    }
})

$grid.Add_KeyDown({
    if ($_.KeyCode -eq 'Delete') { $btnDelete.PerformClick() }
})

# ── Closing reminder ────────────────────────────────────────────
$form.Add_FormClosing({
    if (-not $script:CurrentFile) { return }

    $src = $script:CurrentFile
    $dst = $script:DeployTargetPath

    $msg  = "Bitte nicht vergessen:`n`n"
    $msg += "Geaenderte Datei manuell ins Netlogon kopieren!`n`n"
    $msg += "Von:`n  $src`n`n"
    $msg += "Nach:`n  $dst"

    [System.Windows.Forms.MessageBox]::Show(
        $msg,
        'Datei ins Netlogon kopieren!',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
})

# ── Init ────────────────────────────────────────────────────────
if (Test-Path $txtFile.Text) {
    if (Load-File $txtFile.Text) { Refresh-Grid; Update-Title }
} else {
    $status.Text = '  Keine Datei geladen.'
}

[System.Windows.Forms.Application]::Run($form)
