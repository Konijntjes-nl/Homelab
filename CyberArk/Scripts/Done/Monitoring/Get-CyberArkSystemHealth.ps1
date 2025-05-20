<#
=======================================
CyberArk System Health Detailed Script
Author       : Mark Lam (adapted by ChatGPT)
Created      : 2025-05-20
Description  : Retrieves detailed CyberArk component health info via REST API.
               Uses known ComponentIDs (PVWA, CPM, PTA, AIM, SessionManagement).
               Converts Unix timestamps to readable strings for display and export.
               Exports individual JSON files per component.
Documentation:
  https://docs.cyberark.com/pam-self-hosted/latest/en/content/webservices/systemdetails.htm
=======================================
#>

# ===== CONFIGURATION =====
# PVWA Settings 
$pvwaurl        = "https://pvwa.cybermark.lab/passwordvault/"  # PVWA URL - ensure trailing slash
$username       = "monitoring-user"                            # Privileged user
$authtype       = "CyberArk"                                   # Authentication type
# CCP Settings
$ccpIP          = "<ccp-url>"                       # CCP server
$appID          = "<application-id>"                # CCP AppID
$safe           = "<safe-name>"                     # Safe name
$object         = "<privileged-account>"            # Object name

$useCCP         = $false                             # Set false to enter password manually
# List of valid ComponentIDs to query - use documented values
$componentIDs = @('PVWA', 'CPM', 'PTA', 'AIM', 'SessionManagement')

# Output directory for JSON exports
$exportBaseDir = "$PSScriptRoot\logs"
if (-not (Test-Path $exportBaseDir)) { New-Item -Path $exportBaseDir -ItemType Directory -Force | Out-Null }

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

# ===== LOGIN & GET TOKEN =====
$body = @{ username = $username; password = $password } | ConvertTo-Json
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

# ===== PROCESS EACH COMPONENT =====
foreach ($compID in $componentIDs) {
    Write-Host "`n🔧 Getting details for ComponentID: $compID" -ForegroundColor Cyan
    try {
        $detail = Invoke-RestMethod `
            -Uri "$pvwaurl/API/ComponentsMonitoringDetails/$compID" `
            -Headers $headers `
            -Method GET

        # Convert Unix timestamps in ComponentInstances
        foreach ($inst in $detail.ComponentInstances) {
            if ($inst.LastLogonDate -and $inst.LastLogonDate -gt 0) {
                $inst.LastLogonDate = [DateTimeOffset]::FromUnixTimeSeconds([int64]$inst.LastLogonDate).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
            }
            if ($inst.LastUpdateTime -and $inst.LastUpdateTime -gt 0) {
                $inst.LastUpdateTime = [DateTimeOffset]::FromUnixTimeSeconds([int64]$inst.LastUpdateTime).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
            }
        }

        # Export to JSON file named by component
        $exportPath = Join-Path $exportBaseDir "ComponentHealth_${compID}.json"
        $detail | ConvertTo-Json -Depth 10 | Out-File -FilePath $exportPath -Encoding UTF8

        Write-Host "💾 Exported $compID details to $exportPath" -ForegroundColor Green
    }
    catch {
        Write-Warning "⚠️ Failed to get details for ComponentID $compID $_"
    }
}

# ===== LOG OFF =====
try {
    Invoke-RestMethod -Uri "$pvwaurl/API/Auth/Logoff" -Headers $headers -Method POST | Out-Null
    Write-Host "`n🔒 Logged off from CyberArk."
} catch {
    Write-Warning "⚠️ Failed to log off cleanly."
}