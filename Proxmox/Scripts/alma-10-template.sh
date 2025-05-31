############################################################################
#############################################################################
export IMAGES_PATH="/root/images/" # defines the path where the images will be stored and change the path to it.
cd ${IMAGES_PATH}
#############################################################################
echo downloading cloud-image
#############################################################################
wget -O AlmaLinux-10-GenericCloud-latest.x86_64.qcow2 https://almalinux.mirror.liteserver.nl/10/cloud/x86_64/images/AlmaLinux-10-GenericCloud-latest.x86_64.qcow2
#############################################################################
echo modifing AlmaLinux-9-GenericCloud
#############################################################################
virt-customize -a AlmaLinux-10-GenericCloud-latest.x86_64.qcow2 --install "vim,unzip,bash-completion,wget,curl,qemu-guest-agent"
virt-customize -a AlmaLinux-10-GenericCloud-latest.x86_64.qcow2 --run-command 'systemctl enable qemu-guest-agent'
virt-customize -a AlmaLinux-10-GenericCloud-latest.x86_64.qcow2 --timezone "Europe/Amsterdam"
virt-customize -a AlmaLinux-10-GenericCloud-latest.x86_64.qcow2 --selinux-relabel
qemu-img resize AlmaLinux-10-GenericCloud-latest.x86_64.qcow2 20G
#############################################################################
#############################################################################
export QEMU_CPU_MODEL="host"                        # Specifies the CPU model to be used for the VM according your environment and the desired CPU capabilities.
export VM_CPU_SOCKETS=1
export VM_CPU_CORES=1
export VM_MEMORY=1024
export CLOUD_INIT_USER="mlam"                       # Specifies the username to be created using Cloud-init.
export CLOUD_INIT_SSHKEY="/root/.ssh/id_rsa.pub"    # Provides the path to the SSH public key for the user.
export CLOUD_INIT_IP="dhcp"
export CLOUD_INIT_NAMESERVER="10.0.0.254"
export CLOUD_INIT_SEARCHDOMAIN="mgmt.cybermark.tech"
export TEMPLATE_ID="9001"
export VM_NAME="alma-10"
export VM_DISK_IMAGE="${IMAGES_PATH}/AlmaLinux-10-GenericCloud-latest.x86_64.qcow2"
# Create VM. Change the cpu model
qm create ${TEMPLATE_ID} --name ${VM_NAME} --cpu ${QEMU_CPU_MODEL} --sockets ${VM_CPU_SOCKETS} --cores ${VM_CPU_CORES} --memory ${VM_MEMORY} --vga serial0 --serial0 socket --net0 virtio,bridge=vmbr0 --ostype l26 --agent 1 --scsihw virtio-scsi-single
# Import Disk
qm set ${TEMPLATE_ID} --scsi0 unraid:0,import-from=${VM_DISK_IMAGE}
# Add Cloud-Init CD-ROM drive. This enables the VM to receive customization instructions during boot.
qm set ${TEMPLATE_ID} --ide2 unraid:cloudinit --boot order=scsi0
# Cloud-init network-data
qm set ${TEMPLATE_ID} --ipconfig0 ip=${CLOUD_INIT_IP} --nameserver ${CLOUD_INIT_NAMESERVER} --searchdomain ${CLOUD_INIT_SEARCHDOMAIN}
# Cloud-init user-data
qm set ${TEMPLATE_ID} --ciupgrade 0 --ciuser ${CLOUD_INIT_USER} --sshkeys ${CLOUD_INIT_SSHKEY}
# Cloud-init regenerate ISO image, ensuring that the VM will properly initialize with the desired parameters.
qm cloudinit update ${TEMPLATE_ID}
# Create Template
qm set ${TEMPLATE_ID} --name "${VM_NAME}-template"
qm template ${TEMPLATE_ID}
#############################################################################
#############################################################################
