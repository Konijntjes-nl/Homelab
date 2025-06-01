#!/bin/bash

set -euo pipefail

#############################################################################
# Load environment variables securely
#############################################################################
ENV_FILE="/root/scripts/.env"

if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

# Check required vars
: "${CLOUD_INIT_PASSWORD:?Missing CLOUD_INIT_PASSWORD in .env}"
: "${CLOUD_INIT_USER:=mlam}"
: "${CLOUD_INIT_SSHKEY:=/root/.ssh/id_rsa.pub}"
: "${IMAGES_PATH:=/root/images/}"
: "${TEMPLATE_ID:=9001}"
: "${VM_NAME:=ubuntu24}"
: "${CLOUD_INIT_IP:=dhcp}"
: "${CLOUD_INIT_NAMESERVER:=10.0.0.254}"
: "${CLOUD_INIT_SEARCHDOMAIN:=mgmt.cybermark.tech}"
: "${VM_CPU_SOCKETS:=1}"
: "${VM_CPU_CORES:=1}"
: "${VM_MEMORY:=1024}"
: "${QEMU_CPU_MODEL:=host}"

if [[ ! -f "$CLOUD_INIT_SSHKEY" ]]; then
    echo "Error: SSH public key not found at $CLOUD_INIT_SSHKEY"
    exit 1
fi

mkdir -p "$IMAGES_PATH"
cd "$IMAGES_PATH"

#############################################################################
echo "Downloading cloud image..."
#############################################################################
wget -O noble-server-cloudimg-amd64.img \
    https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

#############################################################################
echo "Modifying cloud image with virt-customize..."
#############################################################################
IMAGE_FILE="noble-server-cloudimg-amd64.img"

virt-customize -a "$IMAGE_FILE" --install "vim,bash-completion,wget,curl,qemu-guest-agent"
virt-customize -a "$IMAGE_FILE" --run-command 'systemctl enable qemu-guest-agent'
virt-customize -a "$IMAGE_FILE" --timezone "Europe/Amsterdam"

qemu-img resize "$IMAGE_FILE" 20G

#############################################################################
echo "Creating Proxmox VM template..."
#############################################################################
VM_DISK_IMAGE="${IMAGES_PATH}/${IMAGE_FILE}"

qm create "$TEMPLATE_ID" \
    --name "$VM_NAME" \
    --cpu "$QEMU_CPU_MODEL" \
    --sockets "$VM_CPU_SOCKETS" \
    --cores "$VM_CPU_CORES" \
    --memory "$VM_MEMORY" \
    --vga serial0 \
    --serial0 socket \
    --net0 virtio,bridge=vmbr0 \
    --ostype l26 \
    --agent 1 \
    --scsihw virtio-scsi-single

qm set "$TEMPLATE_ID" --scsi0 unraid:0,import-from="$VM_DISK_IMAGE"
qm set "$TEMPLATE_ID" --ide2 unraid:cloudinit --boot order=scsi0
qm set "$TEMPLATE_ID" --ipconfig0 ip="$CLOUD_INIT_IP" \
    --nameserver "$CLOUD_INIT_NAMESERVER" \
    --searchdomain "$CLOUD_INIT_SEARCHDOMAIN"
qm set "$TEMPLATE_ID" \
    --ciupgrade 0 \
    --ciuser "$CLOUD_INIT_USER" \
    --sshkeys "$CLOUD_INIT_SSHKEY" \
    --cipassword "$CLOUD_INIT_PASSWORD"
qm cloudinit update "$TEMPLATE_ID"
qm set "$TEMPLATE_ID" --name "${VM_NAME}-template"
qm template "$TEMPLATE_ID"

echo "✅ Ubuntu 24.04 template created as VM ID $TEMPLATE_ID"
