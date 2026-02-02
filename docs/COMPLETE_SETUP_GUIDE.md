# Complete Setup Guide: From Bare PC to Working Home Server

This guide walks you through every step from an unassembled PC to a fully functional home server.

---

## Table of Contents

1. [Phase 1: Hardware Assembly](#phase-1-hardware-assembly)
2. [Phase 2: Install Proxmox](#phase-2-install-proxmox)
3. [Phase 3: Configure Proxmox](#phase-3-configure-proxmox)
4. [Phase 4: Set Up Storage](#phase-4-set-up-storage)
5. [Phase 5: Enable iGPU Passthrough](#phase-5-enable-igpu-passthrough)
6. [Phase 6: Create Ubuntu VM](#phase-6-create-ubuntu-vm)
7. [Phase 7: Configure Ubuntu VM](#phase-7-configure-ubuntu-vm)
8. [Phase 8: Install Docker & Deploy Stack](#phase-8-install-docker--deploy-stack)
9. [Phase 9: Configure Core Services](#phase-9-configure-core-services)
10. [Phase 10: Configure Media Stack](#phase-10-configure-media-stack)
11. [Phase 11: Configure Other Services](#phase-11-configure-other-services)
12. [Phase 12: Final Setup & Testing](#phase-12-final-setup--testing)

---

## Phase 1: Hardware Assembly

### Shopping List (Recommended Build)

| Component | Recommendation | Purpose |
|-----------|---------------|---------|
| CPU | Intel Core i5-12400 or i5-13400 | Quick Sync for transcoding |
| Motherboard | B660/B760 with 6+ SATA ports | Storage connectivity |
| RAM | **32GB DDR4-3200 (2x16GB)** | Containers + Immich ML |
| Boot SSD | 500GB NVMe | Proxmox OS |
| Cache SSD | 1-2TB NVMe | Docker appdata, downloads |
| Media HDDs | 3-4x 12-18TB | Movies, TV, photos, backups |
| Parity HDD | 1x matching size | Data protection |
| Case | Fractal Node 804 or Define 7 | Many drive bays |
| PSU | 550W 80+ Gold | Reliable power |
| Network | 1GbE or 2.5GbE | 1GbE is sufficient for most use |
| UPS | 750VA+ (USB connected) | Power protection + NUT integration |
| USB Drive | 8GB+ | Proxmox installer |

**RAM Note**: 32GB is sufficient for this workload (~14GB active usage). Only get 64GB if you plan to run multiple VMs, use ZFS with large ARC cache, or add significant additional workloads.

**Power Consumption**: Expect 40-60W idle, 80-120W under load. Annual cost: ~$65-85.

### Assembly Steps

1. **Install CPU** into motherboard (align triangle markers)
2. **Install RAM** in correct slots (check motherboard manual for dual-channel)
3. **Install NVMe SSDs** in M.2 slots
4. **Mount motherboard** in case
5. **Install PSU** and connect cables:
   - 24-pin motherboard power
   - 8-pin CPU power
   - SATA power for HDDs
6. **Install HDDs** in drive bays
7. **Connect SATA data cables** from HDDs to motherboard
8. **Connect front panel** cables (power button, USB, etc.)
9. **Connect network cable** to router
10. **Connect monitor, keyboard** for initial setup

### BIOS Settings

Power on and enter BIOS (usually DEL or F2):

1. **Enable XMP/DOCP** for RAM (runs at rated speed)
2. **Enable VT-x/VT-d** (Virtualization Technology)
3. **Set boot order**: USB first (for Proxmox install)
4. **Disable Secure Boot** (can cause issues with Proxmox)
5. **Save and exit**

---

## Phase 2: Install Proxmox

### Create Bootable USB

On another computer:

1. Download Proxmox VE ISO: https://www.proxmox.com/en/downloads
2. Download Balena Etcher: https://etcher.balena.io/
3. Flash ISO to USB drive with Etcher

### Install Proxmox

1. Boot from USB drive
2. Select **"Install Proxmox VE"**
3. Accept EULA
4. **Select target disk**: Choose your 500GB NVMe boot drive
   - ⚠️ Do NOT select your data HDDs
5. **Country/Timezone**: Select yours
6. **Password**: Set a strong root password (save this!)
7. **Network configuration**:
   - Hostname: `proxmox.local` (or your preference)
   - IP: Use static IP (e.g., `192.168.1.50/24`)
   - Gateway: Your router IP (e.g., `192.168.1.1`)
   - DNS: `1.1.1.1` (Cloudflare) or your router
8. **Install** and wait for completion
9. **Remove USB** and reboot

### First Access

1. Note the URL shown on console (e.g., `https://192.168.1.50:8006`)
2. From another computer, open that URL in browser
3. Accept the security warning (self-signed certificate)
4. Login: `root` / your password
5. Ignore subscription notice (click OK)

---

## Phase 3: Configure Proxmox

### SSH into Proxmox

From your computer's terminal:
```bash
ssh root@192.168.1.50
```

### Remove Subscription Notice

```bash
# Remove popup
sed -Ezi.bak "s/(Ext\.Msg\.show\(\{[^}]+)title:.+notvaild,([^}]+)\})/void\(\{ \2 \})/" \
  /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js

# Restart web interface
systemctl restart pveproxy.service
```

### Configure Repositories (No-Subscription)

```bash
# Disable enterprise repo (requires subscription)
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list

# Add free no-subscription repo
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > \
  /etc/apt/sources.list.d/pve-no-subscription.list

# Update system
apt update && apt full-upgrade -y

# Install useful tools
apt install -y vim htop iotop ncdu tmux
```

### Reboot
```bash
reboot
```

---

## Phase 4: Set Up Storage

### Identify Your Drives

```bash
# SSH back in after reboot
ssh root@192.168.1.50

# List all drives
lsblk -o NAME,SIZE,MODEL,SERIAL

# You should see something like:
# nvme0n1     500G Samsung 970 EVO    (boot drive - Proxmox)
# nvme1n1     2T   Samsung 980 PRO    (cache SSD)
# sda         18T  WDC WD180EDGZ      (data HDD 1)
# sdb         18T  WDC WD180EDGZ      (data HDD 2)
# sdc         18T  WDC WD180EDGZ      (data HDD 3)
# sdd         18T  WDC WD180EDGZ      (parity HDD)
```

### Get Disk IDs (More Reliable Than /dev/sdX)

```bash
ls -la /dev/disk/by-id/ | grep -v part

# Note the full IDs like:
# ata-WDC_WD180EDGZ-11B2DA0_XXXXXXXX
# nvme-Samsung_SSD_980_PRO_2TB_XXXXXXXX
```

### Option A: Pass Drives to VM (Recommended for Unraid-like Flexibility)

We'll pass the raw drives to the Ubuntu VM. This is done after creating the VM.

### Option B: Create ZFS Pool on Proxmox (For ZFS Features)

If you prefer ZFS managed by Proxmox:

```bash
# Create a RAIDZ1 pool (like RAID5 - one drive can fail)
zpool create -o ashift=12 storage raidz1 \
  /dev/disk/by-id/ata-WDC_WD180EDGZ-SERIAL1 \
  /dev/disk/by-id/ata-WDC_WD180EDGZ-SERIAL2 \
  /dev/disk/by-id/ata-WDC_WD180EDGZ-SERIAL3 \
  /dev/disk/by-id/ata-WDC_WD180EDGZ-SERIAL4

# Create datasets
zfs create storage/vms
zfs create storage/backups

# Enable compression
zfs set compression=lz4 storage

# Check status
zpool status
```

For this guide, we'll use **Option A** (pass drives to VM) for maximum flexibility.

---

## Phase 5: Enable iGPU Passthrough

This allows Jellyfin to use Intel Quick Sync for hardware transcoding.

### Edit GRUB

```bash
nano /etc/default/grub

# Find this line:
GRUB_CMDLINE_LINUX_DEFAULT="quiet"

# Change it to:
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
```

Save (Ctrl+O, Enter) and exit (Ctrl+X).

### Update GRUB

```bash
update-grub
```

### Load VFIO Modules

```bash
cat >> /etc/modules << EOF
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
EOF
```

### Update Initramfs and Reboot

```bash
update-initramfs -u -k all
reboot
```

### Verify IOMMU is Enabled

```bash
ssh root@192.168.1.50

# Check for IOMMU
dmesg | grep -e DMAR -e IOMMU
# Should see: "DMAR: IOMMU enabled"

# Find iGPU
lspci -nn | grep VGA
# Example: 00:02.0 VGA compatible controller [0300]: Intel Corporation...
```

---

## Phase 6: Create Ubuntu VM

### Download Ubuntu Server

```bash
cd /var/lib/vz/template/iso/
wget https://releases.ubuntu.com/22.04/ubuntu-22.04.4-live-server-amd64.iso
```

### Create VM via Web UI

1. Go to Proxmox web UI: https://192.168.1.50:8006
2. Click **"Create VM"** (top right)

**General tab:**
- Node: proxmox
- VM ID: 100
- Name: homeserver

**OS tab:**
- ISO image: ubuntu-22.04.4-live-server-amd64.iso
- Type: Linux
- Version: 6.x - 2.6 Kernel

**System tab:**
- Machine: q35
- BIOS: OVMF (UEFI)
- Add EFI Disk: Check
- Storage: local-lvm
- Pre-Enroll keys: Uncheck

**Disks tab:**
- Bus: SCSI
- Storage: local-lvm
- Disk size: 100 GB (for OS + Docker)
- SSD emulation: Check
- Discard: Check

**CPU tab:**
- Cores: 8 (or more if available)
- Type: host

**Memory tab:**
- Memory: 28672 MB (28GB - leave 4GB for Proxmox)
- Ballooning: Uncheck

**Network tab:**
- Bridge: vmbr0
- Model: VirtIO

3. Click **Finish** (don't start yet)

### Add Cache SSD to VM

1. Select VM 100 in left panel
2. Go to **Hardware** tab
3. Click **Add** → **Hard Disk**
   - Bus: SCSI
   - Storage: (select your cache NVMe if added to Proxmox)
   - OR use disk passthrough (next section)

### Pass Through Physical Drives

For each data drive, add via command line:

```bash
# Pass through cache SSD (adjust disk ID)
qm set 100 --scsi1 /dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_XXXXXXXX

# Pass through data HDDs
qm set 100 --scsi2 /dev/disk/by-id/ata-WDC_WD180EDGZ-SERIAL1
qm set 100 --scsi3 /dev/disk/by-id/ata-WDC_WD180EDGZ-SERIAL2
qm set 100 --scsi4 /dev/disk/by-id/ata-WDC_WD180EDGZ-SERIAL3
qm set 100 --scsi5 /dev/disk/by-id/ata-WDC_WD180EDGZ-SERIAL4
```

### Add iGPU Passthrough

```bash
# Add Intel iGPU (check your device ID from earlier)
qm set 100 --hostpci0 0000:00:02.0
```

### Start VM

1. Select VM 100
2. Click **Start**
3. Click **Console** to see the screen

---

## Phase 7: Configure Ubuntu VM

### Install Ubuntu Server

1. In the console, select **"Install Ubuntu Server"**
2. Language: English
3. Keyboard: Your layout
4. Network: Should auto-configure via DHCP
   - Note the IP address shown
5. Proxy: Leave blank
6. Mirror: Default is fine
7. Storage: **Use an entire disk**
   - Select the 100GB virtual disk (NOT the passed-through drives)
8. Confirm destructive action
9. Profile:
   - Your name: homeserver
   - Server name: homeserver
   - Username: homeserver
   - Password: (choose a strong password)
10. SSH: **Install OpenSSH server** ✓
11. Featured snaps: Skip (don't select anything)
12. Wait for installation
13. **Reboot Now**

### First Login

After reboot, login via console or SSH:

```bash
ssh homeserver@<vm-ip-address>
```

### Set Static IP

```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

Replace contents with:
```yaml
network:
  version: 2
  ethernets:
    enp6s18:  # Your interface name (check with 'ip a')
      dhcp4: no
      addresses:
        - 192.168.1.100/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
```

Apply:
```bash
sudo netplan apply
```

Now reconnect with new IP:
```bash
ssh homeserver@192.168.1.100
```

### Update System

```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
```

### Format and Mount Drives

After reboot, SSH back in:

```bash
ssh homeserver@192.168.1.100

# List drives
lsblk

# You should see:
# sda - 100GB (OS)
# sdb - 2TB (cache SSD)
# sdc - 18TB (HDD 1)
# sdd - 18TB (HDD 2)
# sde - 18TB (HDD 3)
# sdf - 18TB (HDD 4)
```

### Format Cache SSD

```bash
# Format as ext4
sudo mkfs.ext4 /dev/sdb

# Create mount point
sudo mkdir -p /mnt/cache

# Get UUID
sudo blkid /dev/sdb
# Note the UUID="xxxxx"

# Add to fstab
echo "UUID=xxxxx /mnt/cache ext4 defaults 0 2" | sudo tee -a /etc/fstab

# Mount
sudo mount -a
```

### Set Up Storage Array with mergerfs + SnapRAID (Unraid-like)

This gives you:
- Drives that are individually readable (unlike RAID)
- Parity protection (one drive can fail)
- Flexibility to add different-sized drives later

```bash
# Install mergerfs and snapraid
sudo apt install -y mergerfs snapraid

# Format data drives as ext4
sudo mkfs.ext4 /dev/sdc
sudo mkfs.ext4 /dev/sdd
sudo mkfs.ext4 /dev/sde
sudo mkfs.ext4 /dev/sdf  # This will be parity

# Create mount points
sudo mkdir -p /mnt/disk{1,2,3}
sudo mkdir -p /mnt/parity
sudo mkdir -p /mnt/storage

# Get UUIDs
sudo blkid

# Add to fstab (replace UUIDs)
cat << 'EOF' | sudo tee -a /etc/fstab

# Data drives
UUID=xxxxx1 /mnt/disk1 ext4 defaults 0 2
UUID=xxxxx2 /mnt/disk2 ext4 defaults 0 2
UUID=xxxxx3 /mnt/disk3 ext4 defaults 0 2

# Parity drive
UUID=xxxxx4 /mnt/parity ext4 defaults 0 2

# MergerFS pool
/mnt/disk* /mnt/storage fuse.mergerfs defaults,allow_other,use_ino,cache.files=partial,dropcacheonclose=true,category.create=mfs 0 0
EOF

# Mount all
sudo mount -a

# Verify
df -h
```

### Configure SnapRAID

```bash
sudo nano /etc/snapraid.conf
```

Add:
```
parity /mnt/parity/snapraid.parity

content /mnt/disk1/.snapraid.content
content /mnt/disk2/.snapraid.content
content /mnt/disk3/.snapraid.content

data d1 /mnt/disk1
data d2 /mnt/disk2
data d3 /mnt/disk3

exclude *.tmp
exclude /tmp/
exclude /lost+found/
```

Initial sync (do this after adding data):
```bash
sudo snapraid sync
```

### Create Directory Structure

```bash
# Cache directories
sudo mkdir -p /mnt/cache/appdata
sudo mkdir -p /mnt/cache/downloads/{complete,incomplete}

# Storage directories
sudo mkdir -p /mnt/storage/media/{movies,tv,music,audiobooks,podcasts,books}
sudo mkdir -p /mnt/storage/photos
sudo mkdir -p /mnt/storage/backups/{timemachine,footage}

# Set ownership
sudo chown -R homeserver:homeserver /mnt/cache
sudo chown -R homeserver:homeserver /mnt/storage
```

### Verify iGPU Access

```bash
ls -la /dev/dri/
# Should see: card0, renderD128

# Check which group owns it
ls -la /dev/dri/renderD128
# Usually 'render' group

# Add your user to render group
sudo usermod -aG render homeserver
```

---

## Phase 8: Install Docker & Deploy Stack

### Install Docker

```bash
# Install Docker
curl -fsSL https://get.docker.com | sudo sh

# Add user to docker group
sudo usermod -aG docker homeserver

# Enable Docker on boot
sudo systemctl enable docker

# Apply group change (or logout/login)
newgrp docker

# Verify
docker --version
docker compose version
```

### Clone Home Server Configuration

```bash
cd ~
git clone <your-repo-url> homeserver
# OR copy files from your local machine:
# scp -r /path/to/homeserver homeserver@192.168.1.100:~/
```

### Configure Environment

```bash
cd ~/homeserver

# Copy example env
cp .env.example .env

# Edit configuration
nano .env
```

**Critical settings to change:**

```bash
# Paths - adjust to match your mounts
CACHE_PATH=/mnt/cache
STORAGE_PATH=/mnt/storage
APPDATA_PATH=/mnt/cache/appdata
DOWNLOADS_PATH=/mnt/cache/downloads
MEDIA_PATH=/mnt/storage/media
PHOTOS_PATH=/mnt/storage/photos
BACKUP_PATH=/mnt/storage/backups

# Timezone
TZ=America/Los_Angeles  # Change to yours

# Mullvad VPN - get from https://mullvad.net/en/account/wireguard-config
WIREGUARD_PRIVATE_KEY=your_actual_key_here
WIREGUARD_ADDRESSES=10.x.x.x/32

# Generate random passwords
IMMICH_DB_PASSWORD=$(openssl rand -base64 32)
IMMICH_REDIS_PASSWORD=$(openssl rand -base64 24)
FIREFLY_DB_PASSWORD=$(openssl rand -base64 32)
FIREFLY_APP_KEY=$(openssl rand -base64 32)

# Domain (if you have one)
DOMAIN=yourdomain.com
```

Save and exit (Ctrl+O, Enter, Ctrl+X).

### Run Setup Script

```bash
sudo ./scripts/setup.sh
```

### Start All Services

```bash
cd ~/homeserver
docker compose up -d
```

First run will download all images (5-15 minutes depending on internet).

### Check Status

```bash
docker compose ps
```

All services should show "running".

---

## Phase 9: Configure Core Services

Access services from your browser at `http://192.168.1.100:PORT`

### 1. AdGuard Home (Port 3000)

**Initial Setup:**
1. Go to http://192.168.1.100:3000
2. Click "Get Started"
3. Admin interface: Listen on all interfaces, port 80
4. DNS server: Listen on all interfaces, port 53
5. Create admin username/password
6. Complete setup

**Configure Blocklists:**
1. Filters → DNS blocklists → Add blocklist
2. Add recommended lists:
   - AdGuard DNS filter
   - AdAway Default Blocklist
   - Steven Black's hosts

**Point Your Network to It:**
1. In your router's DHCP settings
2. Set primary DNS to: 192.168.1.100
3. All devices will now use AdGuard for DNS

### 2. Verify VPN is Working

```bash
# Check Gluetun VPN status
docker exec gluetun curl -s https://am.i.mullvad.net/connected

# Should return: "You are connected to Mullvad..."
```

### 3. qBittorrent (Port 8080)

1. Go to http://192.168.1.100:8080
2. Login: `admin` / `adminadmin`
3. **IMMEDIATELY change password:**
   - Tools → Options → Web UI
   - Change password
4. Configure downloads:
   - Downloads → Save files to: `/downloads/complete`
   - Downloads → Keep incomplete in: `/downloads/incomplete`

---

## Phase 10: Configure Media Stack

### 1. Prowlarr (Port 9696) - Do This First!

**Add Indexers:**
1. Go to http://192.168.1.100:9696
2. Indexers → Add Indexer
3. Search for and add your preferred indexers
4. Configure each with your credentials

**Add Download Client:**
1. Settings → Download Clients → Add
2. Select qBittorrent
3. Host: `gluetun` (NOT localhost!)
4. Port: `8080`
5. Username: `admin`
6. Password: (your new password)
7. Test → Save

**Connect to Apps (do after setting up each app):**
1. Settings → Apps → Add
2. Add Sonarr, Radarr, Lidarr, Readarr one by one

### 2. Radarr (Port 7878)

**Initial Setup:**
1. Go to http://192.168.1.100:7878
2. Settings → Media Management:
   - Add Root Folder: `/media/movies`
   - Enable Rename Movies
3. Settings → Download Clients:
   - Add qBittorrent (same as Prowlarr)
   - Host: `gluetun`, Port: 8080
4. Settings → General:
   - Copy the API Key (needed for Prowlarr + Jellyseerr)

**In Prowlarr:**
1. Settings → Apps → Add → Radarr
2. Prowlarr Server: `http://prowlarr:9696`
3. Radarr Server: `http://radarr:7878`
4. API Key: (paste from Radarr)
5. Test → Save

### 3. Sonarr (Port 8989)

Same process as Radarr:
1. Root Folder: `/media/tv`
2. Download client: qBittorrent via `gluetun:8080`
3. Copy API key, add to Prowlarr

### 4. Lidarr (Port 8686)

Same process:
1. Root Folder: `/media/music`
2. Add to Prowlarr

### 5. Readarr (Port 8787)

Same process:
1. Root Folder: `/media/audiobooks` or `/media/books`
2. Add to Prowlarr

### 6. Bazarr (Port 6767)

**Configure Subtitle Providers:**
1. Go to http://192.168.1.100:6767
2. Settings → Providers
3. Add providers (OpenSubtitles, Subscene, etc.)
4. Settings → Sonarr:
   - Enable, Host: `sonarr`, Port: 8989
   - API Key from Sonarr
5. Settings → Radarr:
   - Enable, Host: `radarr`, Port: 7878
   - API Key from Radarr

### 7. Jellyfin (Port 8096)

**Initial Setup:**
1. Go to http://192.168.1.100:8096
2. Select language
3. Create admin account
4. Add libraries:
   - Movies: `/media/movies`
   - Shows: `/media/tv`
   - Music: `/media/music`
5. Set metadata language
6. Configure remote access (enable if needed)

**Enable Hardware Transcoding:**
1. Dashboard → Playback
2. Hardware acceleration: Intel QuickSync (QSV)
3. Enable: H264, HEVC, VP9 decoding
4. Enable: H264, HEVC encoding

### 8. Jellyseerr (Port 5055)

**Connect to Jellyfin:**
1. Go to http://192.168.1.100:5055
2. Sign in with Jellyfin
3. Enter Jellyfin URL: `http://jellyfin:8096`
4. Authenticate with admin account

**Connect to Radarr:**
1. Add Radarr server
2. Hostname: `radarr`
3. Port: 7878
4. API Key: (from Radarr)
5. Select quality profile and root folder

**Connect to Sonarr:**
1. Same process
2. Hostname: `sonarr`
3. Port: 8989

### 9. Recyclarr

Configure quality profiles:
```bash
nano /mnt/cache/appdata/recyclarr/recyclarr.yml
```

Add your Sonarr/Radarr API keys, then:
```bash
docker exec recyclarr recyclarr sync
```

---

## Phase 11: Configure Other Services

### Immich (Port 2283)

1. Go to http://192.168.1.100:2283
2. Click "Getting Started"
3. Create admin account
4. Download mobile app
5. In app: Add server http://192.168.1.100:2283

### Home Assistant (Port 8123)

1. Go to http://192.168.1.100:8123
2. Create account
3. Set location/timezone
4. Discover devices

### Vaultwarden (Port 8222)

1. Go to http://192.168.1.100:8222
2. Create account (first user = admin)
3. After setup, disable signups in `.env`:
   ```
   SIGNUPS_ALLOWED=false
   ```
4. Restart: `docker compose up -d vaultwarden`

### Firefly III (Port 8223)

1. Go to http://192.168.1.100:8223
2. Register account
3. Set up bank accounts, budgets

### Audiobookshelf (Port 13378)

1. Go to http://192.168.1.100:13378
2. Create admin account
3. Add libraries:
   - Audiobooks: `/audiobooks`
   - Podcasts: `/podcasts`

### OctoPrint (Port 5000)

Only configure if you have a 3D printer connected:
1. Pass through USB in Proxmox (VM → Hardware → Add → USB)
2. Restart VM
3. Update docker-compose device mapping
4. Go to http://192.168.1.100:5000

### Uptime Kuma (Port 3001)

1. Go to http://192.168.1.100:3001
2. Create admin account
3. Add monitors for each service

### Homepage (Port 3002)

1. Edit config files in `/mnt/cache/appdata/homepage/`
2. Add API keys for each service
3. Restart: `docker compose restart homepage`

---

## Phase 12: Final Setup & Testing

### Test Media Request Flow

1. Go to Jellyseerr: http://192.168.1.100:5055
2. Search for a movie
3. Click Request
4. Watch it flow through:
   - Jellyseerr → Radarr
   - Radarr → Prowlarr → Indexers
   - Radarr → qBittorrent
   - qBittorrent downloads through VPN
   - Radarr imports and renames
   - Bazarr downloads subtitles
5. Check Jellyfin - movie should appear

### Configure Time Machine

On your Mac:
1. System Settings → General → Time Machine
2. Add Backup Disk
3. Select "homeserver" (should auto-discover)
4. Enter credentials: homeserver / (samba password from .env)

### Set Up Mobile Apps

**Jellyfin:**
- iOS: Download Jellyfin app
- Add server: http://192.168.1.100:8096

**Immich:**
- iOS: Download Immich app
- Add server: http://192.168.1.100:2283

**Audiobookshelf:**
- iOS: Download Audiobookshelf app
- Add server: http://192.168.1.100:13378

### Set Up Remote Access (Optional)

**Option A: Tailscale (Easiest)**
```bash
# On server
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```
Install Tailscale on phone/laptop, same account. Access via Tailscale IPs.

**Option B: Cloudflare Tunnel (No ports to open)**
1. Add domain to Cloudflare
2. Install cloudflared
3. Create tunnel
4. Route subdomains to local services

### Create Backup Schedule

```bash
# Edit crontab
crontab -e

# Add daily backup at 3am
0 3 * * * /home/homeserver/homeserver/scripts/backup.sh >> /var/log/backup.log 2>&1

# Add weekly SnapRAID sync on Sunday at 4am
0 4 * * 0 /usr/bin/snapraid sync >> /var/log/snapraid.log 2>&1
```

### Final Checklist

- [ ] VPN connected (`docker exec gluetun curl https://am.i.mullvad.net/connected`)
- [ ] Can request movie in Jellyseerr
- [ ] Movie downloads and appears in Jellyfin
- [ ] Subtitles download automatically
- [ ] Photos upload to Immich from phone
- [ ] Time Machine backup works
- [ ] AdGuard blocking ads (check stats)
- [ ] All services show in Uptime Kuma
- [ ] Hardware transcoding works in Jellyfin

---

## Quick Reference

### Service URLs

| Service | URL | Purpose |
|---------|-----|---------|
| **Jellyseerr** | :5055 | Request movies/shows |
| **Jellyfin** | :8096 | Watch media |
| **Homepage** | :3002 | Dashboard |
| Prowlarr | :9696 | Indexer management |
| Sonarr | :8989 | TV automation |
| Radarr | :7878 | Movie automation |
| Bazarr | :6767 | Subtitles |
| qBittorrent | :8080 | Downloads |
| Immich | :2283 | Photos |
| Home Assistant | :8123 | Smart home |
| AdGuard | :3000 | DNS ad blocking |
| Vaultwarden | :8222 | Passwords |
| Firefly III | :8223 | Finance |
| Uptime Kuma | :3001 | Monitoring |

### Common Commands

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# View logs
docker compose logs -f <service-name>

# Update all containers
docker compose pull && docker compose up -d

# Restart specific service
docker compose restart jellyfin

# Check VPN
docker exec gluetun curl https://am.i.mullvad.net/connected

# Backup
./scripts/backup.sh

# SnapRAID sync
sudo snapraid sync
```

---

## Troubleshooting

### Service won't start
```bash
docker compose logs <service-name>
```

### VPN not connecting
1. Check credentials in .env
2. `docker compose logs gluetun`

### Can't access from other devices
1. Check firewall: `sudo ufw status`
2. Ensure services bind to 0.0.0.0

### iGPU transcoding not working
1. Verify `/dev/dri` exists in VM
2. Check Jellyfin logs
3. Ensure user is in `render` group

### Downloads stuck
1. Check qBittorrent for errors
2. Verify VPN is connected
3. Check disk space

---

Congratulations! Your home server is now fully operational. 🎉
