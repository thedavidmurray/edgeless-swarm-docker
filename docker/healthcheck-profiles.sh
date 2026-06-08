#!/usr/bin/env bash
# Multi-Profile Agent Runner Health Check
# ----------------------------------------
# Checks that the profile-runner sentinel exists and all tracked PIDs are alive.

set -eo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
PID_DIR="${HERMES_HOME}/.pids"
SENTINEL="/tmp/swarm-profiles-active"

if [ ! -f "$SENTINEL" ]; then
    echo "profiles_health=sentinel_missing"
    exit 1
fi

# Check if sentinel is stale (> 2 min old)
if [ "$(find "$SENTINEL" -mmin +2 2>/dev/null | wc -l)" -gt 0 ]; then
    echo "profiles_health=sentinel_stale"
    exit 1
fi

# Check tracked PIDs
alive=0
dead=0
if [ -d "$PID_DIR" ]; then
    for pidfile in "$PID_DIR"/*.pid; do
        [ -f "$pidfile" ] || continue
        pid=$(cat "$pidfile" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            alive=$((alive + 1))
        else
            dead=$((dead + 1))
        fi
    done
fi

if [ "$alive" -eq 0 ] && [ -d "$PID_DIR" ]; then
    echo "profiles_health=no_profiles_alive"
    exit 1
fi

echo "profiles_health=ok alive=${alive} dead=${dead}"
exit 0
