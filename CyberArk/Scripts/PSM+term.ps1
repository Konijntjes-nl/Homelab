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
        @{Name='AccountUsername'; Expression={ $_.AccountUsername }},
        @{Name='AccountAddress'; Expression={ $_.AccountAddress }},
        @{Name='RemoteMachine'; Expression={ $_.RemoteMachine }},
        @{Name='FromIP'; Expression={ $_.FromIP }},
        @{Name='SessionID'; Expression={ $_.SessionID }},
        @{Name='StartTimeReadable'; Expression={ $_.StartTimeReadable }},
        @{Name='ConnectionComponentID'; Expression={ $_.ConnectionComponentID }},
        @{Name='ProviderID'; Expression={ $_.RawProperties.ProviderID }}    

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
# ===== OPTIONAL: TERMINATE SESSIONS =====
$terminableSessions = $psmSessions | Where-Object { $_.CanTerminate -eq $true }

if ($terminableSessions.Count -gt 0) {
    Write-Host "`n⚠️  You can terminate the following sessions:`n"
    $terminableSessions | Select-Object SessionID, User, RemoteMachine, StartTimeReadable | Format-Table -AutoSize

    $response = Read-Host "`nDo you want to terminate a session? (y/n)"
    if ($response -match '^(y|yes)$') {
        $toTerminate = Read-Host "Enter SessionID to terminate (e.g., 29_138)"
        $target = $terminableSessions | Where-Object { $_.SessionID -eq $toTerminate }

        if ($target) {
            try {
                Invoke-RestMethod `
                    -Uri "$PVWAURL/API/LiveSessions/$($target.SessionID)/Terminate" `
                    -Method POST `
                    -Headers $headers

                Write-Host "✅ Session $($target.SessionID) terminated successfully."
            } catch {
                Write-Error "❌ Failed to terminate session: $_"
            }
        } else {
            Write-Warning "⚠️ No matching session with that ID or session not terminable."
        }
    }
} else {
    Write-Host "`nℹ️ No sessions currently support termination."
}
# ===== LOG OFF =====
try {
    Invoke-RestMethod -Uri "$PVWAURL/API/Auth/Logoff" -Headers $headers -Method POST
    Write-Host "`n[+] Logged off from CyberArk."
} catch {
    Write-Warning "⚠️ Failed to log off cleanly."
}