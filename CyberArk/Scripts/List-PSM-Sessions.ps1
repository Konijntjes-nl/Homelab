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
=======================================
#>
# ===== CONFIGURATION =====
$PVWAURL       = "https://pvwa.cybermark.lab/PasswordVault"
$Username      = "apilive"
$Password      = "LVxY7IQxlVLvtc8GzZ26EChqok1Ttxg3"
$AuthType       = "CyberArk" 
$ExportJsonPath = ".\logs\Active-PSM-Sessions.json"
$StatsJsonPath  = ".\logs\PSM-Session-Stats.json"
$LogFile        = ".\logs\API_Response_Log.json"
$DebugMode      = $false  # 🔧 Set to $true to enable debug output

# ===== GET PASSWORD FROM CCP =====
<# 
$CCPUrl         = "<insert-url>"
$AppID          = "<insert-appid>"
$Safe           = "<insert-safe>"
$Object         = "<insert-account>"

try {
    $ccpResponse = Invoke-RestMethod `
        -Uri "$CCPUrl?AppID=$AppID&Safe=$Safe&Object=$Object" `
        -Method GET `
        -UseBasicParsing

    $Password = $ccpResponse.Content
    Write-Host "🔐 Password retrieved securely from CCP."
} catch {
    Write-Error "❌ Failed to retrieve password from CCP: $_"
    exit 1
}

 #># ===== LOGIN & GET TOKEN =====
$body = @{
    username          = $Username
    password          = $Password
    concurrentSession = $true
} | ConvertTo-Json

try {
    $token = Invoke-RestMethod `
        -Uri "$PVWAURL/API/Auth/$AuthType/Logon" `
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
        -Uri "$PVWAURL/API/LiveSessions" `
        -Headers $headers `
        -Method GET

    $sessions = $response.LiveSessions

    $componentStats = $sessions |
        Group-Object { ($_.RawProperties.ProviderID -as [string]).Trim() } |
        Sort-Object Count -Descending |
        Select-Object @{Name='ProviderID'; Expression={ $_.Name }}, Count

    if ($DebugMode) {
        $response | ConvertTo-Json -Depth 10 | Out-File $LogFile
        Write-Host "📁 API response logged to: $LogFile"
        Write-Host "`n📊 Total sessions returned by API: $($sessions.Count)"

        Write-Host "`n🔎 Sorted ProviderID values:`n"
        $componentStats | Format-Table -AutoSize
    }
} catch {
    Write-Error "❌ Failed to retrieve live sessions: $_"
    Invoke-RestMethod -Uri "$PVWAURL/API/Auth/Logoff" -Headers $headers -Method POST
    exit 1
}

# ===== FILTER FOR PSM SESSIONS =====

$psmSessions = $sessions | Where-Object {
    ($_.ConnectionComponentID -as [string]).Trim().ToUpper() -like "PSM*"
}

Write-Host "`n🎯 Active PSM-RDP Sessions Found: $($psmSessions.Count)`n"

# ===== Add readable time =====
$psmSessions | ForEach-Object {
    $_ | Add-Member -NotePropertyName "StartTimeReadable" -NotePropertyValue ([DateTimeOffset]::FromUnixTimeSeconds($_.Start).ToLocalTime()) -Force
}

# ===== DISPLAY & EXPORT RESULTS =====
$output = $psmSessions | Select-Object `
    @{Name='User'; Expression={ $_.User }},
    @{Name='PAM-account'; Expression={ $_.AccountUsername }},
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
    $exportObject | ConvertTo-Json -Depth 5 | Out-File -FilePath $ExportJsonPath -Encoding UTF8
    Write-Host "`n📁 Exported session data to: $ExportJsonPath"
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
    $componentStatsExport | ConvertTo-Json -Depth 5 | Out-File -FilePath $StatsJsonPath -Encoding UTF8
    Write-Host "📁 Exported Provider stats to: $StatsJsonPath"
} catch {
    Write-Warning "⚠️ Failed to export component stats JSON: $_"
}

# ===== LOG OFF =====
try {
    Invoke-RestMethod -Uri "$PVWAURL/API/Auth/Logoff" -Headers $headers -Method POST
    Write-Host "`n[+] Logged off from CyberArk."
} catch {
    Write-Warning "⚠️ Failed to log off cleanly."
}