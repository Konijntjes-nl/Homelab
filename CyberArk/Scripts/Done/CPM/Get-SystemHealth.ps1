<#
=======================================
  CyberArk System Health Summary Script
  Author       : Mark Lam
  Created      : 2025-05-19
  Description  : Retrieves CyberArk system health summary,
                 optionally retrieves password from CCP,
                 exports JSON, and displays components & vaults.

  Revision History:
  ---------------------------------------------------------------------------------
  Date        | Author    | Description
  ------------|-----------|--------------------------------------------------------
  2025-05-19  | Mark Lam  | Initial version using CCP for credentials + JSON export
=======================================
#>

# ===== CONFIGURATION =====
$pvwaurl        = "<pvwa-url>"                              # PVWA URL (FQDN or IP)
$username       = "<privileged-account>"                    # Username of the privileged account
$authtype       = "CyberArk"                                # Authentication type
$exportjsonpath = ".\logs\ComponentHealth.json"                  # Export JSON path

# CCP Settings
$ccpIP          = "<ccp-url>"                               # CCP server (FQDN or IP)
$appID          = "<application-id>"                        # CCP AppID
$safe           = "<safe-name>"                             # Safe name
$object         = "<privileged-account>"                    # Object name in safe

$useCCP         = $true                                     # Set $false to prompt for password

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
        Write-Host "✅ Password retrieved securely from CCP."
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
$body = @{
    username = $username
    password = $password
} | ConvertTo-Json

try {
    $token = Invoke-RestMethod `
        -Uri "$pvwaurl/API/Auth/$authtype/Logon" `
        -Method POST `
        -Body $body `
        -ContentType "application/json"
    Write-Host "✅ Authenticated successfully."
} catch {
    Write-Error "❌ Authentication failed: $_"
    exit 1
}

$headers = @{ Authorization = $token }

# ===== GET SYSTEM HEALTH SUMMARY =====
try {
    Write-Host "🔍 Requesting system health summary..." -ForegroundColor Cyan
    $response = Invoke-RestMethod `
        -Uri "$pvwaurl/API/ComponentsMonitoringSummary/" `
        -Headers $headers `
        -Method GET
} catch {
    Write-Error "❌ Failed to retrieve system health summary: $_"
    try {
        Invoke-RestMethod -Uri "$pvwaurl/API/Auth/Logoff" -Headers $headers -Method POST | Out-Null
    } catch {}
    exit 1
}

# ===== DISPLAY COMPONENTS =====
Write-Host "`n🖥️  [System Components]" -ForegroundColor Cyan
foreach ($comp in $response.Components) {
    Write-Host ("ComponentID: {0}, Name: {1}, Description: {2}, Connected: {3}, Total: {4}, Stat: {5}" -f
        $comp.ComponentID,
        $comp.ComponentName,
        $comp.Description,
        $comp.ConnectedComponentCount,
        $comp.ComponentTotalCount,
        $comp.ComponentSpecificStat)
}

# ===== DISPLAY VAULTS =====
Write-Host "`n🔐 [Vaults]" -ForegroundColor Cyan
foreach ($vault in $response.Vaults) {
    Write-Host ("IP: {0}, Role: {1}, LoggedOn: {2}" -f
        $vault.IP,
        $vault.Role,
        $vault.IsLoggedOn)
}

# ===== EXPORT TO JSON =====
try {
    $response | ConvertTo-Json -Depth 5 | Out-File -FilePath $exportjsonpath -Encoding UTF8
    Write-Host "`n📁 Exported system health summary to: $exportjsonpath"
} catch {
    Write-Warning "⚠️ Failed to export JSON: $_"
}

# ===== LOG OFF =====
try {
    Invoke-RestMethod -Uri "$pvwaurl/API/Auth/Logoff" -Headers $headers -Method POST
    Write-Host "`n🔒 Logged off from CyberArk."
} catch {
    Write-Warning "⚠️ Failed to log off cleanly."
}
