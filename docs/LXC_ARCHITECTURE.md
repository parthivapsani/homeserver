# LXC Container Architecture (Recommended)

This guide replaces the Ubuntu VM approach with Proxmox LXC containers for better performance.

## Why LXC Instead of VM?

| Metric | VM + Docker | LXC + Docker |
|--------|-------------|--------------|
| Performance overhead | 20-30% | 5-10% |
| RAM needed | 60GB | 32GB |
| Container startup | 15-20 sec | 2-3 sec |
| SMB throughput | 60-90 MB/s | 100-140 MB/s |
| iGPU passthrough | Complex, ~60% success | Simple /dev/dri bind mount |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PROXMOX VE HOST                                 │
│  (Manages LXC containers, storage, networking, UPS shutdown)            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  LXC 100: media-stack (16GB RAM)                                │   │
│  │  ────────────────────────────────────────────────────────────── │   │
│  │  Jellyfin, Sonarr, Radarr, Lidarr, Readarr, Bazarr,            │   │
│  │  Jellyseerr, qBittorrent, Prowlarr, Gluetun, Recyclarr         │   │
│  │  + iGPU access via /dev/dri bind mount                          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  LXC 101: photos-backup (8GB RAM)                               │   │
│  │  ────────────────────────────────────────────────────────────── │   │
│  │  Immich (server, ML, Redis, Postgres), Samba, Avahi             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  LXC 102: core-services (4GB RAM)                               │   │
│  │  ────────────────────────────────────────────────────────────── │   │
│  │  AdGuard, Home Assistant, Vaultwarden, Firefly III,             │   │
│  │  Uptime Kuma, Homepage, Audiobookshelf, Mosquitto               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Storage: ZFS or SnapRAID+MergerFS                              │   │
│  │  UPS: NUT daemon for graceful shutdown                          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## RAM Requirements (Revised)

| Component | Actual Usage |
|-----------|-------------|
| Proxmox host | 2GB |
| Immich ML | 4GB |
| Jellyfin (transcoding) | 2GB |
| *arr stack (all 5) | 2GB |
| Databases (Postgres, Redis) | 1.5GB |
| All other services | 2.5GB |
| **Total active** | **~14GB** |
| **Recommended** | **32GB** (headroom for spikes) |

64GB is only needed if you plan to run multiple VMs, use ZFS with large ARC cache, or run additional workloads.

---

## Phase 1: Create Media Stack LXC (Container 100)

### Create Container

In Proxmox web UI:
1. Click **Create CT**
2. **General**:
   - CT ID: 100
   - Hostname: media-stack
   - Password: (set strong password)
   - Unprivileged: **Uncheck** (needed for /dev/dri access)
3. **Template**: debian-12-standard or ubuntu-22.04-standard
4. **Disks**: 50GB on fast storage
5. **CPU**: 6 cores
6. **Memory**: 16384 MB (16GB)
7. **Network**: vmbr0, DHCP or static IP

### Configure LXC for Docker + iGPU

SSH into Proxmox host:

```bash
# Edit container config
nano /etc/pve/lxc/100.conf
```

Add these lines:

```bash
# Enable nesting for Docker
features: nesting=1

# iGPU passthrough (Intel Quick Sync)
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir

# TUN device for VPN (Gluetun)
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,optional,create=file

# Mount storage (adjust paths)
mp0: /mnt/storage,mp=/mnt/storage
mp1: /mnt/cache,mp=/mnt/cache
```

### Start and Configure Container

```bash
# Start container
pct start 100

# Enter container
pct enter 100

# Update and install Docker
apt update && apt upgrade -y
curl -fsSL https://get.docker.com | sh

# Verify iGPU access
ls -la /dev/dri/
# Should show: card0, renderD128

# Check render group
getent group render
# Add docker user to render group
usermod -aG render root
```

### Deploy Media Stack

```bash
# Clone config
cd /root
git clone https://github.com/parthivapsani/homeserver.git
cd homeserver

# Copy and edit env
cp .env.example .env
nano .env

# Update paths for LXC
# CACHE_PATH=/mnt/cache
# STORAGE_PATH=/mnt/storage
# etc.

# Start media services only
docker compose -f compose/vpn-downloads.yml -f compose/media.yml -f compose/requests.yml up -d
```

