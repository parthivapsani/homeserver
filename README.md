# Home Server

A comprehensive, self-hosted home server running on Proxmox with Docker.

## Features

- **Media Automation**: Sonarr, Radarr, Lidarr, Readarr, Prowlarr, Bazarr
- **Media Streaming**: Jellyfin with hardware transcoding + Live TV/DVR
- **Media Requests**: Jellyseerr (Netflix-like request interface)
- **Photo Management**: Immich (Google Photos alternative)
- **Audiobooks/Podcasts**: Audiobookshelf
- **DNS Ad Blocking**: AdGuard Home
- **Password Manager**: Vaultwarden (Bitwarden-compatible)
- **Personal Finance**: Firefly III
- **Smart Home**: Home Assistant, Mosquitto MQTT
- **3D Printing**: OctoPrint
- **File Sharing**: Samba with Time Machine support
- **VPN Protection**: Mullvad via Gluetun (kill switch enabled)
- **Reverse Proxy**: Traefik with automatic SSL
- **Monitoring**: Uptime Kuma, Homepage dashboard
- **UPS Integration**: NUT for graceful shutdown on power loss

## Architecture Options

### Recommended: LXC Containers (Better Performance)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PROXMOX VE HOST                                 │
├─────────────────────────────────────────────────────────────────────────┤
│  LXC 100: media-stack (16GB)     │  LXC 101: photos-backup (8GB)       │
│  Jellyfin, *arr, Jellyseerr,     │  Immich, Samba, Avahi               │
│  qBittorrent, Gluetun            │                                      │
├──────────────────────────────────┼──────────────────────────────────────┤
│  LXC 102: core-services (4GB)    │  Storage: ZFS or SnapRAID+MergerFS  │
│  AdGuard, Home Assistant,        │  UPS: NUT daemon                     │
│  Vaultwarden, Firefly III        │                                      │
└─────────────────────────────────────────────────────────────────────────┘
```

**Benefits**: 20-30% faster, 100-140 MB/s SMB (vs 60-90 with VM), simpler iGPU access

### Alternative: Single Ubuntu VM

Traditional approach with all services in one VM. Simpler but less efficient.

## Hardware Requirements

| Component | Recommended | Notes |
|-----------|-------------|-------|
| CPU | Intel Core i5-12400/13400 | Quick Sync for transcoding |
| RAM | **32GB DDR4** | 64GB only if running multiple VMs or ZFS |
| Boot SSD | 500GB NVMe | Proxmox OS |
| Cache SSD | 1-2TB NVMe | Docker appdata, downloads |
| Media HDDs | 3-4x 12-18TB | Movies, TV, photos |
| Parity HDD | 1x matching size | SnapRAID parity |
| Network | 1GbE or 2.5GbE | 1GbE sufficient for most use cases |
| UPS | 750VA+ | ~15 min runtime, USB for NUT |

### RAM Breakdown

| Component | Usage |
|-----------|-------|
| Proxmox host | 2GB |
| Immich ML | 4GB |
| Jellyfin (transcoding) | 2GB |
| *arr stack (all 5) | 2GB |
| Databases | 1.5GB |
| Other services | 2.5GB |
| **Total active** | **~14GB** |
| **Recommended** | **32GB** (headroom) |

### Power Consumption

| State | Usage | Annual Cost (@ $0.12/kWh) |
|-------|-------|---------------------------|
| Idle | 40-60W | $42-63 |
| Active (transcoding) | 80-120W | — |
| **Estimated average** | **60-80W** | **$63-84/year** |

## Quick Start

### Option 1: LXC Containers (Recommended)

See [docs/LXC_ARCHITECTURE.md](docs/LXC_ARCHITECTURE.md) for detailed instructions.

### Option 2: Single VM

See [docs/COMPLETE_SETUP_GUIDE.md](docs/COMPLETE_SETUP_GUIDE.md) for the full walkthrough.

### Basic Steps

```bash
# Clone this repository
git clone https://github.com/parthivapsani/homeserver.git
cd homeserver

# Copy and edit environment file
cp .env.example .env
nano .env

# Run setup script
sudo ./scripts/setup.sh

