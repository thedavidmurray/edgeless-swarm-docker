#!/usr/bin/env bash
# ChromaDB Health Check
# ---------------------
# Validates the ChromaDB service is accepting requests.

set -eo pipefail

CHROMA_PORT="${CHROMA_SERVER_PORT:-8000}"
CHROMA_HOST="${CHROMA_SERVER_HOST:-localhost}"

if ! curl -fsS "http://${CHROMA_HOST}:${CHROMA_PORT}/api/v1/heartbeat" >/dev/null 2>&1; then
    echo "chroma_health=fail"
    exit 1
fi

echo "chroma_health=ok"
exit 0
