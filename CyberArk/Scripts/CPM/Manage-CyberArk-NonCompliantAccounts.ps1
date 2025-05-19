<#
=======================================
  CyberArk Non-Compliant Account Manager
  Author       : Mark Lam
  Version      : 1.3.1
  Description  : Finds and fixes non-compliant accounts in CyberArk by resuming CPM and resetting credentials.

  Revision History:
  ---------------------------------------------------------------------------------
  Date        | Author    | Description
  ------------|-----------|--------------------------------------------------------
  2025-05-18  | Mark Lam  | Added v10 ID resolution + debugging
=======================================
#>
param (
    [switch]$DebugMode,
    [ValidateSet("CyberArk","LDAP")]
    [string]$AuthMethod = "CyberArk"   # Default: internal auth
)

# =============== CONFIGURATION ===============
$ScriptVersion   = "1.3.1"
$LogPath         = ".\CyberArkActionLog.txt"
$CyberArkBaseUrl = "https://pvwa.cybermark.lab/PasswordVault"
$APIUser         = "administrator"  # CyberArk account with API access
$PlainPassword   = "Cyberark1"

# =============== DEBUG LOGGING ===============
function Write-DebugLog {
    param([string]$Message)
    if ($DebugMode) {
        Write-Host "[DEBUG] $Message" -ForegroundColor Yellow
    }
}

Write-Host "CyberArk Non-Compliant Account Manager v$ScriptVersion" -ForegroundColor Cyan
Write-Host "Authentication method: $AuthMethod" -ForegroundColor Cyan

# =============== LOGIN ========================
$loginUrl = if ($AuthMethod -eq "LDAP") {
    "$CyberArkBaseUrl/API/Auth/LDAP/Logon"
} else {
    "$CyberArkBaseUrl/API/Auth/CyberArk/Logon"
}
Write-DebugLog "Login URL: $loginUrl"

$loginBody = @{ username = $APIUser; password = $PlainPassword } | ConvertTo-Json

Write-Host "`nAuthenticating with CyberArk Vault..." -ForegroundColor Cyan
try {
    $loginResponse = Invoke-RestMethod -Uri $loginUrl -Method POST -Body $loginBody -ContentType "application/json"
    $SessionToken  = $loginResponse
    $headers       = @{ Authorization = $SessionToken }
    Write-DebugLog "Authentication successful. Session token: $SessionToken"
} catch {
    Write-Error "Vault authentication failed: $_"
    exit 1
}

# =============== GET SAFES ====================
try {
    Write-Host "`nFetching list of safes..." -ForegroundColor Cyan
    $safesResponse = Invoke-RestMethod -Uri "$CyberArkBaseUrl/api/Safes" -Headers $headers
    $safeNames = $safesResponse.value | ForEach-Object {
        if ($_.name) { $_.name } elseif ($_.SafeName) { $_.SafeName } else { "Unknown Safe" }
    }
    $safeNames | ForEach-Object { Write-Host "- $_" }
} catch {
    Write-Error "Failed to fetch safes: $_"
    exit 1
}

$safeChoice = Read-Host "Enter the name of the CyberArk Safe to use"
if ($safeNames -notcontains $safeChoice) {
    Write-Host "Safe '$safeChoice' not found. Exiting." -ForegroundColor Red
    exit
}

# =============== GET ACCOUNTS =================
Write-Host "`nGetting accounts from safe '$safeChoice'..." -ForegroundColor Cyan
try {
    $accounts = Invoke-RestMethod -Uri "$CyberArkBaseUrl/api/Accounts?Safe=$safeChoice" -Headers $headers
    Write-DebugLog "Sample account data:`n$( $accounts.value[0] | ConvertTo-Json -Depth 10 )"
    $nonCompliant = $accounts.value | Where-Object { $_.secretManagement.status -eq "failure" }
} catch {
    Write-Error "Failed to retrieve accounts: $_"
    exit 1
}

if (-not $nonCompliant) {
    Write-Host "No non-compliant accounts found." -ForegroundColor Yellow
    exit
}

Write-Host "`nFound $($nonCompliant.Count) non-compliant account(s)." -ForegroundColor Green

# =============== PROCESS ACCOUNTS =============
foreach ($account in $nonCompliant) {
    $shortId     = $account.id
    $accountName = $account.name
    Write-DebugLog "Processing account ID: $shortId Name: $accountName"

    try {
        # v10 ID Resolution
        $searchUrl = "$CyberArkBaseUrl/api/v10/accounts?search=$shortId"
        Write-DebugLog "GET $searchUrl"
        $searchResponse = Invoke-RestMethod -Uri $searchUrl -Headers $headers

        $accountDetail = $searchResponse.value | Where-Object { $_.name -eq $accountName }

        if (-not $accountDetail) {
            throw "No matching v10 account found for $accountName"
        }

        $accountIdV10 = $accountDetail.id
        Write-DebugLog "Resolved v10 AccountID: $accountIdV10"

        # Resume CPM
        $enableCpmUrl = "$CyberArkBaseUrl/api/Accounts/$accountIdV10/EnableAutomaticManagement"
        Write-DebugLog "POST $enableCpmUrl"
        Invoke-RestMethod -Uri $enableCpmUrl -Method POST -Headers $headers
        "[$(Get-Date)] Resumed CPM for: ${accountName}" | Out-File -Append $LogPath

        # Reset password
        $resetUrl = "$CyberArkBaseUrl/api/Accounts/$accountIdV10/ChangeCredentials"
        Write-DebugLog "POST $resetUrl"
        Invoke-RestMethod -Uri $resetUrl -Method POST -Headers $headers
        "[$(Get-Date)] Password reset for: ${accountName}" | Out-File -Append $LogPath

        Write-Host "Processed account: $accountName" -ForegroundColor Cyan
    } catch {
        $errMsg = $_.Exception.Message
        Write-Warning "[$(Get-Date)] Error on ${accountName}: $errMsg"
        Write-DebugLog "Response body: $($_.ErrorDetails?.Message)"
        "[$(Get-Date)] ERROR for ${accountName}: $errMsg" | Out-File -Append $LogPath
    }
}

# =============== LOGOFF =======================
try {
    Invoke-RestMethod -Uri "$CyberArkBaseUrl/API/Auth/Logoff" -Method POST -Headers $headers
    Write-Host "`nLogged off successfully." -ForegroundColor Green
} catch {
    Write-Warning "Could not log off: $_"
}

Write-Host "`nDone. Actions logged in: $LogPath" -ForegroundColor Cyan
