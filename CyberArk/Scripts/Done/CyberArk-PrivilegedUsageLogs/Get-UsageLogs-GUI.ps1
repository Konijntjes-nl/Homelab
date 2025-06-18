Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==== CONFIGURATION ====
$pvwaURL      = "https://pvwa.cybermark.lab"
$username     = "monitoring-user"
$authType     = "CyberArk"
$useCCP       = $true

$ccpIP        = "ccp.cybermark.lab"
$appID        = "PVWA_App"
$safe         = "CyberArk-Safes"
$object       = "monitoring-user"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"

function Get-Password {
    if ($useCCP) {
        try {
            $ccpResponse = Invoke-RestMethod -Method GET `
                -Uri "https://$ccpIP/AIMWebService/api/Accounts?AppID=$appID&Safe=$safe&Query=Username=$object" `
                -Headers @{ "Content-Type" = "application/json" }
            $Password = $ccpResponse.Content
            Write-Host "🔐 Password retrieved securely from CCP."
            return $Password
        } catch {
            Write-Error "❌ Failed to retrieve password from CCP: $_"
            exit 1
        }
    } else {
        Write-Host "🔐 CCP disabled. Please enter your password:" -ForegroundColor Yellow
        $securePass = Read-Host -AsSecureString
        $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
        )
        return $password
    }
}

# ==== GUI Setup ====
$form = New-Object System.Windows.Forms.Form
$form.Text = "CyberArk Account Activity Viewer"
$form.Size = New-Object System.Drawing.Size(600,480)
$form.StartPosition = "CenterScreen"

# Account Label & Textbox
$lblAccount = New-Object System.Windows.Forms.Label
$lblAccount.Text = "Account Name:"
$lblAccount.Location = New-Object System.Drawing.Point(10,20)
$lblAccount.AutoSize = $true
$form.Controls.Add($lblAccount)

$txtAccount = New-Object System.Windows.Forms.TextBox
$txtAccount.Location = New-Object System.Drawing.Point(110,18)
$txtAccount.Size = New-Object System.Drawing.Size(150,20)
$form.Controls.Add($txtAccount)

# Start Date Label & DateTimePicker
$lblStartDate = New-Object System.Windows.Forms.Label
$lblStartDate.Text = "Start Date:"
$lblStartDate.Location = New-Object System.Drawing.Point(10,50)
$lblStartDate.AutoSize = $true
$form.Controls.Add($lblStartDate)

$dtpStart = New-Object System.Windows.Forms.DateTimePicker
$dtpStart.Format = [System.Windows.Forms.DateTimePickerFormat]::Short
$dtpStart.Location = New-Object System.Drawing.Point(110,48)
$form.Controls.Add($dtpStart)

# End Date Label & DateTimePicker
$lblEndDate = New-Object System.Windows.Forms.Label
$lblEndDate.Text = "End Date:"
$lblEndDate.Location = New-Object System.Drawing.Point(10,80)
$lblEndDate.AutoSize = $true
$form.Controls.Add($lblEndDate)

$dtpEnd = New-Object System.Windows.Forms.DateTimePicker
$dtpEnd.Format = [System.Windows.Forms.DateTimePickerFormat]::Short
$dtpEnd.Location = New-Object System.Drawing.Point(110,78)
$form.Controls.Add($dtpEnd)

# Action Filter Label & ComboBox
$lblAction = New-Object System.Windows.Forms.Label
$lblAction.Text = "Filter Action:"
$lblAction.Location = New-Object System.Drawing.Point(10,110)
$lblAction.AutoSize = $true
$form.Controls.Add($lblAction)

$ddlAction = New-Object System.Windows.Forms.ComboBox
$ddlAction.Location = New-Object System.Drawing.Point(110,108)
$ddlAction.Size = New-Object System.Drawing.Size(150, 20)
$ddlAction.DropDownStyle = 'DropDownList'
$ddlAction.Items.AddRange(@("All", "PSM Connect", "Password Access", "Window Title"))
$ddlAction.SelectedIndex = 0
$form.Controls.Add($ddlAction)

# Button to get activities
$btnGet = New-Object System.Windows.Forms.Button
$btnGet.Text = "Get Activities"
$btnGet.Location = New-Object System.Drawing.Point(280,108)
$form.Controls.Add($btnGet)

# ListView for results (only Time, User, Action)
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(10,140)
$listView.Size = New-Object System.Drawing.Size(560,260)
$listView.View = 'Details'
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.Columns.Add("Time", 180)
$listView.Columns.Add("User", 180)
$listView.Columns.Add("Action", 180)
$form.Controls.Add($listView)

# Status Label
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(10,410)
$lblStatus.Size = New-Object System.Drawing.Size(560,30)
$form.Controls.Add($lblStatus)

$btnGet.Add_Click({
    $listView.Items.Clear()
    $lblStatus.Text = "Authenticating..."

    $password = Get-Password
    if (-not $password) {
        $lblStatus.Text = "Password input cancelled or failed."
        return
    }

    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

    Start-Job -ScriptBlock {
        param ($pvwaURL, $authType, $username, $password, $accountName, $startDate, $endDate, $actionFilter)

        $ErrorActionPreference = "Stop"
        $body = @{ username = $username; password = $password } | ConvertTo-Json
        $headers = $null
        $result = @{}

        try {
            $token = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Auth/$authType/Logon" `
                -Method POST -Body $body -ContentType "application/json"
            $headers = @{ Authorization = $token }

            $searchResult = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Accounts?search=$accountName" `
                -Headers $headers -Method GET
            if ($searchResult.value.Count -eq 0) {
                $result.Status = "No account found."
                return $result
            }
            $account = $searchResult.value[0]

            $activitiesRaw = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Accounts/$($account.id)/Activities" `
                -Headers $headers -Method GET

            $filtered = $activitiesRaw.Activities | Where-Object {
                $date = [DateTimeOffset]::FromUnixTimeSeconds($_.Date).DateTime
                ($date -ge $startDate) -and ($date -le $endDate) -and
                ($actionFilter -eq 'All' -or $_.Action -eq $actionFilter)
            }

            $result.Status = "Success"
            $result.Data = $filtered
            return $result
        } catch {
            $result.Status = "Error: $_"
            return $result
        } finally {
            if ($headers) {
                try {
                    Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Auth/Logoff" -Headers $headers -Method POST | Out-Null
                } catch {}
            }
        }
    } -ArgumentList $pvwaURL, $authType, $username, $password, $txtAccount.Text, $dtpStart.Value.Date, $dtpEnd.Value.Date.AddDays(1).AddSeconds(-1), $ddlAction.SelectedItem |
    Wait-Job | Receive-Job | ForEach-Object {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default

        if ($_.Status -eq "Success") {
            $listView.Items.Clear()
            if ($_.Data.Count -eq 0) {
                $lblStatus.Text = "No matching activities found."
                return
            }

            foreach ($act in $_.Data) {
                $date = [DateTimeOffset]::FromUnixTimeSeconds($act.Date).DateTime
                $item = New-Object System.Windows.Forms.ListViewItem($date.ToString("yyyy-MM-dd HH:mm:ss"))
                $item.SubItems.Add($act.User) | Out-Null
                $item.SubItems.Add($act.Action) | Out-Null
                $listView.Items.Add($item) | Out-Null
            }
            $lblStatus.Text = "Displayed $($_.Data.Count) activities."
        } else {
            $lblStatus.Text = $_.Status
        }
    }
})

[void] $form.ShowDialog()
