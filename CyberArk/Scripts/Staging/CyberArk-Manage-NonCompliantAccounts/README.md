# 🔧 Manage Non-Compliant CyberArk Accounts

Automates the remediation of non-compliant privileged accounts in CyberArk by resuming CPM and resetting passwords.

## 🧩 Features
- Filters unmanaged or non-rotated accounts
- Automatically resumes CPM
- Triggers credential rotation
- Logs actions and results

## 📘 Variants
- `Manage-CyberArk-NonCompliantAccounts.ps1`: Manual credential input
- `Manage-CyberArk-NonCompliantAccounts-ccp.ps1`: Uses CyberArk Central Credential Provider (CCP) for secure authentication

## ⚙️ Requirements
- PowerShell
- API access
- (Optional) CCP configured and reachable

## 📌 Status
Currently in staging. Tested in lab but not yet production-certified.
