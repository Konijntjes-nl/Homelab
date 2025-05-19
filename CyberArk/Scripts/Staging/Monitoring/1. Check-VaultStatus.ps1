# Check-VaultStatus.ps1
$VaultService = "PrivateArk Server"
$VaultLogFile = "C:\CyberArk\Vault\Logs\Vault.log"
$DiskThreshold = 90
$Result = @{}

# Check Service Status
$service = Get-Service -Name $VaultService -ErrorAction SilentlyContinue
$Result.ServiceStatus = if ($service.Status -eq "Running") { "Up" } else { "Down" }

# Disk Usage
$drive = Get-PSDrive -Name C
$Result.DiskUsagePercent = [math]::Round(($drive.Used / $drive.Size) * 100, 2)

# Last Backup Timestamp
$backupPath = "C:\CyberArk\Backup"
$lastBackup = Get-ChildItem -Path $backupPath -Recurse -Include *.zip,*.bak | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Result.LastBackupTime = $lastBackup.LastWriteTime

# Export Result
$Result | ConvertTo-Json | Out-File -FilePath "$env:USERPROFILE\Desktop\VaultStatus.json" -Force
