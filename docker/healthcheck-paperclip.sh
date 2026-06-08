#!/usr/bin/env bash
# Paperclip API Health Check
# --------------------------
# Validates the Paperclip API service is responding.

set -eo pipefail

PAPERCLIP_PORT="${PAPERCLIP_PORT:-3100}"
PAPERCLIP_HOST="${PAPERCLIP_BIND:-localhost}"

if ! curl -fsS "http://${PAPERCLIP_HOST}:${PAPERCLIP_PORT}/api/health" >/dev/null 2>&1; then
    echo "paperclip_health=fail"
    exit 1
fi

echo "paperclip_health=ok"
exit 0