---

## Phase 2: Create Photos/Backup LXC (Container 101)

### Create Container

Same process, but:
- CT ID: 101
- Hostname: photos-backup
- Memory: 8192 MB (8GB)
- CPU: 4 cores

### Configure for Samba

```bash
nano /etc/pve/lxc/101.conf
```

Add:
```bash
features: nesting=1

# Storage mounts
mp0: /mnt/storage,mp=/mnt/storage
mp1: /mnt/cache,mp=/mnt/cache
```

### Deploy

```bash
pct start 101
pct enter 101

apt update && apt upgrade -y
curl -fsSL https://get.docker.com | sh

cd /root
git clone https://github.com/parthivapsani/homeserver.git
cd homeserver
cp .env.example .env
nano .env

# Start photos and backup services
docker compose -f compose/photos.yml -f compose/utilities.yml up -d
```

---

## Phase 3: Create Core Services LXC (Container 102)

### Create Container

- CT ID: 102
- Hostname: core-services
- Memory: 4096 MB (4GB)
- CPU: 2 cores

### Configure

```bash
nano /etc/pve/lxc/102.conf
```

Add:
```bash
features: nesting=1

# For Home Assistant device discovery
lxc.cgroup2.devices.allow: a
lxc.cap.drop:

# Storage
mp0: /mnt/cache/appdata,mp=/mnt/cache/appdata
```

### Deploy

```bash
pct start 102
pct enter 102

apt update && apt upgrade -y
curl -fsSL https://get.docker.com | sh

cd /root
git clone https://github.com/parthivapsani/homeserver.git
cd homeserver
cp .env.example .env
nano .env

# Start core services
docker compose -f compose/core.yml -f compose/home-automation.yml -f compose/monitoring.yml up -d
```

---

## iGPU Passthrough Verification

Inside the media-stack container:

```bash
# Check device exists
ls -la /dev/dri/

# Install vainfo to test
apt install vainfo

# Test Quick Sync
vainfo
# Should show:
# vainfo: VA-API version: 1.xx
# vainfo: Driver version: Intel iHD driver
# vainfo: Supported profile and entrypoints (many listed)
```

### If iGPU Fails - CPU Fallback

If you see errors or no /dev/dri, configure Jellyfin for CPU transcoding:

1. In Jellyfin: Dashboard → Playback → Transcoding
2. Hardware acceleration: **None**
3. Throttle transcodes: Enable
4. Max concurrent transcodes: **2** (for i5-12400)

CPU-only limitations:
- 1-2 concurrent 4K→1080p transcodes
- 3-4 concurrent 1080p→720p transcodes
- Direct play has no limit

---

## Container Management

### Useful Commands

```bash
# List containers
pct list

# Start/stop
pct start 100
pct stop 100

# Enter container shell
pct enter 100

# View container resources
pct status 100

# Snapshot before updates
pct snapshot 100 pre-update

# Rollback if needed
pct rollback 100 pre-update
```

### Resource Monitoring

From Proxmox web UI: Datacenter → [node] → [container] → Summary

Or via CLI:
```bash
# Container stats
pct exec 100 -- free -h
pct exec 100 -- docker stats --no-stream
```

---

## Networking Between Containers

All containers on vmbr0 can communicate. Use container hostnames or IPs:

| Container | Hostname | IP (example) |
|-----------|----------|--------------|
| media-stack | media-stack | 192.168.1.100 |
| photos-backup | photos-backup | 192.168.1.101 |
| core-services | core-services | 192.168.1.102 |

For cross-container communication (e.g., Jellyseerr → Radarr), use the container IP, not localhost.

---

## Backup LXC Containers

Proxmox has built-in backup:

1. Datacenter → Backup → Add
2. Schedule: Daily
3. Selection mode: Include selected VMs/CTs
4. Select: 100, 101, 102
5. Storage: Your backup location
6. Mode: Snapshot (minimal downtime)

Or via CLI:
```bash
# Backup all containers
vzdump 100 101 102 --storage local --mode snapshot --compress zstd
```
