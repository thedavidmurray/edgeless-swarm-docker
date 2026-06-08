# Swarm-in-a-Box

> Product-grade Docker containerization for the Edgeless multi-agent swarm.

**Swarm-in-a-Box** lets you run your own Edgeless-like agent swarm with a single `git clone` and `docker compose up`. It packages the Hermes gateway, a multi-profile agent runner, ChromaDB vector store, and a Paperclip-compatible task API into an isolated, reproducible stack.

---

## What's Included

| Service | Image | Purpose | Default Port |
|---------|-------|---------|--------------|
| **gateway** | `hermes-agent:swarm` | Discord + Telegram gateway, API server, cron scheduler | `8080` |
| **agent-runner** | `hermes-agent:swarm` | Multi-profile agent runner (Hive, Beau, Scribe, Edgeless-CC, Kilo, …) | — |
| **dashboard** | `hermes-agent:swarm` | Web UI for status, logs, and agent control | `9119` |
| **chroma** | `chromadb/chroma:latest` | Vector store for embeddings and memory | `8000` |
| **paperclip** | `swarm-paperclip` | Task / issue tracker (stub or real) | `3100` |
| **watchtower** | `containrrr/watchtower` | *(optional)* Auto-update images | — |

---

## Quick Start

### 1. Clone

```bash
git clone https://github.com/your-org/swarm-in-a-box.git
cd swarm-in-a-box
```

### 2. Configure

```bash
# Copy the environment template
cp docker/.env.example .env

# Edit with your API keys and paths
nano .env
```

Required secrets:
- `FIREWORKS_API_KEY` (or `OPENROUTER_API_KEY`) — for LLM inference
- `DISCORD_BOT_TOKEN` — if using Discord
- `TELEGRAM_BOT_TOKEN` — if using Telegram
- `API_SERVER_KEY` — if exposing the API server beyond localhost

### 3. Run Setup

```bash
./docker/setup.sh
```

This will:
- Validate Docker and Compose
- Create the `~/.hermes` directory tree
- Auto-detect your profiles and write `docker/profiles.txt`
- Clone the `hermes-agent` repo if it's not already present
- Build the `hermes-agent:swarm` image

### 4. Start the Swarm

```bash
docker compose up -d
```

### 5. Verify

```bash
docker compose ps
docker compose logs -f gateway
```

Open the dashboard:
```bash
open http://127.0.0.1:9119
```

---

## Directory Layout

```
.
├── docker-compose.yml           # Main orchestration
├── docker/
│   ├── .env.example               # Template for secrets
│   ├── setup.sh                   # Bootstrap script
│   ├── profiles.txt               # Active profile roster
│   ├── profile-runner.sh          # Multi-profile agent entrypoint
│   ├── healthcheck-gateway.sh     # Gateway health probe
│   ├── healthcheck-chroma.sh      # ChromaDB health probe
│   ├── healthcheck-paperclip.sh   # Paperclip health probe
│   ├── healthcheck-profiles.sh    # Profile runner health probe
│   └── paperclip/
│       ├── Dockerfile             # Paperclip stub image
│       ├── paperclip_stub.py      # Minimal task API
│       └── config.json            # Stub config
├── hermes-agent/                # Hermes source (cloned by setup.sh)
├── .env                         # Your secrets (gitignored)
└── README.md                    # This file
```

---

## Profile Management

Profiles are stored in `~/.hermes/profiles/<name>/`. Each profile has its own:
- `config.yaml` — model, tools, timeouts, personality
- `skills/` — profile-specific skills
- `cron/` — scheduled jobs
- `memories/` — long-term memory

The agent runner spawns one supervised process per profile listed in `docker/profiles.txt`.

### Adding a Profile

```bash
# 1. Create the profile directory
mkdir -p ~/.hermes/profiles/my-agent

# 2. Seed a config
cp ~/.hermes/config.yaml ~/.hermes/profiles/my-agent/config.yaml

# 3. Edit the profile config
nano ~/.hermes/profiles/my-agent/config.yaml

# 4. Add to the roster
echo "my-agent" >> docker/profiles.txt

# 5. Restart the runner
docker compose restart agent-runner
```

### Default Swarm Roster

| Profile | Role | Model |
|---------|------|-------|
| **hive** | Swarm coordinator, human interface | Kimi K2.5 (Fireworks) |
| **beau** | Research, RSS triage, VPS ops | Kimi K2.5 |
| **scribe** | Knowledge base, documentation | Kimi K2.5 |
| **edgeless-cc** | Architecture, system design | Claude Opus 4.6 |
| **kilo** | Code execution, Claude Code lane | Kimi / Codex |

---

## Networking & Isolation

All services attach to a custom bridge network `swarm-net` (`172.30.0.0/16`):
- **chroma** → `http://chroma:8000`
- **paperclip** → `http://paperclip:3100`
- **gateway** → publishes `8080` and `9119` to the host
- **dashboard** → bound to `127.0.0.1:9119` on the host

Only the gateway and dashboard expose ports to the host. Everything else is internal.

