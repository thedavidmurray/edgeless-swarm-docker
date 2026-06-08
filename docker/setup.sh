#!/usr/bin/env bash
# Swarm-in-a-Box Setup Script
# ===========================
# Validates the environment, creates required directories, checks secrets,
# and prepares the Docker Compose stack for first launch.
#
# Usage:
#   ./docker/setup.sh [OPTIONS]
#
# Options:
#   --force      Re-run even if setup appears complete
#   --dry-run    Print what would be done without doing it
#   --profiles   Reconcile profile list only (generate profiles.txt)
#   --help       Show this message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
HERMES_PROFILES="${HERMES_PROFILES:-${HERMES_HOME}/profiles}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DRY_RUN=false
FORCE=false
PROFILES_ONLY=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }

check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        log_error "Required command not found: $1"
        exit 1
    fi
}

env_or_default() {
    local key="$1"
    local default="$2"
    if [ -f "$ENV_FILE" ]; then
        grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d'=' -f2- || echo "$default"
    else
        echo "$default"
    fi
}

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --profiles) PROFILES_ONLY=true; shift ;;
        --help)
            sed -n '2,14p' "$0"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
log_info "Checking prerequisites..."
check_cmd docker
if $DRY_RUN; then
    log_info "(dry-run) Would check docker daemon is running"
else
    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running or not accessible."
        exit 1
    fi
fi

check_cmd docker
check_cmd curl

# ---------------------------------------------------------------------------
# Validate .env
# ---------------------------------------------------------------------------
if [ ! -f "$ENV_FILE" ]; then
    log_warn "No .env file found at ${ENV_FILE}"
    if [ -f "${SCRIPT_DIR}/.env.example" ]; then
        log_info "Copying docker/.env.example to .env"
        if ! $DRY_RUN; then
            cp "${SCRIPT_DIR}/.env.example" "$ENV_FILE"
            log_warn "Please edit ${ENV_FILE} and add your API keys before starting the swarm."
        fi
    fi
else
    log_ok ".env file exists"
    # Check for placeholder secrets
    local placeholders=0
    for key in FIREWORKS_API_KEY DISCORD_BOT_TOKEN TELEGRAM_BOT_TOKEN; do
        val=$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d'=' -f2- || true)
        if [ -z "$val" ] || [[ "$val" == *"YOUR_"* ]] || [[ "$val" == *"fw_*"* ]]; then
            log_warn "${key} appears to be unset or still a placeholder in .env"
            placeholders=$((placeholders + 1))
        fi
    done
    if [ "$placeholders" -gt 0 ]; then
        log_warn "${placeholders} required secrets are missing. Edit .env before starting."
    fi
fi

# ---------------------------------------------------------------------------
# Ensure Hermes home directory structure
# ---------------------------------------------------------------------------
log_info "Ensuring Hermes home directory structure..."
DIRS=(
    "${HERMES_HOME}"
    "${HERMES_HOME}/profiles"
    "${HERMES_HOME}/cron"
    "${HERMES_HOME}/logs"
    "${HERMES_HOME}/skills"
    "${HERMES_HOME}/memories"
    "${HERMES_HOME}/sessions"
    "${HERMES_HOME}/state"
    "${HERMES_HOME}/chroma_db"
)

for dir in "${DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        if $DRY_RUN; then
            log_info "(dry-run) Would mkdir -p ${dir}"
        else
            mkdir -p "$dir"
            log_info "Created ${dir}"
        fi
    fi
done

# ---------------------------------------------------------------------------
# Reconcile profiles list
# ---------------------------------------------------------------------------
log_info "Reconciling swarm profiles..."
PROFILES_FILE="${SCRIPT_DIR}/profiles.txt"
if [ -d "${HERMES_PROFILES}" ]; then
    # Auto-detect profiles from disk
    mapfile -t detected_profiles < <(ls -1 "${HERMES_PROFILES}" 2>/dev/null | grep -v '^\.' | sort || true)
    if [ ${#detected_profiles[@]} -eq 0 ]; then
        log_warn "No profiles found in ${HERMES_PROFILES}. Using default swarm roster."
        default_profiles=(hive beau scribe edgeless-cc kilo)
        detected_profiles=("${default_profiles[@]}")
    fi
else
    log_warn "Profiles directory not found. Using default swarm roster."
    default_profiles=(hive beau scribe edgeless-cc kilo)
    detected_profiles=("${default_profiles[@]}")
fi

if $DRY_RUN; then
    log_info "(dry-run) Would write ${PROFILES_FILE} with:"
    printf '%s\n' "${detected_profiles[@]}" | sed 's/^/  - /'
else
    printf '%s\n' "${detected_profiles[@]}" > "$PROFILES_FILE"
    log_ok "Wrote ${#detected_profiles[@]} profiles to ${PROFILES_FILE}"
fi

if $PROFILES_ONLY; then
    log_info "Profile reconciliation complete."
    exit 0
fi

# ---------------------------------------------------------------------------
# Check for hermes-agent source
# ---------------------------------------------------------------------------
HERMES_AGENT_PATH=$(env_or_default "HERMES_AGENT_PATH" "./hermes-agent")
if [ ! -d "${PROJECT_ROOT}/${HERMES_AGENT_PATH}" ] && [ ! -d "${HERMES_AGENT_PATH}" ]; then
    log_warn "hermes-agent source not found at ${HERMES_AGENT_PATH}"
    log_info "Cloning hermes-agent from GitHub..."
    if $DRY_RUN; then
        log_info "(dry-run) Would clone git@github.com:NousResearch/hermes-agent.git ${HERMES_AGENT_PATH}"
    else
        git clone https://github.com/NousResearch/hermes-agent.git "${PROJECT_ROOT}/${HERMES_AGENT_PATH}" || {
            log_error "Failed to clone hermes-agent. Please clone it manually into ${HERMES_AGENT_PATH}"
            exit 1
        }
    fi
else
    log_ok "hermes-agent source found"
fi

# ---------------------------------------------------------------------------
# Validate Docker Compose file
# ---------------------------------------------------------------------------
log_info "Validating docker-compose.yml..."
if $DRY_RUN; then
    log_info "(dry-run) Would run docker compose config"
else
    if ! docker compose config > /dev/null 2>&1; then
        log_error "docker-compose.yml validation failed. Check your .env values and syntax."
        exit 1
    fi
    log_ok "docker-compose.yml is valid"
fi

# ---------------------------------------------------------------------------
# Build images
# ---------------------------------------------------------------------------
if ! $FORCE && docker image inspect hermes-agent:swarm &>/dev/null; then
    log_ok "hermes-agent:swarm image already exists (use --force to rebuild)"
else
    log_info "Building Hermes agent image (this may take 5-10 minutes)..."
    if $DRY_RUN; then
        log_info "(dry-run) Would run docker compose build gateway"
    else
        docker compose build gateway
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
log_ok "Setup complete!"
log_info "Next steps:"
log_info "  1. Review and edit .env if you haven't already"
log_info "  2. Start the swarm:  docker compose up -d"
log_info "  3. Watch logs:        docker compose logs -f gateway"
log_info "  4. Check health:      docker compose ps"
log_info "  5. Open dashboard:    http://127.0.0.1:${DASHBOARD_PORT:-9119}"
echo ""
log_info "Profile roster:"
cat "$PROFILES_FILE" | sed 's/^/  - /'
