# Single lifecycle interface for this repo. Run `make help`.
SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

-include .env
BM_PORT := $(or $(BM_PORT),8737)
export BM_VM_HOST BM_VM_USER BM_TAILNET_DOMAIN BM_VM_PUBLIC_IP BM_PORT

SHELLCHECK_IMAGE := koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d
SHFMT_IMAGE := mvdan/shfmt:v3.12.0@sha256:307d265ffd25ce832899ae17c93ed5062fc3375c514bba8f52cbf52792735c4d
TOOLS_IMAGE := bm-tools:local
COVERAGE_MIN := 80
# A worktree .git file points at the main repo .git dir by absolute path; mount it so git works in containers.
GIT_COMMON_DIR := $(shell git rev-parse --path-format=absolute --git-common-dir)
DOCKER_RUN := docker run --rm -v "$(CURDIR):/repo" -v "$(GIT_COMMON_DIR):$(GIT_COMMON_DIR):ro" -w /repo
SH_FILES = $(shell git ls-files --cached --others --exclude-standard -- '*.sh' '*.bash' 'tests/stubs/*')

.PHONY: help tools-image lint fmt test coverage check local-up local-down local-logs local-verify

help: ## Show available targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-z0-9-]+:.*## / { printf "  %-14s %s\n", $$1, $$2 }' $(firstword $(MAKEFILE_LIST))

tools-image: ## Build the local test image (kcov + bats + jq)
	@docker build -q -t $(TOOLS_IMAGE) tools >/dev/null

lint: ## Check shell files with shellcheck and shfmt
	$(DOCKER_RUN) $(SHELLCHECK_IMAGE) $(SH_FILES)
	$(DOCKER_RUN) $(SHFMT_IMAGE) -d $(SH_FILES)

fmt: ## Rewrite shell files in place with shfmt
	$(DOCKER_RUN) $(SHFMT_IMAGE) -w $(SH_FILES)

test: tools-image ## Run all bats tests
	$(DOCKER_RUN) $(TOOLS_IMAGE) bats tests

coverage: tools-image ## Run tests under kcov; fail below COVERAGE_MIN% line coverage
	$(DOCKER_RUN) $(TOOLS_IMAGE) tools/coverage.sh $(COVERAGE_MIN)

check: lint coverage ## Lint + all tests + coverage gate (run before every commit)

COMPOSE := docker compose -f compose.yaml
LOCAL_DATA_DIRS := .local-data/knowledge .local-data/config

local-up: ## Start Basic Memory locally on 127.0.0.1:BM_PORT and wait until healthy
	mkdir -p $(LOCAL_DATA_DIRS)
	$(COMPOSE) up -d --wait

local-down: ## Stop the local container (data in .local-data/ is kept)
	$(COMPOSE) down

local-logs: ## Show recent local container logs
	$(COMPOSE) logs --tail=200

local-verify: ## Verify the local MCP endpoint (plain and *.ts.net Host header)
	scripts/verify-mcp.sh "http://127.0.0.1:$(BM_PORT)/mcp"
	scripts/verify-mcp.sh --host-header bm-node.example.ts.net "http://127.0.0.1:$(BM_PORT)/mcp"
