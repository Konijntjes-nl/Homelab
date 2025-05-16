# Define your CyberArk PVWA details
$PVWAURL = "https://pvwa.cybermark.lab/PasswordVault"
$Username = "admin2"
$Password = "LVxY7IQxlVLvtc8GzZ26EChqok1Ttxg3"  # Use secure method in production!
$AuthType = "CyberArk"  # Or LDAP, Radius, etc.

# Login to get token
$body = @{
    username = $Username
    password = $Password
    concurrentSession = "true"
} | ConvertTo-Json

$tokenResponse = Invoke-RestMethod -Uri "$PVWAURL/API/Auth/$AuthType/Logon" -Method POST -Body $body -ContentType "application/json"
$token = $tokenResponse

# Add token to header
$headers = @{
    Authorization = $token
}

# Get list of active sessions
$sessions = Invoke-RestMethod -Uri "$PVWAURL/API/LiveSessions" -Headers $headers -Method GET

# Filter for HTML5GW sessions
$html5Sessions = $sessions.LiveSessions | Where-Object { $_.ConnectionComponentType -eq "PSM" }

# Output results
$html5Sessions | Select-Object UserName, Address, PlatformID, StartTime, ConnectionComponentType | Format-Table -AutoSize

# Logoff to invalidate token
Invoke-RestMethod -Uri "$PVWAURL/API/Auth/Logoff" -Headers $headers -Method POST