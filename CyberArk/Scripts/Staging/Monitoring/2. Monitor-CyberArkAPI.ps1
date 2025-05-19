# Monitor-CyberArkAPI.ps1
$PVWAURL = "https://pvwa.company.local"
$Username = "<username>"
$Password = "<password>"  # Suggest using CredentialManager or CCP in prod
$AuthType = "CyberArk"

$body = @{ username = $Username; password = $Password; concurrentSession = $true } | ConvertTo-Json
try {
    $token = Invoke-RestMethod -Uri "$PVWAURL/API/Auth/$AuthType/Logon" -Method POST -Body $body -ContentType "application/json"
    Write-Output "✅ API Login Successful"
    $healthCheck = Invoke-RestMethod -Uri "$PVWAURL/API/HealthCheck" -Headers @{Authorization = $token}
    $healthCheck | ConvertTo-Json | Out-File -FilePath "$env:USERPROFILE\Desktop\PVWAHealth.json" -Force
} catch {
    Write-Error "❌ API Login Failed or PVWA down"
}
