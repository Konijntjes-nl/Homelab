# ===== CONFIGURATION =====
$PVWAURL       = "https://pvwa.cybermark.lab/PasswordVault"
$Username      = "apilive"
$Password      = "LVxY7IQxlVLvtc8GzZ26EChqok1Ttxg3"
$AuthType      = "CyberArk"
$ExportCsvPath = "$env:USERPROFILE\Desktop\Active-PSM-Sessions.csv"
$LogFile       = "$env:USERPROFILE\Desktop\API_Response_Log.json"
$DebugMode     = $false  # 🔧 Set to $true to enable debug output

# ===== LOGIN & GET TOKEN =====
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

    if ($DebugMode) {
        $response | ConvertTo-Json -Depth 10 | Out-File $LogFile
        Write-Host "📁 API response logged to: $LogFile"
        Write-Host "`n📊 Total sessions returned by API: $($response.LiveSessions.Count)"

        Write-Host "`n🔎 Distinct ConnectionComponentID values:`n"
        $response.LiveSessions | Group-Object { ($_.ConnectionComponentID -as [string]).Trim() } |
            Select-Object Name, Count | Format-Table -AutoSize
    }

    $sessions = $response.LiveSessions
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
if ($psmSessions.Count -gt 0) {
    $output = $psmSessions | Select-Object `
        @{Name='User'; Expression={ $_.User }},
        @{Name='PAM-account'; Expression={ $_.AccountUsername }},
        @{Name='Domain/local'; Expression={ $_.AccountAddress }},
        @{Name='TargetMachine'; Expression={ $_.RemoteMachine }},
        @{Name='FromIP'; Expression={ $_.FromIP }},
        @{Name='SessionID'; Expression={ $_.SessionID }},
        @{Name='StartTimeReadable'; Expression={ $_.StartTimeReadable }},
        @{Name='ConnectionComponentID'; Expression={ $_.ConnectionComponentID }},
        @{Name='PSM-Server'; Expression={ $_.RawProperties.ProviderID }}    

    # Display to console
    $output | Format-Table -AutoSize

    # Export to CSV
    try {
        $output | Export-Csv -Path $ExportCsvPath -NoTypeInformation -Force
        Write-Host "`n📁 Exported session list to: $ExportCsvPath"
    } catch {
        Write-Warning "⚠️ Failed to export CSV: $_"
    }
} else {
    Write-Host "⚠️ No active PSM-RDP sessions found."
}
# ===== LOG OFF =====
try {
    Invoke-RestMethod -Uri "$PVWAURL/API/Auth/Logoff" -Headers $headers -Method POST
    Write-Host "`n[+] Logged off from CyberArk."
} catch {
    Write-Warning "⚠️ Failed to log off cleanly."
}