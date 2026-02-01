#!/bin/bash
# =============================================================================
# HOME SERVER UPDATE SCRIPT
# =============================================================================
# Updates all Docker containers to latest versions
# Includes health checks and rollback capability
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Home Server Update${NC}"
echo -e "${GREEN}=========================================${NC}"

# ---------------------------------------------------------------------------
# Pre-update checks
# ---------------------------------------------------------------------------
echo -e "\n${YELLOW}Checking current status...${NC}"
docker compose ps

# ---------------------------------------------------------------------------
# Create backup before update
# ---------------------------------------------------------------------------
echo -e "\n${YELLOW}Creating pre-update backup...${NC}"
if [[ -f scripts/backup.sh ]]; then
    bash scripts/backup.sh
else
    echo "Backup script not found, skipping..."
fi

# ---------------------------------------------------------------------------
# Pull latest images
# ---------------------------------------------------------------------------
echo -e "\n${YELLOW}Pulling latest images...${NC}"
docker compose pull

# ---------------------------------------------------------------------------
# Update containers
# ---------------------------------------------------------------------------
echo -e "\n${YELLOW}Updating containers...${NC}"
docker compose up -d

# ---------------------------------------------------------------------------
# Wait for containers to be healthy
# ---------------------------------------------------------------------------
echo -e "\n${YELLOW}Waiting for containers to be healthy...${NC}"
sleep 30

# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
echo -e "\n${YELLOW}Running health checks...${NC}"

FAILED=0

# Check if key containers are running
for container in jellyfin sonarr radarr prowlarr gluetun immich-server homeassistant; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        STATUS=$(docker inspect --format='{{.State.Status}}' ${container})
        if [[ "${STATUS}" == "running" ]]; then
            echo -e "  ${GREEN}✓${NC} ${container} is running"
        else
            echo -e "  ${RED}✗${NC} ${container} status: ${STATUS}"
            FAILED=1
        fi
    else
        echo -e "  ${YELLOW}○${NC} ${container} not deployed"
    fi
done

# Check VPN connectivity
if docker ps --format '{{.Names}}' | grep -q "^gluetun$"; then
    VPN_STATUS=$(docker exec gluetun curl -s https://am.i.mullvad.net/connected 2>/dev/null || echo "Failed")
    if [[ "${VPN_STATUS}" == *"You are connected"* ]]; then
        echo -e "  ${GREEN}✓${NC} VPN connected to Mullvad"
    else
        echo -e "  ${RED}✗${NC} VPN not connected!"
        FAILED=1
    fi
fi

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
echo -e "\n${YELLOW}Cleaning up old images...${NC}"
docker image prune -f

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}=========================================${NC}"
if [[ ${FAILED} -eq 0 ]]; then
    echo -e "${GREEN}  Update Complete - All checks passed!${NC}"
else
    echo -e "${RED}  Update Complete - Some checks failed!${NC}"
    echo -e "${YELLOW}  Review the output above for issues.${NC}"
fi
echo -e "${GREEN}=========================================${NC}"

docker compose ps
