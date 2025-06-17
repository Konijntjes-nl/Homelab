<#
=======================================
CyberArk Privileged Account Usage Logs
Author       : Mark Lam
Created      : 2025-06-17
Description  : Retrieves privileged account usage logs from CyberArk.
               Supports CCP or manual password. Outputs to CSV.
=======================================
#>

# ========== CONFIGURATION ==========
# PVWA Configuration
$pvwaURL      = "https://pvwa.cybermark.lab"
$username     = "monitoring-user"
$authType     = "CyberArk"

# CCP Configuration
$useCCP       = $true
$ccpIP        = "ccp.cybermark.lab"
$appID        = "MonitoringApp"
$ccpSafe      = "PrivilegedAccounts"
$ccpObject    = "monitoring-user"

# Date Range
$startDate = Read-Host "Enter start date (yyyy-MM-dd)"
$endDate   = Read-Host "Enter end date (yyyy-MM-dd)"

# Output File
$outputCSV = "$PSScriptRoot\CyberArk_UsageLogs_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

# ========== GET PASSWORD ==========
if ($useCCP) {
    try {
        Write-Host "🔐 Retrieving password via CCP..." -ForegroundColor Cyan
        $ccpResponse = Invoke-RestMethod -Method GET `
            -Uri "https://$ccpIP/AIMWebService/api/Accounts?AppID=$appID&Safe=$ccpSafe&Object=$ccpObject" `
            -Headers @{ "Content-Type" = "application/json" }
        $password = $ccpResponse.Content
    } catch {
        Write-Error "❌ Failed to retrieve password from CCP: $_"
        exit 1
    }
} else {
    Write-Host "🔐 Enter password manually:"
    $securePass = Read-Host -AsSecureString
    $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
    )
}

# ========== LOGIN ==========
try {
    $body = @{ username = $username; password = $password } | ConvertTo-Json
    $token = Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Auth/$authType/Logon" `
        -Method POST -Body $body -ContentType "application/json"
    Write-Host "✅ Authenticated successfully." -ForegroundColor Green
} catch {
    Write-Error "❌ Authentication failed: $_"
    exit 1
}

$headers = @{ Authorization = $token }

# ========== GET AUDIT LOGS ==========
try {
    $uri = "$pvwaURL/PasswordVault/API/Audits?startDate=$startDate&endDate=$endDate&search=Logon"
    $audits = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET

    if (-not $audits.value) {
        Write-Warning "No audit logs found for specified dates."
        return
    }

    # ========== FILTER FOR PRIVILEGED ACCOUNT ACCESS ==========
    $filtered = $audits.value | Where-Object {
        $_.Action -eq "Logon" -and $_.User -like "a*" -and $_.TargetUser -like "b*"
    }

    if ($filtered.Count -eq 0) {
        Write-Host "No privileged account usage logs found."
    } else {
        $filtered |
            Select-Object Date, User, TargetUser, Action, Safe, System, TicketingID |
            Export-Csv -Path $outputCSV -NoTypeInformation -Encoding UTF8
        Write-Host "💾 Exported logs to $outputCSV" -ForegroundColor Green
    }
} catch {
    Write-Error "❌ Failed to retrieve audit logs: $_"
}

# ========== LOGOFF ==========
try {
    Invoke-RestMethod -Uri "$pvwaURL/PasswordVault/API/Auth/Logoff" -Headers $headers -Method POST | Out-Null
    Write-Host "🔒 Logged off from CyberArk."
} catch {
    Write-Warning "⚠️ Failed to log off cleanly."
}
