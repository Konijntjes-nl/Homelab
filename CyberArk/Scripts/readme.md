# CyberArk Scripts

This folder contains PowerShell scripts for automating CyberArk Privileged Access Security (PAS) tasks via the CyberArk REST API. The scripts cover account management, compliance reporting, password resets, session monitoring, and CPM automation.

---

## Folder Structure

- `Done/`  
  Production-ready scripts that have been tested and are ready for use in your CyberArk environment.

- `Staging/`  
  Work-in-progress scripts under development or testing before promotion to `Done/`.

- `Ideas/`  
  Brainstorming notes, concepts, or early-stage automation ideas related to CyberArk.

---

## Usage

Each script generally supports parameters such as:

- `-StartDate` / `-EndDate` to filter logs or reports by date range  
- `-ExportPath` to specify output CSV or XML files  
- `-Verbose` or `-Debug` for detailed logging  
- Credential input via secure methods or CyberArk Credential Provider (CCP) integration

Example to export privileged account usage logs:

```powershell
.\Done\CyberArk-PrivilegedUsageLogs.ps1 -StartDate "2025-01-01" -EndDate "2025-01-31" -ExportPath "C:\Logs\PrivilegedUsage.csv"
