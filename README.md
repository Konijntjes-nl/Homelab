# 🧪 Homelab

Welcome to my Homelab automation and experimentation repository. This repo contains structured scripts, ideas, and automation tools for managing infrastructure components like CyberArk, Ansible, and Proxmox.

---

## 📁 Repository Structure

| Folder      | Description |
|-------------|-------------|
| `Ansible/`  | Ansible playbooks and roles to automate system provisioning, security hardening, and configuration management. |
| `CyberArk/` | PowerShell scripts to interact with the CyberArk REST API for account management, compliance reporting, and automation. |
| `Proxmox/`  | Bash and cloud-init scripts for automating Proxmox VM provisioning, backup, and image customization. |

---

## 🔄 Workflow

Each tool (Ansible, CyberArk, Proxmox) follows a structured flow:

1. **Ideas/** – Brainstorming area or early-stage notes/scripts.
2. **Scripts/Staging/** – Work-in-progress or unverified scripts.
3. **Scripts/Done/** – Production-ready and tested automation.

---

## ✅ Highlights

- 🔐 **CyberArk Automation**
  - Retrieve privileged account usage logs
  - Reset non-compliant accounts
  - Resume CPM and trigger reconciliations

- 🛠 **Ansible Roles**
  - Secure Linux hosts (Ubuntu/Debian)
  - Bootstrap new servers
  - Deploy self-hosted services

- 💻 **Proxmox Scripting**
  - Generate secure, hardened cloud-init templates
  - Automate backup snapshots
  - Optimize disk space and cleanup tasks

---

## 📦 Requirements

- PowerShell 5.1+ or PowerShell Core (for CyberArk)
- Ansible 2.9+ (for configuration tasks)
- Proxmox VE 7+ (for hypervisor automation)
- CyberArk REST API access

---

## 📜 License

MIT — Feel free to use, modify, and contribute.

---

## 🤝 Contributing

Suggestions and PRs are welcome! Please submit any ideas or improvements via the `Ideas/` folders or open an issue.
