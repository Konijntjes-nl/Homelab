<#
=======================================
  CyberArk Live Session Monitor Script
  Author       : Mark Lam
  Created      : 2025-05-15
  Description  : Lists active PSM sessions, retrieves password from CCP, and exports to JSON.

  Revision History:
  ---------------------------------------------------------------------------------
  Date        | Author    | Description
  ------------|-----------|--------------------------------------------------------
  2025-05-15  | Mark Lam  | Initial version using CCP for credentials + JSON export
  ------------|-----------|--------------------------------------------------------
  2025-05-15  | Mark Lam  | Added seperate stats json for monitoring. 
  ------------|-----------|--------------------------------------------------------
  2025-05-19  | Mark Lam  | Added maxsessions and PSM sesions to *
  ------------|-----------|--------------------------------------------------------
  2025-05-19  | Mark Lam  | Fixed CCP intergration
  ------------|-----------|--------------------------------------------------------
  ------------|-----------|--------------------------------------------------------
  ------------|-----------|--------------------------------------------------------
  ------------|-----------|--------------------------------------------------------
=======================================
#>
# ===== CONFIGURATION =====
$pvwaurl        = "<pvwa-url>"                              # CCP address (FQDN or IP)
$username       = "<privileged-account>"                    # Username of the privileged account
$authtype       = "CyberArk"                                # Authentication type
$exportjsonpath = "$PSScriptRoot\logs\live-sessions\Active-PSM-Sessions.json"         # All sessions Json 
$statsjsonpath  = "$PSScriptRoot\logs\live-sessions\PSM-Session-Stats.json"           # Monitoring Json
$logfile        = "$PSScriptRoot\logs\live-sessions\API_Response_Log.json"            # Debug log file API
$maxsessions    = 100                                       # Max number of recieved sessions default =25
$debugmode      = $false                                    # 🔧 Set to $true to enable debug output

# ===== GET PASSWORD FROM CCP =====
$ccpIP   = "<ccp-url>"                                      # CCP address (FQDN or IP)
$appID   = "<application-id>"                               # Application ID
$safe    = "<safe-name>"                                    # Safe in which the privileged account is stored
$object  = "<privileged-account>"                           # username of the privileged account

# Use TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Try to get password from CCP
try {
    $ccpResponse = Invoke-RestMethod -Method GET `
        -Uri "https://$ccpIP/AIMWebService/api/Accounts?AppID=$appID&Safe=$safe&Query=username=$object" `
        -Headers @{ "Content-Type" = "application/json" }
    $password = $ccpResponse.Content
    Write-Host "🔐 Password retrieved securely from CCP."
} catch {
    Write-Error "❌ Failed to retrieve password from CCP: $_"
    exit 1
}

# ===== LOGIN & GET TOKEN =====
$body = @{
    username          = $username
    password          = $password
    concurrentSession = $true
} | ConvertTo-Json

try {
    $token = Invoke-RestMethod `
        -Uri "$pvwaurl/API/Auth/$authtype/Logon" `
        -Method POST `
        -Body $body `
        -ContentType "application/json"
    Write-Host "✅ Authenticated successfully."
} catch {
    Write-Error "❌ Authentication failed: $_"
    exit 1
}

$headers = @{ Authorization = $token }

# ===== GET LIVE SESSIONS =====
try {
    $response = Invoke-RestMethod `
        -Uri "$pvwaurl/API/LiveSessions?limit=$maxsessions" `
        -Headers $headers `
        -Method GET

    $sessions = $response.LiveSessions

    $componentStats = $sessions |
        Group-Object { ($_.RawProperties.ProviderID -as [string]).Trim() } |
        Sort-Object Count -Descending |
        Select-Object @{Name='ProviderID'; Expression={ $_.Name }}, Count

    if ($debugmode) {
        $response | ConvertTo-Json -Depth 10 | Out-File $logfile
        Write-Host "📁 API response logged to: $logfile"
        Write-Host "`n📊 Total sessions returned by API: $($sessions.Count)"

        Write-Host "`n🔎 Sorted ProviderID values:`n"
        $componentStats | Format-Table -AutoSize
    }
} catch {
    Write-Error "❌ Failed to retrieve live sessions: $_"
    Invoke-RestMethod -Uri "$pvwaurl/API/Auth/Logoff" -Headers $headers -Method POST
    exit 1
}

# ===== FILTER FOR PSM SESSIONS =====

$psmSessions = $sessions | Where-Object {
    ($_.ConnectionComponentID -as [string]).Trim().ToUpper() -like "*"
}

Write-Host "`n🎯 Active PSM-RDP Sessions Found: $($psmSessions.Count)`n"

# ===== Add readable time =====
$psmSessions | ForEach-Object {
    $_ | Add-Member -NotePropertyName "StartTimeReadable" -NotePropertyValue ([DateTimeOffset]::FromUnixTimeSeconds($_.Start).ToLocalTime()) -Force
}

# ===== DISPLAY & EXPORT RESULTS =====
$output = $psmSessions | Select-Object `
    @{Name='User'; Expression={ $_.User }},
    @{Name='PAM-account'; Expression={ $_.Accountusername }},
    @{Name='Domain/local'; Expression={ $_.AccountAddress }},
    @{Name='TargetMachine'; Expression={ $_.RemoteMachine }},
    @{Name='FromIP'; Expression={ $_.FromIP }},
    @{Name='SessionID'; Expression={ $_.SessionID }},
    @{Name='StartTimeReadable'; Expression={ $_.StartTimeReadable }},
    @{Name='ConnectionComponentID'; Expression={ $_.ConnectionComponentID }},
    @{Name='ProviderID'; Expression={ $_.RawProperties.ProviderID }}

# Display to console
if ($output.Count -gt 0) {
    $output | Format-Table -AutoSize
} else {
    Write-Host "⚠️ No active PSM-RDP sessions found."
}

# Export session data to JSON
try {
    $exportObject = [PSCustomObject]@{
        Timestamp = (Get-Date).ToString("s")
        SessionCount = $output.Count
        Sessions = $output
    }
    $exportObject | ConvertTo-Json -Depth 5 | Out-File -FilePath $exportjsonpath -Encoding UTF8
    Write-Host "`n📁 Exported session data to: $exportjsonpath"
} catch {
    Write-Warning "⚠️ Failed to export session JSON: $_"
}

# Export component statistics to separate JSON
try {
    $componentStatsExport = [PSCustomObject]@{
        Timestamp = (Get-Date).ToString("s")
        TotalSessions = $sessions.Count
        ProviderStats = $componentStats
    }
    $componentStatsExport | ConvertTo-Json -Depth 5 | Out-File -FilePath $statsjsonpath -Encoding UTF8
    Write-Host "📁 Exported Provider stats to: $statsjsonpath"
} catch {
    Write-Warning "⚠️ Failed to export component stats JSON: $_"
}

# ===== LOG OFF =====
try {
    Invoke-RestMethod -Uri "$pvwaurl/API/Auth/Logoff" -Headers $headers -Method POST
    Write-Host "`n[+] Logged off from CyberArk."
} catch {
    Write-Warning "⚠️ Failed to log off cleanly."
}