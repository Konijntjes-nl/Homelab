# Ansible Scripts

This folder contains Ansible playbooks and roles designed to automate server provisioning, security hardening, and application deployment.

---

## 📂 Playbooks

Each playbook is modular and serves a specific purpose, like bootstrapping a new host or installing services.

---

## ⚙️ Usage Examples

```bash
ansible-playbook -i inventory/hosts.ini secure-ubuntu.yml
ansible-playbook -i inventory/hosts.ini deploy-docker-stack.yml
