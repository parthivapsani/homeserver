# Home Server

A comprehensive, self-hosted home server running on Proxmox with Docker.

## Features

- **Media Automation**: Sonarr, Radarr, Lidarr, Readarr, Prowlarr
- **Media Streaming**: Jellyfin with Live TV/DVR support
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

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              NETWORK LAYER                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  AdGuard Home (DNS)  │  Traefik (Reverse Proxy)  │  Tailscale (VPN Access)  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GLUETUN (Mullvad VPN Container)                     │
├──────────────────┬──────────────────┬───────────────────────────────────────┤
│   qBittorrent    │     SABnzbd      │              Prowlarr                 │
└──────────────────┴──────────────────┴───────────────────────────────────────┘
                                      │
┌─────────────────────────────────────────────────────────────────────────────┐
│                           MEDIA AUTOMATION                                  │
├────────────┬────────────┬────────────┬────────────┬─────────────────────────┤
│   Sonarr   │   Radarr   │   Lidarr   │  Readarr   │    Audiobookshelf       │
└────────────┴────────────┴────────────┴────────────┴─────────────────────────┘
                                      │
┌─────────────────────────────────────────────────────────────────────────────┐
│                           MEDIA & PHOTOS                                    │
├─────────────────────┬─────────────────────┬─────────────────────────────────┤
│      Jellyfin       │     Jellyfin DVR    │           Immich                │
└─────────────────────┴─────────────────────┴─────────────────────────────────┘
                                      │
┌─────────────────────────────────────────────────────────────────────────────┐
│                           HOME AUTOMATION                                   │
├─────────────────────┬─────────────────────┬─────────────────────────────────┤
│   Home Assistant    │      Mosquitto      │          OctoPrint              │
└─────────────────────┴─────────────────────┴─────────────────────────────────┘
                                      │
┌─────────────────────────────────────────────────────────────────────────────┐
│                              UTILITIES                                      │
├────────────────┬────────────────┬───────────────────────────────────────────┤
│  Vaultwarden   │  Firefly III   │           Samba (NAS/Time Machine)        │
└────────────────┴────────────────┴───────────────────────────────────────────┘
```

## Hardware Requirements

| Component | Recommended |
|-----------|-------------|
| CPU | Intel Core i5-12400 or i5-13400 (Quick Sync for transcoding) |
| RAM | 64GB DDR4 |
| Boot SSD | 500GB NVMe |
| Cache SSD | 1-2TB NVMe |
| Media HDDs | 3-4x 12-18TB |
| Parity HDD | 1x matching size |
| Network | 2.5GbE |
| UPS | 750VA+ |

## Quick Start

### 1. Proxmox VM Setup

Create a VM or LXC container with:
- Ubuntu Server 22.04 LTS or Debian 12
- 8+ CPU cores
- 64GB RAM
- Passthrough storage drives
- Intel iGPU passthrough (for Jellyfin transcoding)

### 2. Clone and Configure

```bash
# Clone this repository
git clone <your-repo-url> ~/homeserver
cd ~/homeserver

# Copy and edit environment file
cp .env.example .env
nano .env
```

### 3. Configure .env

Edit `.env` with your settings:

```bash
# Required: Update these paths to match your mount points
CACHE_PATH=/mnt/cache
STORAGE_PATH=/mnt/storage

# Required: Mullvad VPN credentials
# Get from: https://mullvad.net/en/account/wireguard-config
WIREGUARD_PRIVATE_KEY=your_key_here
WIREGUARD_ADDRESSES=10.x.x.x/32

# Required: Generate secure passwords
IMMICH_DB_PASSWORD=$(openssl rand -base64 32)
FIREFLY_DB_PASSWORD=$(openssl rand -base64 32)
FIREFLY_APP_KEY=$(openssl rand -base64 32)

# Optional: Domain for remote access
DOMAIN=yourdomain.com
CF_API_TOKEN=your_cloudflare_token
```

### 4. Run Setup Script

```bash
sudo chmod +x scripts/setup.sh
sudo ./scripts/setup.sh
```

### 5. Start Services

```bash
# Start everything
docker compose up -d

# Or start specific services
docker compose up -d jellyfin sonarr radarr

