# Paperclip API — Swarm Task / Issue Tracker
# ==========================================
# This is a placeholder Dockerfile for the Paperclip API service.
# Paperclip is the Edgeless swarm's task-management system (issue tracker
# with EDGA- prefix). In production you should either:
#
#   1. Replace this with the real Paperclip service image (if available).
#   2. Use an external Paperclip instance and set PAPERCLIP_URL in .env.
#   3. Extend this minimal Python stub with your own API implementation.
#
# The compose file expects Paperclip to expose:
#   GET /api/health        → 200 { "status": "ok" }
#   GET /api/issues        → 200 [ { "id": "EDGA-001", ... } ]
#   POST /api/issues       → 201 { "id": "EDGA-002", ... }
#   GET /api/issues/:id    → 200 { ... }
#   PUT /api/issues/:id    → 200 { ... }

FROM python:3.11-slim

WORKDIR /app

# Install minimal dependencies
RUN pip install --no-cache-dir fastapi uvicorn pydantic

# Copy the stub server
COPY paperclip_stub.py /app/paperclip_stub.py

# Default config (can be overridden by volume mount)
COPY config.json /app/config.json

EXPOSE 3100

CMD ["uvicorn", "paperclip_stub:app", "--host", "0.0.0.0", "--port", "3100"]
