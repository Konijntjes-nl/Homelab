# === CONFIGURATION ===
$PVWA = "https://pvwa.cybermark.lab"
$User = "monitoring-user"
$Pass = "Blitzkrieg00!"  # Replace securely!
$ExportFolder = "$PSScriptRoot\PlatformExports"

# Create export folder if it doesn't exist
if (-not (Test-Path -Path $ExportFolder)) {
    New-Item -Path $ExportFolder -ItemType Directory | Out-Null
}

# === AUTHENTICATE ===
$body = @{ username = $User; password = $Pass } | ConvertTo-Json
try {
    $token = Invoke-RestMethod -Uri "$PVWA/PasswordVault/API/Auth/CyberArk/Logon" `
                               -Method POST -Body $body -ContentType "application/json"
    $headers = @{ Authorization = $token }
    Write-Host "✅ Authenticated successfully."
} catch {
    Write-Error "❌ Authentication failed: $_"
    return
}

# === GET ALL PLATFORMS ===
try {
    $platformsResponse = Invoke-RestMethod -Uri "$PVWA/PasswordVault/API/Platforms" -Headers $headers
    if ($platformsResponse.value) {
        $platforms = $platformsResponse.value
    } elseif ($platformsResponse.Platforms) {
        $platforms = $platformsResponse.Platforms
    } else {
        Write-Error "Unknown platforms response structure."
        return
    }
    Write-Host "✅ Retrieved platforms."
} catch {
    Write-Error "❌ Failed to retrieve platforms: $_"
    return
}

# === EXTRACT PLATFORM IDs ===
$platformIDs = @()
foreach ($platform in $platforms) {
    if ($platform.general -and $platform.general.id) {
        $platformIDs += $platform.general.id
    } else {
        Write-Warning "⚠️ Skipping platform without ID."
    }
}

if ($platformIDs.Count -eq 0) {
    Write-Error "❌ No platform IDs found."
    return
}

# === EXPORT EACH PLATFORM TO ZIP ===
foreach ($id in $platformIDs) {
    $exportUrl = "$PVWA/PasswordVault/API/Platforms/$id/Export/"
    $outputFile = Join-Path -Path $ExportFolder -ChildPath "$id.zip"

    try {
        Write-Host "⬇️ Exporting platform '$id' to '$outputFile'..."
        Invoke-RestMethod -Uri $exportUrl -Headers $headers -Method POST -OutFile $outputFile
        Write-Host "✅ Exported platform '$id' successfully."
    } catch {
        Write-Warning "⚠️ Failed to export platform '$id': $_"
    }
}

# === LOGOFF ===
try {
    Invoke-RestMethod -Uri "$PVWA/PasswordVault/API/Auth/Logoff" -Headers $headers -Method POST
    Write-Host "✅ Logged off successfully."
} catch {
    Write-Warning "⚠️ Logoff failed (non-fatal): $_"
}
