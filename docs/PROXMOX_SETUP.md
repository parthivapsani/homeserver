# Proxmox Setup Guide

Complete guide to setting up Proxmox VE for your home server.

## 1. Install Proxmox VE

1. Download Proxmox VE ISO from https://www.proxmox.com/en/downloads
2. Flash to USB with Balena Etcher or Rufus
3. Boot from USB and install
4. Access web UI at: `https://your-server-ip:8006`

## 2. Post-Installation Setup

### Remove Subscription Notice

```bash
# SSH into Proxmox host
sed -Ezi.bak "s/(Ext\.Msg\.show\(\{[^}]+)title:.+notvaild,([^}]+)\})/void\(\{ \2 \})/" \
  /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
systemctl restart pveproxy.service
```

### Configure Repositories (No Subscription)

```bash
# Disable enterprise repo
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list

# Add no-subscription repo
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > \
  /etc/apt/sources.list.d/pve-no-subscription.list

# Update
apt update && apt full-upgrade -y
```

### Install Useful Packages

```bash
apt install -y vim htop iotop ncdu tmux
```

## 3. Storage Setup

### Pass Through Entire Disks to VM

Identify your disks:
```bash
lsblk -o NAME,SIZE,MODEL,SERIAL
ls -la /dev/disk/by-id/
```

For each data disk, add to VM config (`/etc/pve/qemu-server/<vmid>.conf`):
```
scsi1: /dev/disk/by-id/ata-WDC_WD180EDGZ-SERIAL,backup=0
scsi2: /dev/disk/by-id/ata-WDC_WD180EDGZ-SERIAL2,backup=0
```

Or via GUI: VM → Hardware → Add → Hard Disk → Use existing disk

### Create ZFS Pool (Alternative)

If managing storage from Proxmox instead of VM:
```bash
# Create mirror pool
zpool create -o ashift=12 storage mirror \
  /dev/disk/by-id/ata-WDC_WD180EDGZ-SERIAL \
  /dev/disk/by-id/ata-WDC_WD180EDGZ-SERIAL2

# Create datasets
zfs create storage/media
zfs create storage/backups
zfs create storage/photos

# Set compression
zfs set compression=lz4 storage
```

## 4. Intel iGPU Passthrough (for Jellyfin Transcoding)

### Enable IOMMU

Edit GRUB:
```bash
nano /etc/default/grub

# Change this line:
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
```

Update GRUB:
```bash
update-grub
```

### Load VFIO Modules

```bash
# Add modules
cat >> /etc/modules << EOF
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
EOF
```

### Blacklist GPU Drivers (for full passthrough)

Only needed if passing through dedicated GPU, not for Intel iGPU:
```bash
cat >> /etc/modprobe.d/blacklist.conf << EOF
blacklist nouveau
blacklist nvidia
blacklist radeon
EOF
```

### Update initramfs and Reboot

```bash
update-initramfs -u -k all
reboot
```

### Verify IOMMU

```bash
dmesg | grep -e DMAR -e IOMMU
# Should see: DMAR: IOMMU enabled
```

### Find iGPU Device

```bash
lspci -nn | grep VGA
# Example output: 00:02.0 VGA compatible controller [0300]: Intel Corporation... [8086:4692]
```

### Add iGPU to VM (LXC Method - Easier)

For LXC containers, add to config (`/etc/pve/lxc/<id>.conf`):
```
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
```

### Add iGPU to VM (Full VM Method)

Add to VM config:
```
hostpci0: 0000:00:02.0,pcie=1
```

Or via GUI: VM → Hardware → Add → PCI Device → Select Intel iGPU

## 5. Create Ubuntu VM for Docker

### Download Ubuntu Cloud Image

```bash
cd /var/lib/vz/template/iso/
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

### Create VM

```bash
# Create VM
qm create 100 --name homeserver --memory 65536 --cores 8 --net0 virtio,bridge=vmbr0

# Import cloud image as disk
qm importdisk 100 jammy-server-cloudimg-amd64.img local-lvm

# Attach disk
qm set 100 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-100-disk-0

# Add cloud-init drive
qm set 100 --ide2 local-lvm:cloudinit

# Set boot order
qm set 100 --boot c --bootdisk scsi0

# Configure cloud-init
qm set 100 --ciuser homeserver
qm set 100 --cipassword your-password
qm set 100 --ipconfig0 ip=dhcp
# Or static: --ipconfig0 ip=192.168.1.100/24,gw=192.168.1.1

# Add SSH key (optional)
qm set 100 --sshkeys ~/.ssh/authorized_keys

# Start VM
qm start 100
```

### Alternative: Use Proxmox GUI

1. Create VM → Name: homeserver
2. OS: Use Ubuntu ISO
3. System: BIOS (SeaBIOS), Machine: q35
4. Disks: 100GB on SSD storage
5. CPU: 8 cores, Type: host
6. Memory: 65536 MB
7. Network: vmbr0, VirtIO

### Pass Through Storage Disks

After VM creation:
```bash
# Add each data disk
qm set 100 --scsi1 /dev/disk/by-id/ata-YOUR-DISK-ID
qm set 100 --scsi2 /dev/disk/by-id/ata-YOUR-DISK-ID-2
```

### Pass Through iGPU

```bash
qm set 100 --hostpci0 0000:00:02.0,pcie=1
```

## 6. Inside the Ubuntu VM

### Mount Disks

```bash
# Create mount points
sudo mkdir -p /mnt/cache /mnt/storage

# For simple ext4:
sudo mkfs.ext4 /dev/sdb
sudo mount /dev/sdb /mnt/cache

# Add to fstab for persistence
echo "/dev/sdb /mnt/cache ext4 defaults 0 2" | sudo tee -a /etc/fstab
```

### Install Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
```

### Verify iGPU Access

```bash
ls -la /dev/dri/
# Should see: card0, renderD128
```

### Clone Home Server Config

```bash
git clone <your-repo> ~/homeserver
cd ~/homeserver
cp .env.example .env
nano .env
sudo ./scripts/setup.sh
docker compose up -d
```

## 7. Network Configuration

### Static IP for VM

In Proxmox, or within Ubuntu:
```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

```yaml
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: no
      addresses:
        - 192.168.1.100/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 192.168.1.100  # Point to AdGuard after setup
          - 1.1.1.1
```

```bash
sudo netplan apply
```

### Port Forwarding (Router)

Forward these ports to your server for remote access:
- 80 (HTTP → redirects to HTTPS)
- 443 (HTTPS)

## 8. USB Passthrough (for OctoPrint, Zigbee, HDHomeRun)

### Find USB Device

```bash
lsusb
# Example: Bus 001 Device 005: ID 1a86:7523 QinHeng Electronics CH340 serial converter
```

### Add to VM

Via GUI: VM → Hardware → Add → USB Device → Select device

Or in config:
```
usb0: host=1a86:7523
```

## 9. Backup Proxmox Config

```bash
# Backup all VM/container configs
tar -czf /tmp/proxmox-config-backup.tar.gz /etc/pve/

# Copy off-server
scp /tmp/proxmox-config-backup.tar.gz user@backup-location:/path/
```

## Troubleshooting

### VM Won't Start After iGPU Passthrough

Try `pcie=0` instead of `pcie=1`, or use `x-vga=1` flag.

### iGPU Not Visible in VM

Ensure IOMMU is enabled:
```bash
dmesg | grep -e DMAR -e IOMMU
```

Check VFIO modules loaded:
```bash
lsmod | grep vfio
```

### Network Performance Issues

Ensure VirtIO drivers are used:
```bash
# Check network device type in VM
ethtool -i eth0
# Driver should be: virtio_net
```
