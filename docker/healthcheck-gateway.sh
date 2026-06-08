#!/usr/bin/env bash
# Gateway Health Check
# --------------------
# Used by Docker Compose healthcheck and external monitoring.
# Returns 0 if the gateway is healthy, 1 otherwise.

set -eo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
GATEWAY_STATE="${HERMES_HOME}/gateway_state.json"
API_PORT="${GATEWAY_API_PORT:-8080}"

# Check 1: gateway_state.json exists and reports "running"
if [ -f "$GATEWAY_STATE" ]; then
    if grep -q '"gateway_state":"running"' "$GATEWAY_STATE" 2>/dev/null; then
        echo "gateway_state=running"
    else
        state=$(grep -o '"gateway_state":"[^"]*"' "$GATEWAY_STATE" 2>/dev/null || echo "unknown")
        echo "gateway_state=${state}"
        exit 1
    fi
else
    echo "gateway_state=file_missing"
    exit 1
fi

# Check 2: API server responds (if API_SERVER_KEY is set, skip auth check)
if curl -fsS "http://127.0.0.1:${API_PORT}/health" >/dev/null 2>&1; then
    echo "api_health=ok"
else
    # API server may not be enabled; that's fine as long as state is running
    echo "api_health=not_enabled_or_unreachable"
fi

# Check 3: Platforms are connected (at least one)
if [ -f "$GATEWAY_STATE" ]; then
    platforms=$(grep -c '"state":"connected"' "$GATEWAY_STATE" 2>/dev/null || echo "0")
    if [ "$platforms" -gt 0 ]; then
        echo "platforms_connected=${platforms}"
    else
        echo "platforms_connected=0"
        # Not fatal — gateway can be running even if platforms are retrying
    fi
fi

exit 0
