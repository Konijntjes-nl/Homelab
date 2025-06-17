# CyberArk Privileged Account Usage Logs

## Overview
This repo contains two PowerShell scripts to retrieve CyberArk privileged account usage logs:

- **Get-UsageLogs-CLI.ps1** — CLI (terminal) version supporting CCP or manual password.
- **Get-UsageLogs-GUI.ps1** — Windows Forms GUI version with date pickers, CCP toggle, and password input.

## Prerequisites
- PowerShell 5.1+ (Windows)
- Network access to CyberArk PVWA and CCP endpoints
- Appropriate privileges for CyberArk monitoring user

## Usage

### CLI Version

```powershell
.\Get-UsageLogs-CLI.ps1