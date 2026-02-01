#!/bin/bash
# =============================================================================
# HOME SERVER INITIAL SETUP SCRIPT
# =============================================================================
# Run this script on your Proxmox VM/LXC to set up the directory structure
# and prepare for running Docker containers.
#
# Usage: sudo ./setup.sh
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Home Server Setup Script${NC}"
echo -e "${GREEN}=========================================${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root (use sudo)${NC}"
   exit 1
fi

# Configuration - adjust these paths to match your setup
CACHE_PATH="/mnt/cache"
STORAGE_PATH="/mnt/storage"
APPDATA_PATH="${CACHE_PATH}/appdata"
DOWNLOADS_PATH="${CACHE_PATH}/downloads"
MEDIA_PATH="${STORAGE_PATH}/media"
PHOTOS_PATH="${STORAGE_PATH}/photos"
BACKUP_PATH="${STORAGE_PATH}/backups"

# User/Group IDs - should match your .env file
PUID=1000
PGID=1000

echo -e "\n${YELLOW}Creating directory structure...${NC}"

# Create appdata directories for all services
mkdir -p ${APPDATA_PATH}/{adguard,audiobookshelf,avahi,firefly/upload,gluetun,homeassistant}
mkdir -p ${APPDATA_PATH}/{immich/model-cache,jellyfin/{cache,tvguide},lidarr,mosquitto/config}
mkdir -p ${APPDATA_PATH}/{octoprint,prowlarr,qbittorrent,radarr,readarr,sabnzbd}
mkdir -p ${APPDATA_PATH}/{sonarr,traefik,vaultwarden,zigbee2mqtt}
mkdir -p ${APPDATA_PATH}/{jellyseerr,bazarr,recyclarr,uptime-kuma,homepage}

# Create downloads directories
mkdir -p ${DOWNLOADS_PATH}/{complete,incomplete}
mkdir -p ${DOWNLOADS_PATH}/complete/{movies,tv,music,audiobooks,books}

# Create media directories
mkdir -p ${MEDIA_PATH}/{movies,tv,music,audiobooks,podcasts,books}

# Create photos directory
mkdir -p ${PHOTOS_PATH}

# Create backup directories
mkdir -p ${BACKUP_PATH}/{timemachine,footage}

echo -e "${GREEN}Directory structure created!${NC}"

echo -e "\n${YELLOW}Setting permissions...${NC}"

# Set ownership
chown -R ${PUID}:${PGID} ${CACHE_PATH}
chown -R ${PUID}:${PGID} ${STORAGE_PATH}

# Create Traefik acme.json with correct permissions
touch ${APPDATA_PATH}/traefik/acme.json
chmod 600 ${APPDATA_PATH}/traefik/acme.json
chown ${PUID}:${PGID} ${APPDATA_PATH}/traefik/acme.json

echo -e "${GREEN}Permissions set!${NC}"

echo -e "\n${YELLOW}Copying configuration files...${NC}"

# Copy Mosquitto config if it doesn't exist
if [[ ! -f ${APPDATA_PATH}/mosquitto/config/mosquitto.conf ]]; then
    cp ../config/mosquitto/mosquitto.conf ${APPDATA_PATH}/mosquitto/config/
    echo "Mosquitto config copied"
fi

# Copy Avahi service if it doesn't exist
if [[ ! -f ${APPDATA_PATH}/avahi/timemachine.service ]]; then
    cp ../config/avahi/timemachine.service ${APPDATA_PATH}/avahi/
    echo "Avahi Time Machine service copied"
fi

# Copy Homepage config if it doesn't exist
if [[ ! -f ${APPDATA_PATH}/homepage/services.yaml ]]; then
    cp ../config/homepage/*.yaml ${APPDATA_PATH}/homepage/ 2>/dev/null || true
    echo "Homepage config copied"
fi

# Copy Recyclarr config if it doesn't exist
if [[ ! -f ${APPDATA_PATH}/recyclarr/recyclarr.yml ]]; then
    cp ../config/recyclarr/recyclarr.yml ${APPDATA_PATH}/recyclarr/
    echo "Recyclarr config copied (remember to add API keys!)"
fi

echo -e "${GREEN}Configuration files copied!${NC}"

echo -e "\n${YELLOW}Installing Docker (if not present)...${NC}"

if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker $(logname)
    systemctl enable docker
    systemctl start docker
    echo -e "${GREEN}Docker installed!${NC}"
else
    echo "Docker already installed"
fi

echo -e "\n${YELLOW}Creating /dev/net/tun for VPN...${NC}"
mkdir -p /dev/net
mknod /dev/net/tun c 10 200 2>/dev/null || true
chmod 600 /dev/net/tun

echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Edit the .env file with your configuration"
echo "2. Get your Mullvad WireGuard credentials from:"
echo "   https://mullvad.net/en/account/wireguard-config"
echo "3. Start the services:"
echo "   docker compose up -d"
echo ""
echo -e "${YELLOW}Service URLs (replace server-ip with your server's IP):${NC}"
echo ""
echo "  REQUEST MEDIA HERE:"
echo "  ─────────────────────────────────────────"
echo "  Jellyseerr:       http://server-ip:5055   ← Browse & request movies/shows"
echo ""
echo "  WATCH MEDIA HERE:"
echo "  ─────────────────────────────────────────"
echo "  Jellyfin:         http://server-ip:8096"
echo "  Audiobookshelf:   http://server-ip:13378"
echo ""
echo "  MEDIA AUTOMATION (usually don't need to touch):"
echo "  ─────────────────────────────────────────"
echo "  Sonarr:           http://server-ip:8989   (TV shows)"
echo "  Radarr:           http://server-ip:7878   (Movies)"
echo "  Lidarr:           http://server-ip:8686   (Music)"
echo "  Readarr:          http://server-ip:8787   (Books)"
echo "  Prowlarr:         http://server-ip:9696   (Indexers)"
echo "  Bazarr:           http://server-ip:6767   (Subtitles)"
echo "  qBittorrent:      http://server-ip:8080   (Downloads)"
echo ""
echo "  OTHER SERVICES:"
echo "  ─────────────────────────────────────────"
echo "  Homepage:         http://server-ip:3002   (Dashboard)"
echo "  Immich:           http://server-ip:2283   (Photos)"
echo "  Home Assistant:   http://server-ip:8123   (Smart home)"
echo "  AdGuard Home:     http://server-ip:3000   (DNS ad blocking)"
echo "  Vaultwarden:      http://server-ip:8222   (Passwords)"
echo "  Firefly III:      http://server-ip:8223   (Finance)"
echo "  OctoPrint:        http://server-ip:5000   (3D printing)"
echo "  Uptime Kuma:      http://server-ip:3001   (Monitoring)"
echo ""
echo -e "${YELLOW}Important:${NC}"
echo "- qBittorrent default login: admin / adminadmin (change immediately!)"
echo "- First user to register on each service becomes admin"
echo "- Set SIGNUPS_ALLOWED=false in Vaultwarden after creating accounts"
echo ""
echo -e "${YELLOW}Post-setup checklist:${NC}"
echo "1. Configure Prowlarr with indexers"
echo "2. Connect Prowlarr to Sonarr/Radarr/Lidarr"
echo "3. Configure Jellyseerr to connect to Jellyfin + Sonarr/Radarr"
echo "4. Set up Recyclarr API keys in ${APPDATA_PATH}/recyclarr/recyclarr.yml"
echo "5. Point your router's DNS to this server's IP for ad blocking"
echo ""
echo -e "${GREEN}See docs/HOW_TO_REQUEST_MEDIA.md for usage instructions!${NC}"
