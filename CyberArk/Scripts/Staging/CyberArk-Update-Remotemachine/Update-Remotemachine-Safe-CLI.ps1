<#
CyberArk Bulk RemoteMachines Updater
- Extracts remoteMachines from one account
- Saves to `remoteMachines_bulk.txt`
- Allows previewing and confirming before applying changes
- Logs each change to a timestamped backup file
#>

# ========== CONFIGURATION ==========
$pvwaURL    = "<PVWA URL>"				    # e.g., https://pvwa.cybermark.lab
$username   = "<USERNAME>"				    # Admin or monitoring user
$authType   = "<Auth>"					    # CyberArk / LDAP / RADIUS

# ========== CCP Configuration ==========
$ccpIP      = "<CCP URL>"       			# FQDN or IP of CCP
$appID      = "<APPID>"                    	# Application ID for CCP
$object     = "<USERNAME>"       			# CCP credential lookup
$useCCP     = $true                         # Set to $false to use manual password

# ========== INPUT ==========
$safe       = Read-Host "Enter Safe Name"   # Prompt for safe to operate on

# ===== TLS & Error Handling =====
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"

# ===== GET PASSWORD FROM CCP OR MANUAL =====
if ($useCCP) {
    try {
        $ccpResponse = Invoke-RestMethod -Method GET `
            -Uri "https://$ccpIP/AIMWebService/api/Accounts?AppID=$appID&Safe=$safe&Query=Username=$object" `
            -Headers @{ "Content-Type" = "application/json" }
        $password = $ccpResponse.Content
        Write-Host "🔐 Password retrieved from CCP."
    } catch {
        Write-Error "❌ Failed to retrieve password from CCP: $_"
        exit 1
    }
} else {
    Write-Host "🔐 CCP disabled. Please enter your password:" -ForegroundColor Yellow
    $securePass = Read-Host -AsSecureString
    $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
    )
}

# ===== LOGIN TO CYBERARK =====
$body = @{ username = $username; password = $password } | ConvertTo-Json
try {
    $token = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Auth/$authType/Logon" `
        -Method POST -Body $body -ContentType "application/json"
    Write-Host "✅ Authenticated successfully." -ForegroundColor Green
} catch {
    Write-Error "❌ Authentication failed: $_"
    exit 1
}
$headers = @{ Authorization = $token }

# ===== GET ALL ACCOUNTS IN SAFE =====
try {
    $allAccounts = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Accounts?filter=safeName eq '$safe'" `
        -Headers $headers -Method GET
} catch {
    Write-Error "❌ Failed to retrieve accounts from safe '$safe': $_"
    exit 1
}

if (-not $allAccounts.value) {
    Write-Host "ℹ️ No accounts found in safe '$safe'" -ForegroundColor Yellow
    exit 0
}

# ===== EXPORT EXISTING remoteMachines TO TXT FILE =====
$outputFile = "remoteMachines_bulk.txt"
$firstAccountId = $allAccounts.value[0].id
try {
    $firstAccount = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Accounts/$firstAccountId/" `
        -Headers $headers -Method GET
    $remoteRaw = $firstAccount.remoteMachinesAccess.remoteMachines
    if ($remoteRaw) {
        $remoteMachines = $remoteRaw -split ',' | ForEach-Object { $_.Trim() }
        $remoteMachines | Set-Content -Path $outputFile
        Write-Host "📄 Existing remoteMachines exported to '$outputFile'" -ForegroundColor Cyan
    } else {
        Write-Host "ℹ️ No remoteMachines found in first account. Blank file created." -ForegroundColor Yellow
        "" | Out-File $outputFile
    }
} catch {
    Write-Warning "⚠️ Could not extract remoteMachines from first account: $_"
    "" | Out-File $outputFile
}

# ===== READ PATCH DATA FROM TXT FILE =====
if (-not (Test-Path $outputFile)) {
    Write-Error "❌ File '$outputFile' does not exist."
    exit 1
}

$newRemoteMachines = Get-Content -Path $outputFile | Where-Object { $_.Trim() -ne "" }
if (-not $newRemoteMachines) {
    Write-Warning "⚠️ File is empty. Nothing to apply."
    exit 1
}

# ===== PREVIEW MODE =====
Write-Host "`n🧪 Preview: These remoteMachines will be applied to all accounts in safe '$safe':" -ForegroundColor Cyan
$newRemoteMachines | ForEach-Object { Write-Host "  • $_" }
Write-Host "`n📦 Affected accounts:" -ForegroundColor Cyan
$allAccounts.value | Select-Object id, userName, address, platformId | Format-Table -AutoSize

$proceed = Read-Host "`nContinue with PATCH for all these accounts? (yes/no)"
if ($proceed -ne "yes") {
    Write-Host "❌ Aborted by user." -ForegroundColor Yellow
    exit 0
}

# ===== VERSION CONTROL: BACKUP OLD remoteMachines =====
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFile = "remoteMachines_backup_$($safe)_$timestamp.csv"
$backupData = @()

foreach ($basic in $allAccounts.value) {
    try {
        $account = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Accounts/$($basic.id)/" `
            -Headers $headers -Method GET
        $backupData += [PSCustomObject]@{
            AccountID      = $basic.id
            Safe           = $basic.safeName
            Username       = $basic.userName
            Address        = $basic.address
            Platform       = $basic.platformId
            RemoteMachines = $account.remoteMachinesAccess.remoteMachines
        }
    } catch {
        Write-Warning "⚠️ Failed to get current remoteMachines for $($basic.id)"
    }
}

$backupData | Export-Csv -Path $backupFile -NoTypeInformation
Write-Host "📁 Backup saved: $backupFile" -ForegroundColor Gray

# ===== APPLY PATCH TO ALL ACCOUNTS =====
foreach ($basic in $allAccounts.value) {
    $patchBody = @(
        @{
            op = "replace"
            path = "/remoteMachinesAccess/remoteMachines"
            value = $newRemoteMachines
        },
        @{
            op = "replace"
            path = "/remoteMachinesAccess/accessRestrictedToRemoteMachines"
            value = $false
        }
    ) | ConvertTo-Json -Depth 5

    try {
        Invoke-RestMethod -Method PATCH `
            -Uri "$pvwaURL/PasswordVault/API/Accounts/$($basic.id)/" `
            -Headers $headers -Body $patchBody -ContentType "application/json"
        Write-Host "✅ Patched [$($basic.userName)] successfully." -ForegroundColor Green
    } catch {
        Write-Warning "❌ Failed to PATCH [$($basic.userName)]: $_"
    }
}

# ===== LOGOFF =====
try {
    Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Auth/Logoff" -Headers $headers -Method POST | Out-Null
    Write-Host "🔒 Logged off from CyberArk." -ForegroundColor Gray
} catch {
    Write-Warning "⚠️ Failed to log off cleanly."
}
