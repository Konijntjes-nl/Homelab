<#
.SYNOPSIS
    CyberArk Non-Compliant Account Manager (with CCP Support)

.DESCRIPTION
    Uses CyberArk's CCP to fetch API credentials securely. Connects to the vault,
    selects a Safe by name, finds non-compliant (unmanaged) accounts, resumes CPM,
    resets passwords, and logs actions.

.VERSION
    1.1.0

.AUTHOR
    YourNameHere
#>

param (
    [switch]$DebugMode
)

# ================
# === Settings ===
# ================
$ScriptVersion = "1.1.0"
$LogPath = ".\CyberArkActionLog.txt"
$CCPUrl = "https://ccp.example.local/AIMWebService/api/Accounts"
$AppID = "cyberark-api-app"         # The AppID assigned in CCP
$SafeNameForAPIUser = "APISafe"     # The Safe where the API user is stored
$APIUserAccountName = "api_user"    # The name of the CyberArk API user account

# ====================
# === Debug Helper ===
# ====================
function Write-DebugLog {
    param([string]$Message)
    if ($DebugMode) {
        Write-Host "[DEBUG] $Message" -ForegroundColor Yellow
    }
}

# =====================
# === CCP Credential ===
# =====================
Write-Host "CyberArk Non-Compliant Account Manager v$ScriptVersion" -ForegroundColor Cyan
Write-Host "`nFetching API user credentials from CCP..." -ForegroundColor Cyan

$ccpQuery = @{
    AppID      = $AppID
    Safe       = $SafeNameForAPIUser
    Object     = $APIUserAccountName
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$CCPUrl" -Method POST -Body $ccpQuery -ContentType "application/json"
    $Username = $response.UserName
    $Password = $response.Content
    Write-DebugLog "Fetched API credentials for user: $Username"
} catch {
    Write-Error "Failed to fetch API credentials from CCP: $_"
    exit 1
}

# =================
# === Vault Login ===
# =================
$CyberArkBaseUrl = Read-Host "Enter CyberArk Base URL (e.g. https://cyberark.local/PasswordVault)"

Write-Host "`nAuthenticating with CyberArk Vault..." -ForegroundColor Cyan
$loginBody = @{ username = $Username; password = $Password } | ConvertTo-Json

try {
    $loginResponse = Invoke-RestMethod -Uri "$CyberArkBaseUrl/PasswordVault/API/Auth/CyberArk/Logon" `
        -Method POST -Body $loginBody -ContentType "application/json"
    $SessionToken = $loginResponse
    $headers = @{ Authorization = $SessionToken }
    Write-DebugLog "Authentication successful. Session token: $SessionToken"
} catch {
    Write-Error "Vault authentication failed: $_"
    exit 1
}

# ======================
# === List Safes =======
# ======================
try {
    Write-Host "`nFetching list of safes..." -ForegroundColor Cyan
    $safesResponse = Invoke-RestMethod -Uri "$CyberArkBaseUrl/PasswordVault/api/Safes" -Headers $headers
    $safeNames = $safesResponse.value.name
    $safeNames | ForEach-Object { Write-Host "- $_" }
} catch {
    Write-Error "Failed to fetch safes: $_"
    exit 1
}

# Safe Selection
$safeChoice = Read-Host "Enter the name of the CyberArk Safe to use"
if ($safeNames -notcontains $safeChoice) {
    Write-Host "Safe '$safeChoice' not found. Exiting." -ForegroundColor Red
    exit
}

# ======================
# === Find Accounts ====
# ======================
Write-Host "`nGetting accounts from safe '$safeChoice'..." -ForegroundColor Cyan

try {
    $accounts = Invoke-RestMethod -Uri "$CyberArkBaseUrl/PasswordVault/api/Accounts?Safe=$safeChoice" -Headers $headers
    $nonCompliant = $accounts.value | Where-Object { $_.secretManagement.Unmanaged -eq $true }
} catch {
    Write-Error "Failed to retrieve accounts: $_"
    exit 1
}

if (-not $nonCompliant) {
    Write-Host "No non-compliant accounts found." -ForegroundColor Yellow
    exit
}

Write-Host "`nFound $($nonCompliant.Count) non-compliant accounts." -ForegroundColor Green

# =========================
# === Resume + Reset =====
# =========================
foreach ($account in $nonCompliant) {
    $accountId = $account.id
    $accountName = $account.name

    Write-DebugLog "Processing account ID: $accountId Name: $accountName"

    try {
        # Resume CPM
        Invoke-RestMethod -Uri "$CyberArkBaseUrl/PasswordVault/api/Accounts/$accountId/EnableAutomaticManagement" `
            -Method POST -Headers $headers
        "[$(Get-Date)] Resumed CPM for: $accountName" | Out-File -Append $LogPath

        # Reset password
        Invoke-RestMethod -Uri "$CyberArkBaseUrl/PasswordVault/api/Accounts/$accountId/ChangeCredentials" `
            -Method POST -Headers $headers
        "[$(Get-Date)] Password reset for: $accountName" | Out-File -Append $LogPath

        Write-Host "Processed account: $accountName" -ForegroundColor Cyan
    } catch {
        Write-Warning "[$(Get-Date)] Error on ${accountName}: $_"
        "[$(Get-Date)] ERROR for ${accountName}: $_" | Out-File -Append $LogPath

    }
}

# ================
# === Logoff ====
# ================
try {
    Invoke-RestMethod -Uri "$CyberArkBaseUrl/PasswordVault/API/Auth/Logoff" -Method POST -Headers $headers
    Write-Host "`nLogged off successfully." -ForegroundColor Green
} catch {
    Write-Warning "Could not log off: $_"
}

Write-Host "`nDone. Actions logged in: $LogPath" -ForegroundColor Cyan
