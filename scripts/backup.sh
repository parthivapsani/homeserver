#!/bin/bash
# =============================================================================
# HOME SERVER BACKUP SCRIPT
# =============================================================================
# Backs up all container configurations and databases
# Run via cron: 0 3 * * * /path/to/backup.sh
# =============================================================================

set -e

# Configuration
BACKUP_DIR="/mnt/storage/backups/server"
APPDATA_PATH="/mnt/cache/appdata"
RETENTION_DAYS=30
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="homeserver-backup-${DATE}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Home Server Backup - ${DATE}${NC}"
echo -e "${GREEN}=========================================${NC}"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# ---------------------------------------------------------------------------
# Stop services that need consistent state for backup
# ---------------------------------------------------------------------------
echo -e "\n${YELLOW}Stopping database containers for consistent backup...${NC}"
docker compose stop immich-postgres firefly-postgres 2>/dev/null || true

# ---------------------------------------------------------------------------
# Backup PostgreSQL databases
# ---------------------------------------------------------------------------
echo -e "\n${YELLOW}Backing up databases...${NC}"

# Immich database
if docker ps -a | grep -q immich-postgres; then
    docker compose start immich-postgres
    sleep 5
    docker exec immich-postgres pg_dump -U postgres immich > "${BACKUP_DIR}/${BACKUP_NAME}-immich.sql"
    echo "  Immich database backed up"
fi

# Firefly database
if docker ps -a | grep -q firefly-postgres; then
    docker compose start firefly-postgres
    sleep 5
    docker exec firefly-postgres pg_dump -U firefly firefly > "${BACKUP_DIR}/${BACKUP_NAME}-firefly.sql"
    echo "  Firefly database backed up"
fi

# ---------------------------------------------------------------------------
# Backup appdata directories
# ---------------------------------------------------------------------------
echo -e "\n${YELLOW}Backing up appdata directories...${NC}"

# Create tar archive of all appdata (excluding large cache directories)
tar -czf "${BACKUP_DIR}/${BACKUP_NAME}-appdata.tar.gz" \
    --exclude='*/cache/*' \
    --exclude='*/Cache/*' \
    --exclude='*/logs/*' \
    --exclude='*/.cache/*' \
    --exclude='*/transcodes/*' \
    --exclude='*/model-cache/*' \
    -C "${APPDATA_PATH}" .

echo "  Appdata backup complete"

# ---------------------------------------------------------------------------
# Backup docker compose files
# ---------------------------------------------------------------------------
echo -e "\n${YELLOW}Backing up configuration files...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tar -czf "${BACKUP_DIR}/${BACKUP_NAME}-config.tar.gz" \
    -C "${SCRIPT_DIR}" \
    docker-compose.yml \
    compose/ \
    config/ \
    scripts/ \
    .env 2>/dev/null || true

echo "  Configuration backup complete"

# ---------------------------------------------------------------------------
# Restart services
# ---------------------------------------------------------------------------
echo -e "\n${YELLOW}Restarting services...${NC}"
docker compose start

# ---------------------------------------------------------------------------
# Cleanup old backups
# ---------------------------------------------------------------------------
echo -e "\n${YELLOW}Cleaning up backups older than ${RETENTION_DAYS} days...${NC}"
find "${BACKUP_DIR}" -name "homeserver-backup-*" -mtime +${RETENTION_DAYS} -delete

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
BACKUP_SIZE=$(du -sh "${BACKUP_DIR}/${BACKUP_NAME}"* 2>/dev/null | awk '{sum+=$1} END {print sum}')

echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}  Backup Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "Location: ${BACKUP_DIR}"
echo -e "Files created:"
ls -lh "${BACKUP_DIR}/${BACKUP_NAME}"* 2>/dev/null
echo ""
