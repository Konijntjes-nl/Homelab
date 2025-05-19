# Monitor-CyberArkSessions.ps1
# Assumes valid token already retrieved or invoke alongside Monitor-CyberArkAPI.ps1
$response = Invoke-RestMethod -Uri "$PVWAURL/API/LiveSessions" -Headers @{ Authorization = $token } -Method GET

$psmSessions = $response.LiveSessions | Where-Object {
    ($_.ConnectionComponentID -as [string]).Trim().ToUpper() -like "PSM*"
}

$sessionCount = $psmSessions.Count
$groupedByProvider = $psmSessions | Group-Object { $_.RawProperties.ProviderID } | Sort-Object Count -Descending

$result = [PSCustomObject]@{
    TotalSessions = $sessionCount
    SessionsByProvider = $groupedByProvider | Select-Object Name, Count
}

$result | ConvertTo-Json -Depth 5 | Out-File "$env:USERPROFILE\Desktop\SessionMonitor.json" -Force
