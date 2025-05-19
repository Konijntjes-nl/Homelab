# Export-CyberArkMetrics.ps1
$files = @("VaultStatus.json", "PVWAHealth.json", "SessionMonitor.json")
$combined = @()

foreach ($file in $files) {
    $data = Get-Content -Raw -Path "$env:USERPROFILE\Desktop\$file" | ConvertFrom-Json
    $combined += $data
}

$combined | ConvertTo-Json -Depth 10 | Out-File "$env:USERPROFILE\Desktop\CyberArkMetrics.json" -Force