# View logs
docker compose logs -f jellyfin
```

## Service URLs

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| AdGuard Home | http://server-ip:3000 | Set on first visit |
| Jellyfin | http://server-ip:8096 | Set on first visit |
| Sonarr | http://server-ip:8989 | None (set API key) |
| Radarr | http://server-ip:7878 | None (set API key) |
| Lidarr | http://server-ip:8686 | None (set API key) |
| Readarr | http://server-ip:8787 | None (set API key) |
| Prowlarr | http://server-ip:9696 | None (set API key) |
| qBittorrent | http://server-ip:8080 | admin / adminadmin |
| SABnzbd | http://server-ip:8081 | Set on first visit |
| Immich | http://server-ip:2283 | First user is admin |
| Home Assistant | http://server-ip:8123 | Set on first visit |
| Vaultwarden | http://server-ip:8222 | First user is admin |
| Firefly III | http://server-ip:8223 | Set on first visit |
| OctoPrint | http://server-ip:5000 | Set on first visit |
| Audiobookshelf | http://server-ip:13378 | Set on first visit |
| Traefik Dashboard | http://server-ip:8080 | None |

## Post-Installation

### 1. Configure AdGuard Home

1. Visit http://server-ip:3000
2. Complete setup wizard
3. Set your router's DHCP to use server IP as DNS

### 2. Set Up *arr Apps

1. **Prowlarr** (first): Add indexers
2. **Prowlarr**: Add Sonarr, Radarr, Lidarr, Readarr as apps
3. Each *arr app: Add qBittorrent/SABnzbd as download client
   - Host: `gluetun` (container name, not localhost!)
   - Port: 8080 for qBittorrent, 8081 for SABnzbd

### 3. Configure Jellyfin

1. Complete setup wizard
2. Add media libraries pointing to `/media/movies`, `/media/tv`, etc.
3. Enable hardware transcoding:
   - Settings → Playback → Transcoding
   - Hardware acceleration: Intel QuickSync

### 4. Live TV Setup (Optional)

1. Install HDHomeRun and connect antenna
2. In Jellyfin: Settings → Live TV → Add Tuner
3. Type: HDHomeRun, URL: http://HDHR_IP
4. Add TV Guide: Use zap2xml container output at `/tvguide/xmltv.xml`

### 5. Time Machine Setup

1. On Mac: System Preferences → Time Machine
2. Select Disk → HomeServer (should auto-discover)
3. Enter Samba credentials (default: homeserver / changeme123)

### 6. Secure Vaultwarden

After creating your admin account:
```bash
# Edit compose/utilities.yml
# Change: SIGNUPS_ALLOWED=false
docker compose up -d vaultwarden
```

## Folder Structure

```
/mnt/
├── cache/                    # SSD - Fast storage
│   ├── appdata/              # Container configs/databases
│   │   ├── adguard/
│   │   ├── jellyfin/
│   │   ├── sonarr/
│   │   └── ...
│   └── downloads/            # Temporary downloads
│       ├── complete/
│       └── incomplete/
│
└── storage/                  # HDD Array - Bulk storage
    ├── media/
    │   ├── movies/
    │   ├── tv/
    │   ├── music/
    │   ├── audiobooks/
    │   └── podcasts/
    ├── photos/               # Immich library
    └── backups/
        ├── timemachine/
        └── footage/
```

## Maintenance

### Update All Containers

```bash
docker compose pull
docker compose up -d
```

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f jellyfin
```

### Backup

Important directories to backup:
- `/mnt/cache/appdata/` - All container configurations
- Database volumes (immich_postgres, firefly_postgres)

### Check VPN Status

```bash
# Verify VPN is connected
docker exec gluetun curl -s https://am.i.mullvad.net/connected

# Should return: "You are connected to Mullvad..."
```

## Troubleshooting

### Containers Can't Connect to Each Other

Ensure they're on the same network and use container names (not localhost):
- qBittorrent host in Sonarr: `gluetun` (not `localhost`)

### VPN Not Connecting

1. Check Gluetun logs: `docker compose logs gluetun`
2. Verify WireGuard credentials in `.env`
3. Ensure `/dev/net/tun` exists

### Jellyfin Transcoding Not Working

1. Verify iGPU passthrough in Proxmox
2. Check render group ID: `getent group render`
3. Update `group_add` in compose/media.yml

### Time Machine Not Discovering Server

1. Ensure Avahi container is running
2. Check `timemachine.service` file is mounted
3. Verify Samba share has `fruit:time machine = yes`

## Costs

### One-Time
- Server hardware: ~$1,200-1,500
- HDHomeRun (optional): ~$110-150
- Antenna (optional): ~$30

### Recurring
- Mullvad VPN: ~$60/year
- Domain (optional): ~$12/year
- Electricity: ~$60-180/year

**Total: ~$130-250/year** (all software is free and open source)

## Adding New Services

1. Create a new compose file in `compose/` or add to existing one
2. Follow the pattern:
```yaml
new-service:
  image: whatever/service:latest
  container_name: new-service
  restart: unless-stopped
  networks:
    - homeserver
  environment:
    - PUID=${PUID}
    - PGID=${PGID}
    - TZ=${TZ}
  volumes:
    - ${APPDATA_PATH}/new-service:/config
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.new-service.rule=Host(`new-service.${DOMAIN}`)"
    - "traefik.http.routers.new-service.entrypoints=websecure"
    - "traefik.http.routers.new-service.tls.certresolver=cloudflare"
```

3. Add to `include` list in main `docker-compose.yml` if new file
4. Run `docker compose up -d new-service`

## License

This configuration is provided as-is for personal use.