---

## Persistence

| Data | Location | Volume Type |
|------|----------|-------------|
| Hermes config, auth, sessions | `~/.hermes` | Bind mount |
| Agent profiles | `~/.hermes/profiles` | Bind mount |
| ChromaDB index | Docker named volume `chroma-data` | Named volume |
| Paperclip issues | Docker named volume `paperclip-data` | Named volume |

---

## Health Checks

Every core service has a Docker-native health check:

```bash
# Check all service health
docker compose ps

# Inspect a specific health status
docker inspect --format='{{.State.Health.Status}}' swarm-gateway

# Trigger manual checks
./docker/healthcheck-gateway.sh
./docker/healthcheck-chroma.sh
./docker/healthcheck-paperclip.sh
./docker/healthcheck-profiles.sh
```

---

## Upgrading

```bash
# Pull latest images
docker compose pull

# Rebuild if you changed source
docker compose build gateway

# Rolling restart (zero-downtime for gateway)
docker compose up -d

# Optional: enable auto-updates
# Edit docker-compose.yml to uncomment the watchtower service
# or start with: docker compose --profile auto-update up -d
```

---

## Security Checklist

- [ ] `.env` is **not** committed to git (`git check-ignore -v .env`)
- [ ] `.env` permissions are `600` (`chmod 600 .env`)
- [ ] `API_SERVER_KEY` is set to a strong random key if exposing port 8080
- [ ] Dashboard is behind a reverse proxy (nginx, Traefik, Caddy) with TLS
- [ ] Discord/Telegram tokens are rotated regularly
- [ ] `CHROMA_SERVER_CORS_ALLOW_ORIGINS` is narrowed if Chroma is exposed
- [ ] Host firewall blocks `8000`/`3100` from external interfaces unless needed

---

## Troubleshooting

### Gateway keeps restarting

```bash
docker compose logs gateway | tail -n 50
# Check if gateway_state.json is corrupt or missing:
cat ~/.hermes/gateway_state.json
# Fix: rm ~/.hermes/gateway_state.json && docker compose restart gateway
```

### Agent runner shows no alive profiles

```bash
docker compose logs agent-runner | tail -n 50
# Check if profiles.txt is correct:
cat docker/profiles.txt
# Check if profile directories exist:
ls ~/.hermes/profiles/
```

### ChromaDB unreachable

```bash
docker compose logs chroma
curl http://localhost:8000/api/v1/heartbeat
# If port 8000 is taken, set CHROMA_HOST_PORT=8001 in .env
```

### Permission denied on ~/.hermes

```bash
# Ensure UID/GID in .env match your host user:
id -u  # e.g., 1000
id -g  # e.g., 1000
# Then update .env and restart:
docker compose down
docker compose up -d
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HERMES_UID` | `1000` | Host user ID for file ownership |
| `HERMES_GID` | `1000` | Host group ID for file ownership |
| `HERMES_HOME` | `~/.hermes` | Path to Hermes data directory |
| `HERMES_PROFILES` | `~/.hermes/profiles` | Path to agent profiles |
| `HERMES_AGENT_PATH` | `./hermes-agent` | Path to hermes-agent source |
| `CHROMA_HOST_PORT` | `8000` | Host port for ChromaDB |
| `PAPERCLIP_HOST_PORT` | `3100` | Host port for Paperclip |
| `GATEWAY_API_PORT` | `8080` | Host port for Hermes API |
| `DASHBOARD_PORT` | `9119` | Host port for Dashboard |
| `API_SERVER_HOST` | `0.0.0.0` | API server bind address |
| `API_SERVER_KEY` | — | API server auth key |
| `FIREWORKS_API_KEY` | — | Fireworks AI API key |
| `OPENROUTER_API_KEY` | — | OpenRouter API key |
| `ANTHROPIC_API_KEY` | — | Anthropic API key |
| `OPENAI_API_KEY` | — | OpenAI API key |
| `DISCORD_BOT_TOKEN` | — | Discord bot token |
| `TELEGRAM_BOT_TOKEN` | — | Telegram bot token |
| `PAPERCLIP_COMPANY_ID` | — | Paperclip company UUID |
| `PAPERCLIP_API_KEY` | — | Paperclip API key |
| `CHROMA_MEMORY_LIMIT` | `2G` | ChromaDB container memory limit |
| `GATEWAY_MEMORY_LIMIT` | `2G` | Gateway container memory limit |
| `AGENT_RUNNER_MEMORY_LIMIT` | `4G` | Agent runner memory limit |
| `WATCHTOWER_NOTIFICATION_URL` | — | Shoutrrr URL for update alerts |

---

## Development & Contributing

- Follow the Hermes Agent [CONTRIBUTING.md](hermes-agent/CONTRIBUTING.md) for code style.
- Run smoke tests before committing: `python scripts/preflight/smoke_test.py`
- All shell scripts are checked with `shellcheck` and `bash -n`.

---

## License

MIT — same as [hermes-agent](https://github.com/NousResearch/hermes-agent).
