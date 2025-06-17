Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ========== CONFIGURATION ==========
$pvwaURL      = "https://pvwa.cybermark.lab"
$username     = "monitoring-user"
$authType     = "CyberArk"

# CCP Config
$ccpIP        = "ccp.cybermark.lab"
$appID        = "MonitoringApp"
$ccpSafe      = "PrivilegedAccounts"
$ccpObject    = "monitoring-user"

# ========== FORM SETUP ==========
$form = New-Object Windows.Forms.Form
$form.Text = "CyberArk Usage Log Viewer"
$form.Size = New-Object Drawing.Size(500, 420)
$form.StartPosition = "CenterScreen"

$labelStart = New-Object Windows.Forms.Label
$labelStart.Text = "Start Date:"
$labelStart.Location = New-Object Drawing.Point(20,20)
$form.Controls.Add($labelStart)

$dateStart = New-Object Windows.Forms.DateTimePicker
$dateStart.Location = New-Object Drawing.Point(100, 18)
$dateStart.Width = 350
$form.Controls.Add($dateStart)

$labelEnd = New-Object Windows.Forms.Label
$labelEnd.Text = "End Date:"
$labelEnd.Location = New-Object Drawing.Point(20,60)
$form.Controls.Add($labelEnd)

$dateEnd = New-Object Windows.Forms.DateTimePicker
$dateEnd.Location = New-Object Drawing.Point(100, 58)
$dateEnd.Width = 350
$form.Controls.Add($dateEnd)

$chkCCP = New-Object Windows.Forms.CheckBox
$chkCCP.Text = "Use CCP"
$chkCCP.Location = New-Object Drawing.Point(20, 100)
$chkCCP.Checked = $true
$form.Controls.Add($chkCCP)

$lblPassword = New-Object Windows.Forms.Label
$lblPassword.Text = "Password:"
$lblPassword.Location = New-Object Drawing.Point(20,140)
$form.Controls.Add($lblPassword)

$txtPassword = New-Object Windows.Forms.TextBox
$txtPassword.UseSystemPasswordChar = $true
$txtPassword.Location = New-Object Drawing.Point(100,138)
$txtPassword.Width = 350
$form.Controls.Add($txtPassword)

$btnRun = New-Object Windows.Forms.Button
$btnRun.Text = "Run Query"
$btnRun.Width = 100
$btnRun.Location = New-Object Drawing.Point(180, 180)
$form.Controls.Add($btnRun)

$statusLabel = New-Object Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.Location = New-Object Drawing.Point(20, 220)
$statusLabel.Size = New-Object Drawing.Size(450, 100)
$form.Controls.Add($statusLabel)

# ========== BUTTON LOGIC ==========
$btnRun.Add_Click({
    $form.Cursor = 'WaitCursor'
    $startDate = $dateStart.Value.ToString("yyyy-MM-dd")
    $endDate = $dateEnd.Value.ToString("yyyy-MM-dd")
    $password = $null

    try {
        if ($chkCCP.Checked) {
            $statusLabel.Text = "Retrieving password from CCP..."
            $ccpResponse = Invoke-RestMethod -Method GET `
                -Uri "https://$ccpIP/AIMWebService/api/Accounts?AppID=$appID&Safe=$ccpSafe&Object=$ccpObject" `
                -Headers @{ "Content-Type" = "application/json" }
            $password = $ccpResponse.Content
        } else {
            if (-not $txtPassword.Text) {
                [System.Windows.Forms.MessageBox]::Show("Please enter a password.", "Error", "OK", "Error")
                return
            }
            $password = $txtPassword.Text
        }

        $statusLabel.Text = "Authenticating..."
        $body = @{ username = $username; password = $password } | ConvertTo-Json
        $token = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Auth/$authType/Logon" `
            -Method POST -Body $body -ContentType "application/json"
        $headers = @{ Authorization = $token }

        $statusLabel.Text = "Retrieving logs..."
        $uri = "$pvwaURL/PasswordVault/API/Audits?startDate=$startDate&endDate=$endDate&search=Logon"
        $audits = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET

        $filtered = $audits.value | Where-Object {
            $_.Action -eq "Logon" -and $_.User -like "a*" -and $_.TargetUser -like "b*"
        }

        if ($filtered.Count -eq 0) {
            $statusLabel.Text = "No privileged account usage logs found."
        } else {
            $csvPath = "$PSScriptRoot\CyberArk_UsageLogs_GUI_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
            $filtered |
                Select-Object Date, User, TargetUser, Action, Safe, System, TicketingID |
                Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
            $statusLabel.Text = "Logs exported to:`n$csvPath"
        }

        Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Auth/Logoff" -Headers $headers -Method POST | Out-Null
    } catch {
        $statusLabel.Text = "❌ Error: $($_.Exception.Message)"
    }

    $form.Cursor = 'Default'
})

# ========== SHOW FORM ==========
[void]$form.ShowDialog()
