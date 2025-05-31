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
: "${TEMPLATE_ID:=9000}"
: "${VM_NAME:=rocky-9}"
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
wget -O Rocky-9-GenericCloud-Base.latest.x86_64.qcow2 \
    https://rockylinux.mirror.liteserver.nl/9.5/images/x86_64/Rocky-9-GenericCloud-Base-9.5-20241118.0.x86_64.qcow2

#############################################################################
echo "Modifying cloud image with virt-customize..."
#############################################################################
IMAGE_FILE="Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"

virt-customize -a "$IMAGE_FILE" --install "vim,bash-completion,wget,curl,qemu-guest-agent"
virt-customize -a "$IMAGE_FILE" --run-command 'systemctl enable qemu-guest-agent'
virt-customize -a "$IMAGE_FILE" --run-command \
    'sed -i "s/.*PasswordAuthentication.*/PasswordAuthentication yes/g" /etc/ssh/sshd_config'
virt-customize -a "$IMAGE_FILE" --run-command \
    'sed -i "s/.*PermitRootLogin.*/PermitRootLogin no/g" /etc/ssh/sshd_config'
virt-customize -a "$IMAGE_FILE" --run-command \
    "sed -i 's/^ssh_pwauth:[[:space:]]*false/ssh_pwauth: true/' /etc/cloud/cloud.cfg"
virt-customize -a "$IMAGE_FILE" --timezone "Europe/Amsterdam"
virt-customize -a "$IMAGE_FILE" --selinux-relabel

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

echo "✅ Rocky Linux 9 template created as VM ID $TEMPLATE_ID"