# Start services
docker compose up -d
```

## Documentation

| Guide | Description |
|-------|-------------|
| [COMPLETE_SETUP_GUIDE.md](docs/COMPLETE_SETUP_GUIDE.md) | Full walkthrough from hardware to working server |
| [LXC_ARCHITECTURE.md](docs/LXC_ARCHITECTURE.md) | Recommended LXC-based setup (better performance) |
| [HOW_TO_REQUEST_MEDIA.md](docs/HOW_TO_REQUEST_MEDIA.md) | How to request and download movies/shows |
| [PROXMOX_SETUP.md](docs/PROXMOX_SETUP.md) | Proxmox installation and iGPU passthrough |
| [UPS_CONFIGURATION.md](docs/UPS_CONFIGURATION.md) | UPS integration for graceful shutdown |

## Service URLs

| Service | Port | Purpose |
|---------|------|---------|
| **Jellyseerr** | 5055 | Request movies/shows |
| **Jellyfin** | 8096 | Watch media |
| **Homepage** | 3002 | Dashboard |
| Sonarr | 8989 | TV automation |
| Radarr | 7878 | Movie automation |
| Lidarr | 8686 | Music automation |
| Readarr | 8787 | Book automation |
| Prowlarr | 9696 | Indexer management |
| Bazarr | 6767 | Subtitles |
| qBittorrent | 8080 | Downloads |
| Immich | 2283 | Photos |
| Home Assistant | 8123 | Smart home |
| AdGuard Home | 3000 | DNS ad blocking |
| Vaultwarden | 8222 | Passwords |
| Firefly III | 8223 | Finance |
| Audiobookshelf | 13378 | Audiobooks |
| Uptime Kuma | 3001 | Monitoring |
| OctoPrint | 5000 | 3D printing |

## Costs

### One-Time

| Item | Cost |
|------|------|
| Server hardware (32GB RAM) | ~$1,000-1,200 |
| HDHomeRun (optional) | ~$110-150 |
| Antenna (optional) | ~$30 |
| UPS 750VA | ~$90-150 |

### Recurring

| Item | Annual Cost |
|------|-------------|
| Mullvad VPN | ~$60 |
| Domain (optional) | ~$12 |
| Electricity | ~$65-85 |
| **Total** | **~$140-160/year** |

## iGPU Transcoding Fallback

If Intel Quick Sync passthrough fails (~30-40% of cases on 12th gen):

1. In Jellyfin: Dashboard → Playback → Transcoding
2. Set Hardware acceleration to **None**
3. Enable throttling
4. Set max concurrent transcodes to **2**

CPU-only limits:
- 1-2 concurrent 4K→1080p transcodes
- 3-4 concurrent 1080p→720p transcodes
- Unlimited direct play

## SnapRAID Best Practices

To minimize data loss risk:

```bash
# Run sync twice daily (cron)
0 3,15 * * * /usr/bin/snapraid sync >> /var/log/snapraid.log 2>&1

# Weekly scrub for bitrot detection
0 4 * * 0 /usr/bin/snapraid scrub -p 10 >> /var/log/snapraid.log 2>&1
```

**Important**: Files deleted between syncs are vulnerable. Consider ZFS if you need real-time protection.

## Maintenance

```bash
# Update all containers
./scripts/update.sh

# Backup configurations
./scripts/backup.sh

# Check VPN status
docker exec gluetun curl -s https://am.i.mullvad.net/connected

# SnapRAID sync
sudo snapraid sync

# SnapRAID status
sudo snapraid status
```

## Troubleshooting

### Jellyfin Transcoding Not Working

1. Check iGPU access: `ls -la /dev/dri/`
2. Verify render group: `getent group render`
3. Test Quick Sync: `vainfo`
4. If fails, use CPU fallback (see above)

### VPN Not Connecting

1. Check logs: `docker compose logs gluetun`
2. Verify WireGuard credentials
3. Ensure `/dev/net/tun` exists

### SMB Slow Performance

- VM approach: Limited to 60-90 MB/s
- LXC approach: Achieves 100-140 MB/s
- Consider migrating to LXC architecture

### UPS Not Detected

```bash
# Check USB connection
lsusb | grep -i ups

# Test NUT
upsc myups
```

## License

This configuration is provided as-is for personal use.
