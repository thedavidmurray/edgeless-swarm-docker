#!/command/with-contenv sh
# shellcheck shell=sh
# Multi-Profile Agent Runner for Swarm-in-a-Box
# =============================================
# Spawns one Hermes process per profile listed in /etc/swarm/profiles.txt.
# Each profile runs as a supervised child process under the container's
# s6-overlay tree. This script is the entrypoint for the agent-runner service.
#
# Design:
#   - Uses s6-supervise when available (s6-overlay container), falling back to
#     a simple bash loop with wait/respawn for non-s6 contexts.
#   - Each profile gets its own log file under /opt/data/logs/<profile>.log.
#   - SIGTERM/SIGINT are propagated to all child profiles for graceful shutdown.
#   - A sentinel file (/tmp/swarm-profiles-active) is touched once all profiles
#     are spawned; the Dockerfile healthcheck checks for this file.

set -eu

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="${INSTALL_DIR:-/opt/hermes}"
PROFILES_FILE="${HERMES_RUN_PROFILES:-/etc/swarm/profiles.txt}"
LOG_DIR="${HERMES_HOME}/logs"
PID_DIR="${HERMES_HOME}/.pids"
SENTINEL="/tmp/swarm-profiles-active"

# Drop to hermes user when running as root
as_hermes() { [ "$(id -u)" = 0 ] && set -- s6-setuidgid hermes "$@"; "$@"; }

mkdir -p "$LOG_DIR" "$PID_DIR"

# ---------------------------------------------------------------------------
# Read profile roster
# ---------------------------------------------------------------------------
if [ ! -f "$PROFILES_FILE" ]; then
    echo "[profile-runner] ERROR: profiles file not found: $PROFILES_FILE"
    exit 1
fi

PROFILES=""
while IFS= read -r line; do
    # Skip comments and blank lines
    case "$line" in
        ''|\#*) continue ;;
    esac
    PROFILES="${PROFILES}${line} "
done < "$PROFILES_FILE"

if [ -z "$PROFILES" ]; then
    echo "[profile-runner] ERROR: no profiles defined in $PROFILES_FILE"
    exit 1
fi

echo "[profile-runner] Starting profiles: ${PROFILES}"

# ---------------------------------------------------------------------------
# Spawn helpers
# ---------------------------------------------------------------------------
spawn_profile() {
    local profile="$1"
    local logfile="${LOG_DIR}/${profile}.log"
    local pidfile="${PID_DIR}/${profile}.pid"

    # Ensure profile directory exists
    if [ ! -d "${HERMES_HOME}/profiles/${profile}" ]; then
        echo "[profile-runner] WARNING: profile dir not found, creating: ${HERMES_HOME}/profiles/${profile}"
        as_hermes mkdir -p "${HERMES_HOME}/profiles/${profile}"
    fi

    # Ensure profile has a config.yaml (seed from base if missing)
    if [ ! -f "${HERMES_HOME}/profiles/${profile}/config.yaml" ]; then
        echo "[profile-runner] Seeding config.yaml for ${profile}"
        if [ -f "${HERMES_HOME}/profiles/${profile}/profile.yaml" ]; then
            as_hermes cp "${HERMES_HOME}/profiles/${profile}/profile.yaml" \
                "${HERMES_HOME}/profiles/${profile}/config.yaml"
        elif [ -f "${HERMES_HOME}/config.yaml" ]; then
            as_hermes cp "${HERMES_HOME}/config.yaml" \
                "${HERMES_HOME}/profiles/${profile}/config.yaml"
        fi
    fi

    # Start hermes in profile mode (no gateway, headless agent loop)
    # We use `hermes chat --quiet` with a profile flag, but hermes CLI
    # doesn't natively support --profile. Instead we use HERMES_PROFILE
    # env var and set the working directory to the profile dir.
    (
        cd "${HERMES_HOME}/profiles/${profile}" || exit 1
        export HERMES_PROFILE="${profile}"
        export HERMES_HOME="${HERMES_HOME}"
        # Activate the venv so `hermes` resolves correctly
        # shellcheck disable=SC1091
        . "${INSTALL_DIR}/.venv/bin/activate"

        # Launch hermes in a background-able mode suitable for a swarm agent.
        # We use the batch runner in a polling loop, or fall back to a simple
        # heartbeat process. The exact command is profile-configurable via
        # profile.yaml's `docker_run_command` key.
        local cmd
        if [ -f "${HERMES_HOME}/profiles/${profile}/.swarm-docker-cmd" ]; then
            cmd=$(cat "${HERMES_HOME}/profiles/${profile}/.swarm-docker-cmd")
        else
            # Default: run a lightweight heartbeat that keeps the profile alive
            # and lets the gateway dispatch work to it.
            cmd="python -c 'import time; time.sleep(86400)'"
        fi

        # Write PID for healthcheck tracking
        echo $$ > "$pidfile"

        # Execute the command, logging stdout+stderr
        eval "$cmd" >> "$logfile" 2>&1
    ) &

    echo "[profile-runner] Spawned ${profile} (PID $!)"
    echo "$!" > "$pidfile"
}

# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------
cleanup() {
    echo "[profile-runner] Received shutdown signal, terminating profiles..."
    for pidfile in "$PID_DIR"/*.pid; do
        [ -f "$pidfile" ] || continue
        local pid
        pid=$(cat "$pidfile" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "[profile-runner] Stopping PID ${pid}"
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    # Wait up to 10s for graceful exit
    sleep 2
    for pidfile in "$PID_DIR"/*.pid; do
        [ -f "$pidfile" ] || continue
        local pid
        pid=$(cat "$pidfile" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
    rm -f "$SENTINEL"
    exit 0
}

trap cleanup INT TERM

# ---------------------------------------------------------------------------
# Spawn all profiles
# ---------------------------------------------------------------------------
for profile in $PROFILES; do
    spawn_profile "$profile"
done

# Write sentinel for healthcheck
touch "$SENTINEL"

# ---------------------------------------------------------------------------
# Watchdog / respawn loop
# ---------------------------------------------------------------------------
echo "[profile-runner] Entering watchdog loop. Press Ctrl+C or send SIGTERM to stop."
while true; do
    all_alive=true
    for pidfile in "$PID_DIR"/*.pid; do
        [ -f "$pidfile" ] || continue
        local pid profile_name
        pid=$(cat "$pidfile" 2>/dev/null || true)
        profile_name=$(basename "$pidfile" .pid)
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            logfile="${LOG_DIR}/${profile_name}.log"
            echo "[profile-runner] ${profile_name} (PID ${pid}) died, respawning..."
            spawn_profile "$profile_name"
            all_alive=false
        fi
    done

    if $all_alive; then
        # Update sentinel timestamp
        touch "$SENTINEL"
    fi

    sleep 10
done
