# Proxmox Scripts

This folder contains automation scripts designed to create and configure Linux VM templates for Proxmox Virtual Environment (VE). These scripts facilitate the building of reproducible, secure, and customizable VM templates for Rocky Linux (versions 9 and 10) and Ubuntu 24.04.

---

## Scripts Overview

| Script Name                  | Relative Path                                                | Description                                                  |
|-----------------------------|--------------------------------------------------------------|--------------------------------------------------------------|
| `create-rocky10-template.sh`  | Proxmox-create-rocky10-template/create-rocky10-template.sh  | Automates the creation of a Rocky Linux 10 VM template with secure environment variable handling. |
| `create-rocky9-template.sh`   | Proxmox-create-rocky9-template/create-rocky9-template.sh    | Automates the creation of a Rocky Linux 9 VM template with secure environment variable handling.  |
| `create-ubuntu24-template.sh` | Proxmox-create-ubuntu24-template/create-ubuntu24-template.sh| Automates the creation of an Ubuntu 24.04 VM template with secure environment variable handling. |

---

## Features

- Scripts use strict bash settings (`set -euo pipefail`) for robust error handling.
- Securely load environment variables from an external `.env` file.
- Automate VM template creation and configuration optimized for Proxmox VE.
- Designed for easy modification and reuse in various Proxmox environments.

---

## Usage

1. Place your environment variables in a `.env` file, typically located at `/root/scripts/.env`, or modify the scripts to point to your preferred location.

2. Run the desired script with root or sudo privileges on your Proxmox host or a compatible Linux VM:

```bash
sudo ./create-rocky10-template.sh
