# Parameters
$pvwaURL  = "https://pvwa.cybermark.lab"
$username = "monitoring-user"
$authType = "CyberArk"
$useCCP   = $true

$ccpIP    = "ccp.cybermark.lab"
$appID    = "PVWA_App"
$safe     = "CyberArk-Safes"
$object   = "monitoring-user"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"

function Get-Password {
    if ($useCCP) {
        try {
            Write-Host "Retrieving password from CCP..."
            $ccpResponse = Invoke-RestMethod -Method GET `
                -Uri "https://$ccpIP/AIMWebService/api/Accounts?AppID=$appID&Safe=$safe&Query=Username=$object" `
                -Headers @{ "Content-Type" = "application/json" }
            return $ccpResponse.Content
        } catch {
            Write-Error "Failed to retrieve password from CCP: $_"
            exit 1
        }
    } else {
        Write-Host "Please enter your password:" -ForegroundColor Yellow
        $securePass = Read-Host -AsSecureString
        return [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
        )
    }
}

function Read-Input {
    param([string]$Prompt, [bool]$AllowEmpty=$false)
    do {
        $input = Read-Host $Prompt
        if ($AllowEmpty -or $input.Trim() -ne '') { return $input.Trim() }
    } while ($true)
}

# Get inputs
$accountName = Read-Input "Enter Account Name to search"
$startDateStr = Read-Input "Enter Start Date (yyyy-MM-dd), leave empty for 30 days ago" $true
$endDateStr = Read-Input "Enter End Date (yyyy-MM-dd), leave empty for today" $true
$actionFilter = Read-Input "Enter Action filter (PSM Connect, Password Access, Window Title) or 'All'" $true

if ([string]::IsNullOrEmpty($startDateStr)) {
    $startDate = (Get-Date).AddDays(-30).Date
} else {
    $startDate = [DateTime]::ParseExact($startDateStr, 'yyyy-MM-dd', $null)
}
if ([string]::IsNullOrEmpty($endDateStr)) {
    $endDate = (Get-Date).Date.AddDays(1).AddSeconds(-1)
} else {
    $endDate = [DateTime]::ParseExact($endDateStr, 'yyyy-MM-dd', $null).AddDays(1).AddSeconds(-1)
}
if ([string]::IsNullOrEmpty($actionFilter)) { $actionFilter = 'All' }

$password = Get-Password

try {
    Write-Host "Logging in to PVWA..."
    $body = @{ username = $username; password = $password } | ConvertTo-Json
    $token = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Auth/$authType/Logon" -Method POST -Body $body -ContentType "application/json"
    $headers = @{ Authorization = $token }

    Write-Host "Searching for account '$accountName'..."
    $searchResult = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Accounts?search=$accountName" -Headers $headers -Method GET
    if ($searchResult.value.Count -eq 0) {
        Write-Warning "No accounts found matching '$accountName'."
        exit
    }
    $account = $searchResult.value[0]
    Write-Host "Found account: $($account.Name) (ID: $($account.id))"

    Write-Host "Retrieving activities..."
    $activitiesRaw = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Accounts/$($account.id)/Activities" -Headers $headers -Method GET

    $filteredActivities = $activitiesRaw.Activities | Where-Object {
        $date = [DateTimeOffset]::FromUnixTimeSeconds($_.Date).DateTime
        ($date -ge $startDate) -and ($date -le $endDate) -and
        ($actionFilter -eq 'All' -or $_.Action -eq $actionFilter)
    }

    if ($filteredActivities.Count -eq 0) {
        Write-Host "No activities found for the specified criteria."
        exit
    }

    # Output results to console
    $filteredActivities | ForEach-Object {
        $date = [DateTimeOffset]::FromUnixTimeSeconds($_.Date).DateTime
        Write-Host ("{0} | {1,-20} | {2}" -f $date.ToString("yyyy-MM-dd HH:mm:ss"), $_.User, $_.Action)
    }

    # Export CSV prompt
    $exportCsv = Read-Input "Export results to CSV? (Y/N)" 
    if ($exportCsv -match '^[Yy]') {
        $filePath = Read-Input "Enter output CSV file path"
        $filteredActivities | Select-Object @{n='Time';e={[DateTimeOffset]::FromUnixTimeSeconds($_.Date).DateTime}}, User, Action |
            Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8
        Write-Host "Results exported to $filePath"
    }

} catch {
    Write-Error "Error: $_"
} finally {
    if ($headers) {
        try { Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Auth/Logoff" -Headers $headers -Method POST | Out-Null } catch {}
    }
}
