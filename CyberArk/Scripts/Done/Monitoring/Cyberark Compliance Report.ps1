<#
=======================================
CyberArk Compliance Report Script
Author       : Mark Lam 
Created      : 2025-05-20
Description  : Retrieves CyberArk account information via REST API, 
               evaluates accounts for compliance based on password 
               management and rotation status, and exports a report 
               of non-compliant accounts with detailed reasons.
=======================================
  Revision History:
  ---------------------------------------------------------------------------------
  Date        | Author    | Description
  ------------|-----------|--------------------------------------------------------
  2025-05-20  | Mark Lam  | Initial version with REST API integration, CCP support, 
                            compliance checks, and CSV export
  ------------|-----------|--------------------------------------------------------
=======================================
#>
# ===== CONFIGURATION =====
# PVWA Settings 
$pvwaurl        = "<pvwa-url>"                              # CCP address (FQDN or IP)
$username       = "<privileged-account>"                    # Username of the privileged account
$authtype       = "CyberArk"                                # Authentication type
# CCP Settings
$ccpIP          = "<ccp-url>"                       # CCP server
$appID          = "<application-id>"                # CCP AppID
$safe           = "<safe-name>"                     # Safe name
$object         = "<privileged-account>"            # Object name
$useCCP         = $false                             # Set false to enter password manually
# Password age Settings
$passwordAgeThreshold = 90                                          # Days before password considered outdated
# Log path Settings
$exportCsvPath       = "$PSScriptRoot\logs\compliance\NonCompliantAccounts.csv"     # CSV export path

# ===== TLS Setup =====
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ===== GET PASSWORD =====
if ($useCCP) {
    try {
        Write-Host "🔐 Retrieving password securely from CCP..." -ForegroundColor Cyan
        $ccpResponse = Invoke-RestMethod -Method GET `
            -Uri "https://$ccpIP/AIMWebService/api/Accounts?AppID=$appID&Safe=$safe&Object=$object" `
            -Headers @{ "Content-Type" = "application/json" }
        $password = $ccpResponse.Content
        Write-Host "✅ Password retrieved from CCP."
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

# ===== LOGIN =====
Write-Host "[DEBUG] Logging in to REST API at $pvwaurl/API/Auth/$authtype/Logon"
$body = @{ username = $username; password = $password } | ConvertTo-Json
try {
    $token = Invoke-RestMethod -Uri "$pvwaurl/API/Auth/$authtype/Logon" -Method POST -Body $body -ContentType "application/json"
    Write-Host "✅ Authenticated successfully."
} catch {
    Write-Error "❌ Authentication failed: $_"
    exit 1
}
$headers = @{ Authorization = $token }

# ===== GET LIST OF SAFES =====
Write-Host "[DEBUG] Retrieving available safes..." -ForegroundColor Cyan
try {
    $safesResponse = Invoke-RestMethod -Method GET -Uri "$pvwaurl/API/Safes?limit=1000" -Headers $headers
    $safeNames = $safesResponse.value.safeName
    Write-Host "[DEBUG] Found $($safeNames.Count) safes:"
    $safeNames | ForEach-Object { Write-Host "  - $_" }
} catch {
    Write-Error "❌ Failed to retrieve safes: $_"
    exit 1
}

# ===== PROMPT FOR SAFE SELECTION =====
$safeToQuery = Read-Host "Enter specific safe name or press Enter to process all"
if ([string]::IsNullOrWhiteSpace($safeToQuery)) {
    $selectedSafes = $safeNames
} else {
    if ($safeNames -contains $safeToQuery) {
        $selectedSafes = @($safeToQuery)
    } else {
        Write-Warning "❌ Safe '$safeToQuery' not found in available safes. Exiting."
        exit 1
    }
}

# ===== PROMPT FOR FILTERS =====
$extraFilters = @{ }
$platformFilter = Read-Host "Filter by platformId (or press Enter to skip)"
if ($platformFilter) { $extraFilters["platformId"] = $platformFilter }
$usernameFilter = Read-Host "Filter by userName (or press Enter to skip)"
if ($usernameFilter) { $extraFilters["userName"] = $usernameFilter }

$nonCompliantAccounts = @()

# ===== FETCH AND EVALUATE ACCOUNTS =====
foreach ($safe in $selectedSafes) {
    $accountsUri = "$pvwaurl/API/Accounts?limit=1000"
    Write-Host "[DEBUG] Retrieving accounts via REST API from $accountsUri" -ForegroundColor Yellow

    try {
        $response = Invoke-RestMethod -Uri $accountsUri -Headers $headers -Method GET
        Write-Host "[DEBUG] Raw API response:" (ConvertTo-Json $response -Depth 4)

        $accounts = $response.value | Where-Object {
            $_.safeName -eq $safe -and
            (!$platformFilter -or $_.platformId -eq $platformFilter) -and
            (!$usernameFilter -or $_.userName -eq $usernameFilter)
        }
        Write-Host "✅ Retrieved $($accounts.Count) accounts from safe: $safe."
    } catch {
        Write-Warning "⚠️ Failed to retrieve accounts from safe $safe : $_"
        continue
    }

    foreach ($acct in $accounts) {
        Write-Host "[DEBUG] Processing account: $($acct.userName) on $($acct.address)"
        $mgmt = $acct.secretManagement
        $reasonList = @()

        if ($mgmt.automaticManagementEnabled -ne $true) {
            $reasonList += "Not managed by CPM"
        }
        if ($mgmt.lastVerifiedStatus -eq "Failed" -or -not $mgmt.lastVerifiedStatus) {
            $reasonList += "Password verification fails"
        }
        if ($mgmt.lastChangeStatus -eq "Failed" -or -not $mgmt.lastChangeStatus) {
            $reasonList += "Password change failed"
        }
        if ($mgmt.lastChangedDate) {
            $lastChange = [datetime]$mgmt.lastChangedDate
            if (((Get-Date) - $lastChange).Days -gt $passwordAgeThreshold) {
                $reasonList += "Outdated password"
            }
        }
        if (-not $mgmt.managementStatus -or $mgmt.status -eq "platformManagementDisabled") {
            $reasonList += "CPM Disabled"
        }
        if (-not $acct.platformId -or $acct.platformId -match "manual") {
            $reasonList += "Platform misconfiguration"
        }

        if ($reasonList.Count -gt 0) {
            $reason = $reasonList -join "; "
            Write-Host "[DEBUG] Marked NON-COMPLIANT: $reason"
            $acct | Add-Member -NotePropertyName NonCompliantReason -NotePropertyValue $reason -Force
            $nonCompliantAccounts += $acct
        }
    }
}

# ===== EXPORT RESULTS =====
if ($nonCompliantAccounts.Count -gt 0) {
    $nonCompliantAccounts | Select-Object userName, address, platformId, safeName, @{Name='MgmtEnabled';Expression={$_.secretManagement.automaticManagementEnabled}}, @{Name='MgmtStatus';Expression={$_.secretManagement.status}}, NonCompliantReason | Export-Csv -Path $exportCsvPath -NoTypeInformation
    Write-Host "✅ Exported $($nonCompliantAccounts.Count) non-compliant accounts to: $exportCsvPath" -ForegroundColor Green
} else {
    Write-Host "✅ No non-compliant accounts found."
}

# ===== LOG OFF =====
try {
    Invoke-RestMethod -Uri "$pvwaurl/API/Auth/Logoff" -Headers $headers -Method POST | Out-Null
    Write-Host "🔒 Logged off from CyberArk."
} catch {
    Write-Warning "⚠️ Failed to log off cleanly."
}
