#!/usr/bin/env bash
# Swarm CLI Helper
# ================
# Convenience wrapper for common Swarm-in-a-Box operations.
#
# Usage:
#   ./docker/swarm-cli.sh <command> [args]
#
# Commands:
#   status              Show all service health and profile status
#   logs <service>      Tail logs for a service (gateway, chroma, paperclip, agent-runner, dashboard)
#   restart <service>   Restart a service
#   exec <profile>      Open a shell inside the agent-runner as a specific profile
#   profiles            List active profiles and their PIDs
#   update              Pull latest images and restart
#   backup              Backup ~/.hermes and Docker volumes
#   prune               Remove old containers, images, and volumes
#   help                Show this message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE="docker compose -f ${PROJECT_ROOT}/docker-compose.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cmd_status() {
    echo -e "${BLUE}=== Swarm Service Status ===${NC}"
    ${COMPOSE} ps
    echo ""
    echo -e "${BLUE}=== Profile Runner Status ===${NC}"
    ${COMPOSE} exec agent-runner bash /opt/hermes/docker/healthcheck-profiles.sh 2>/dev/null || echo -e "${YELLOW}Profile runner not ready${NC}"
}

cmd_logs() {
    local service="${1:-gateway}"
    ${COMPOSE} logs -f "$service"
}

cmd_restart() {
    local service="${1:-}"
    if [ -z "$service" ]; then
        echo "Usage: restart <service>"
        exit 1
    fi
    ${COMPOSE} restart "$service"
}

cmd_exec() {
    local profile="${1:-}"
    if [ -z "$profile" ]; then
        echo "Usage: exec <profile>"
        exit 1
    fi
    ${COMPOSE} exec -e HERMES_PROFILE="$profile" agent-runner bash
}

cmd_profiles() {
    echo -e "${BLUE}=== Active Profiles ===${NC}"
    cat "${SCRIPT_DIR}/profiles.txt" 2>/dev/null | grep -v '^#' | sed 's/^/  - /'
    echo ""
    echo -e "${BLUE}=== Profile PIDs ===${NC}"
    ${COMPOSE} exec agent-runner ls -la /opt/data/.pids/ 2>/dev/null || echo -e "${YELLOW}No PID files yet${NC}"
}

cmd_update() {
    echo -e "${BLUE}Pulling latest images...${NC}"
    ${COMPOSE} pull
    echo -e "${BLUE}Rebuilding local images...${NC}"
    ${COMPOSE} build
    echo -e "${BLUE}Restarting swarm...${NC}"
    ${COMPOSE} up -d
}

cmd_backup() {
    local backup_dir="${PROJECT_ROOT}/backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    echo -e "${BLUE}Backing up to ${backup_dir}...${NC}"
    tar czf "${backup_dir}/hermes-home.tar.gz" -C "${HOME}" .hermes 2>/dev/null || echo -e "${YELLOW}Warning: could not backup ~/.hermes${NC}"
    ${COMPOSE} exec chroma tar czf - /chroma/chroma > "${backup_dir}/chroma-data.tar.gz" 2>/dev/null || echo -e "${YELLOW}Warning: could not backup ChromaDB${NC}"
    ${COMPOSE} exec paperclip tar czf - /data > "${backup_dir}/paperclip-data.tar.gz" 2>/dev/null || echo -e "${YELLOW}Warning: could not backup Paperclip${NC}"
    echo -e "${GREEN}Backup complete: ${backup_dir}${NC}"
}

cmd_prune() {
    echo -e "${YELLOW}This will remove unused containers, images, and volumes.${NC}"
    read -rp "Continue? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        docker system prune -f
        docker volume prune -f
    fi
}

cmd_help() {
    sed -n '2,18p' "$0"
}

# Main dispatch
command="${1:-help}"
shift || true

case "$command" in
    status) cmd_status ;;
    logs) cmd_logs "$@" ;;
    restart) cmd_restart "$@" ;;
    exec) cmd_exec "$@" ;;
    profiles) cmd_profiles ;;
    update) cmd_update ;;
    backup) cmd_backup ;;
    prune) cmd_prune ;;
    help|--help|-h) cmd_help ;;
    *) echo "Unknown command: $command"; cmd_help; exit 1 ;;
esac
