# anthro-log

Self-hosted observability stack for **Claude Code** token throughput, cost,
and activity. OpenTelemetry collector + Prometheus + Grafana, in Docker
Compose, behind a Makefile.

## What it shows

- Token rate (tokens/sec) by type — `input`, `output`, `cacheRead`, `cacheCreation`
- Output token rate by model
- Cumulative tokens, cost (USD), sessions, lines of code, commits
- Per-interval token deltas for spotting fluctuations

## Requirements

- Docker + Docker Compose v2
- Claude Code CLI (`claude`)

## Quick start

```bash
git clone <this-repo> anthro-log
cd anthro-log
make init                       # pulls images, starts stack
source ./claude-env.sh          # in every shell that runs 'claude'
claude                          # run claude as normal
```

Open http://localhost:3000 (admin/admin). Dashboard "Claude Code — Tokens & Cost"
appears under the **Claude Code** folder.

## Auto-load env on every `claude` invocation (optional)

Sourcing `claude-env.sh` per shell is friction. The repo ships a shim
that replaces the `claude` command on `PATH` with a one-line wrapper
that auto-sources the env file before exec'ing the real binary —
transparent to all CLI args.

```bash
make install-shim     # replaces ~/local/bin/claude (or $SHIM_PATH)
make uninstall-shim   # restores original
```

Disable temporarily for a single invocation:

```bash
ANTHRO_LOG_DISABLE=1 claude ...
```

The installer records prior state at `<shim-path>.original` so the
uninstaller can restore exactly (symlink, regular file, or absent).
Override locations via `SHIM_PATH=...` or `CLAUDE_REAL_BIN=...`.

## Sharing with another machine

Other machines on the LAN can ship metrics to this stack. On the remote box:

```bash
ANTHRO_LOG_HOST=<this-host-ip> source /path/to/claude-env.sh
```

The collector binds `0.0.0.0:4317` (gRPC) and `0.0.0.0:4318` (HTTP).

## Make targets

| Target | What it does |
|--------|--------------|
| `make init` | Pull images + start stack + print next steps |
| `make up` | Start stack |
| `make down` | Stop (keep volumes) |
| `make restart` | Restart all services |
| `make status` | `docker compose ps` |
| `make logs` | Tail all logs |
| `make logs-otel` / `logs-prom` / `logs-grafana` | Per-service logs |
| `make verify` | Curl health endpoints + sample metric query |
| `make env` | Print `source` command |
| `make clean` | Down + delete volumes (DATA LOSS) |
| `make reset` | `clean` + `up` |

## Ports

| Port | Service |
|------|---------|
| 3000 | Grafana UI |
| 9090 | Prometheus UI |
| 4317 | OTLP gRPC (collector ingest) |
| 4318 | OTLP HTTP (collector ingest) |
| 8889 | Collector → Prometheus scrape (internal) |
| 13133 | Collector health check |

## Verifying data flow

```bash
make verify
```

If `claude_code_token_usage_tokens_total` returns no series:
1. Confirm `claude-env.sh` was sourced in the shell running `claude`.
2. Confirm `claude` ran at least one turn after sourcing.
3. Wait 10–15 s for next metric export.
4. Check `make logs-otel` for receive errors.
5. Browse http://localhost:9090/api/v1/label/__name__/values for actual metric names — Claude Code may rename or version metrics. Edit the dashboard PromQL to match.

## Customizing

- **Retention** — `--storage.tsdb.retention.time=180d` in `docker-compose.yml`.
- **Admin password** — set `GF_ADMIN_USER` / `GF_ADMIN_PASSWORD` in a `.env`
  file next to `docker-compose.yml` (gitignored).
- **Faster updates** — lower `OTEL_METRIC_EXPORT_INTERVAL` in `claude-env.sh`
  (already 10 s; minimum useful ~1 s).
- **More dashboards** — drop JSON into `grafana/dashboards/` and restart
  Grafana, or edit in UI (changes persist via the `grafana-data` volume).

## Reference

- Claude Code monitoring: https://code.claude.com/docs/en/monitoring-usage.md
- OpenTelemetry collector: https://opentelemetry.io/docs/collector/
