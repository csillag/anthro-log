SHELL      := /bin/bash
COMPOSE    := docker compose
GF_PORT    ?= 9300
PROM_PORT  ?= 9090

.PHONY: help init install up down restart status logs logs-otel logs-prom logs-grafana logs-poller env env-print verify clean reset install-shim uninstall-shim reload-prom rebuild-poller

help:
	@echo "anthro-log — Claude Code OTel → Prometheus → Grafana"
	@echo ""
	@echo "Targets:"
	@echo "  init           First-time setup: pull images + start stack + show next steps"
	@echo "  install        Pull docker images"
	@echo "  up             Start stack (detached)"
	@echo "  down           Stop stack (keep volumes)"
	@echo "  restart        Full restart: down + up (recovers stopped containers)"
	@echo "  status         Container status"
	@echo "  logs           Tail all logs"
	@echo "  logs-otel      Tail collector logs"
	@echo "  logs-prom      Tail Prometheus logs"
	@echo "  logs-grafana   Tail Grafana logs"
	@echo "  logs-poller    Tail usage-poller logs"
	@echo "  reload-prom    Hot-reload Prometheus config"
	@echo "  rebuild-poller Rebuild + restart usage-poller image"
	@echo "  env            Print 'source' command for Claude Code env"
	@echo "  env-print      Print env vars (for 'eval')"
	@echo "  verify         Curl health endpoints"
	@echo "  clean          Down + remove volumes (DATA LOSS)"
	@echo "  reset          clean + up (fresh start)"
	@echo ""
	@echo "  install-shim   Replace 'claude' on PATH with auto-source shim"
	@echo "  uninstall-shim Restore the original 'claude' binary path"
	@echo ""
	@echo "URLs (after 'make up'):"
	@echo "  Grafana:    http://localhost:$(GF_PORT)   (admin/admin)"
	@echo "  Prometheus: http://localhost:$(PROM_PORT)"

init: install up
	@echo ""
	@echo "Stack running."
	@echo "  Grafana:    http://localhost:$(GF_PORT)   (admin/admin — change on first login)"
	@echo "  Prometheus: http://localhost:$(PROM_PORT)"
	@echo ""
	@echo "Next: enable Claude Code telemetry in any shell that runs 'claude':"
	@echo "  source $(CURDIR)/claude-env.sh"
	@echo ""
	@echo "Then run claude as usual. Metrics appear within ~10s."

install:
	$(COMPOSE) pull

up:
	$(COMPOSE) up -d
	@$(MAKE) --no-print-directory status

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) down
	$(COMPOSE) up -d
	@$(MAKE) --no-print-directory status

status:
	@$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f --tail=100

logs-otel:
	$(COMPOSE) logs -f --tail=200 otel-collector

logs-prom:
	$(COMPOSE) logs -f --tail=200 prometheus

logs-grafana:
	$(COMPOSE) logs -f --tail=200 grafana

logs-poller:
	$(COMPOSE) logs -f --tail=200 usage-poller

reload-prom:
	curl -fsS -X POST http://localhost:$(PROM_PORT)/-/reload && echo "  reloaded"

rebuild-poller:
	$(COMPOSE) build usage-poller
	$(COMPOSE) up -d usage-poller

env:
	@echo "source $(CURDIR)/claude-env.sh"

env-print:
	@cat claude-env.sh

verify:
	@echo "== Collector health =="
	@curl -fsS http://localhost:13133 && echo "  OK" || echo "  FAIL"
	@echo "== Prometheus ready =="
	@curl -fsS http://localhost:$(PROM_PORT)/-/ready && echo "  OK" || echo "  FAIL"
	@echo "== Grafana health =="
	@curl -fsS http://localhost:$(GF_PORT)/api/health || echo "  FAIL"
	@echo ""
	@echo "== Prometheus targets =="
	@curl -fsS "http://localhost:$(PROM_PORT)/api/v1/targets?state=active" \
		| grep -oE '"health":"[^"]+"|"scrapeUrl":"[^"]+"' || true
	@echo ""
	@echo "== Sample metric query (claude_code_token_usage_tokens_total) =="
	@curl -fsS "http://localhost:$(PROM_PORT)/api/v1/query?query=claude_code_token_usage_tokens_total" \
		| head -c 800; echo

clean:
	$(COMPOSE) down -v

reset: clean up

install-shim:
	bash scripts/install-shim.sh

uninstall-shim:
	bash scripts/uninstall-shim.sh
