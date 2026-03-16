# ── KalyNow Infrastructure — Makefile ─────────────────────────────────────────
#
# Usage:
#   make deploy ENV=local
#   make deploy ENV=prod
#   make job JOB=traefik ENV=local
#   make stop JOB=web ENV=local
#   make status
#   make logs JOB=user-service

ENV  ?= local
JOB  ?=
VARS  = environments/$(ENV)/jobs/$(JOB).vars

.PHONY: help deploy job stop stop-all status logs plan lint

## help: Show this help message
help:
	@echo ""
	@echo "  KalyNow Infrastructure"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"} /^## / { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""

## restart: Stop all jobs (except consul) then redeploy in order  (ENV=local|prod)
restart:
	@bash scripts/deploy.sh $(ENV) --restart

## purge: Stop AND purge ALL jobs including consul (clean slate)
purge:
	@bash scripts/deploy.sh $(ENV) --purge

## deploy: Deploy all jobs  (ENV=local|prod)
deploy:
	@bash scripts/deploy.sh $(ENV)

## job: Deploy a single job  (ENV=local|prod  JOB=<name>)
job:
	@bash scriptge-lock.json  README.md  TEMPLATE_CONTENT.md  tsconfig.node.json
gaetan@fedora:~/DATA/Dev/kalyNow/kalyNow-web$ docker build -t web:locals/deploy.sh $(ENV) $(JOB)

## stop: Stop a single job  (JOB=<name>)
stop:
	nomad job stop $(JOB)

## stop-all: Stop all application jobs (keeps consul/vault/traefik)
stop-all:
	nomad job stop web          || true
	nomad job stop user-service || true
	nomad job stop offer-service || true
	nomad job stop rustfs       || true
	nomad job stop mongodb      || true
	nomad job stop postgres     || true

## status: Show status of all jobs
status:
	nomad job status

## logs: Tail logs for a job  (JOB=<name>)
logs:
	nomad alloc logs -f $$(nomad job allocs -latest $(JOB) | tail -1 | awk '{print $$1}') $(JOB)

## plan: Dry-run a job deployment  (ENV=local|prod  JOB=<name>)
plan:
	nomad job plan -var-file=$(VARS) nomad/jobs/$(JOB).nomad.hcl

## lint: Validate all job files
lint:
	@echo "Validating all job files for ENV=$(ENV)..."
	@for f in nomad/jobs/*.nomad.hcl; do \
		job=$$(basename "$$f" .nomad.hcl); \
		vars="environments/$(ENV)/jobs/$${job}.vars"; \
		echo -n "  $$f ... "; \
		if [[ -f "$$vars" ]]; then \
			nomad job validate -var-file="$$vars" "$$f" && echo "OK" || echo "FAIL"; \
		else \
			nomad job validate "$$f" && echo "OK (no vars)" || echo "FAIL"; \
		fi; \
	done

## vault-unseal: Unseal Vault after a restart
vault-unseal:
	python3 scripts/bootstrap_vault.py --unseal-only --config scripts/config.py

## vault-init: Initialize Vault (first time only)
vault-init:
	python3 scripts/bootstrap_vault.py --init --config scripts/config.py

## vault-bootstrap: Bootstrap all Vault secrets (first time only)
vault-bootstrap:
	python3 scripts/bootstrap_vault.py --config scripts/config.py
