<#
CyberArk RemoteMachines Single-Account Editor
- Fetches account by name
- Extracts current remoteMachines to .txt file
- Allows review and update
- Adds preview, commenting, and version control
#>

# ========== CONFIGURATION ==========
$pvwaURL    = "<PVWA URL>"				    # e.g., https://pvwa.cybermark.lab
$username   = "<USERNAME>"				    # Admin or monitoring user
$authType   = "<Auth>"					    # CyberArk / LDAP / RADIUS

# ========== CCP Configuration ==========
$ccpIP      = "<CCP URL>"       			# FQDN or IP of CCP
$appID      = "<APPID>"                    	# Application ID for CCP
$safe       = "<SAFE>"                    	# Safe name
$object     = "<USERNAME>"       			# Username used to query CCP
$useCCP     = $true                         # Set to $false for manual password

# ========== INPUT ==========
$targetAccountName = Read-Host "Enter CyberArk Username to search"

# ===== TLS & Output Setup =====
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"

# ===== GET PASSWORD =====
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

# ===== LOGIN & GET TOKEN =====
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

# ===== ACCOUNT LOOKUP =====
$searchResult = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Accounts?search=$targetAccountName" `
    -Headers $headers -Method GET

if ($searchResult.value.Count -gt 1) {
    Write-Host "`nMultiple accounts found for '$targetAccountName':" -ForegroundColor Yellow
    $searchResult.value | Select-Object id, name, userName, platformId, address | Format-Table -AutoSize
    $selectedId = Read-Host "Enter the ID of the correct account"
    $account = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Accounts/$selectedId/" -Headers $headers -Method GET
} elseif ($searchResult.value.Count -eq 1) {
    $account = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Accounts/$($searchResult.value[0].id)/" `
        -Headers $headers -Method GET
} else {
    Write-Error "❌ No account found matching '$targetAccountName'."
    exit 1
}

# ===== EXPORT remoteMachines TO FILE =====
$remoteRaw = $account.remoteMachinesAccess.remoteMachines
$outputFile = "remoteMachines_$($account.id).txt"

if ($remoteRaw) {
    $remoteMachines = $remoteRaw -split ',' | ForEach-Object { $_.Trim() }
    $remoteMachines | Set-Content -Path $outputFile
    Write-Host "📄 remoteMachines exported to '$outputFile'" -ForegroundColor Cyan
} else {
    Write-Host "ℹ️ No remoteMachines set on this account. Creating blank file." -ForegroundColor Yellow
    "" | Out-File $outputFile
}

# ===== PROMPT TO APPLY UPDATE =====
$confirm = Read-Host "Do you want to PATCH the account with remoteMachines from '$outputFile'? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "❌ Operation canceled." -ForegroundColor Yellow
    exit 0
}

# ===== LOAD NEW remoteMachines FROM FILE =====
if (-Not (Test-Path $outputFile)) {
    Write-Error "❌ File '$outputFile' not found."
    exit 1
}
$newRemoteMachines = Get-Content $outputFile | Where-Object { $_.Trim() -ne "" }

if (-Not $newRemoteMachines) {
    Write-Warning "⚠️ File is empty. No changes to apply."
    exit 1
}

# ===== PREVIEW CHANGES =====
Write-Host "`n🧪 Preview changes to be applied:" -ForegroundColor Cyan
Write-Host "Account: $($account.userName)"
Write-Host "Old remoteMachines: $remoteRaw"
Write-Host "New remoteMachines: $($newRemoteMachines -join ', ')"

# ===== VERSION CONTROL: BACKUP BEFORE PATCH =====
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupCSV = "remoteMachines_backup_$($account.id)_$timestamp.csv"
[PSCustomObject]@{
    AccountID      = $account.id
    Safe           = $account.safeName
    Username       = $account.userName
    Address        = $account.address
    Platform       = $account.platformId
    RemoteMachines = $remoteRaw
} | Export-Csv -Path $backupCSV -NoTypeInformation
Write-Host "💾 Backup saved: $backupCSV" -ForegroundColor Gray

# ===== APPLY PATCH =====
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
        -Uri "$pvwaURL/PasswordVault/API/Accounts/$($account.id)/" `
        -Headers $headers -Body $patchBody -ContentType "application/json"
    Write-Host "✅ remoteMachines updated successfully." -ForegroundColor Green
} catch {
    Write-Error "❌ PATCH failed: $_"
}

# ===== LOGOFF =====
try {
    Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Auth/Logoff" -Headers $headers -Method POST | Out-Null
    Write-Host "🔒 Logged off from CyberArk." -ForegroundColor Gray
} catch {
    Write-Warning "⚠️ Failed to log off cleanly."
}
