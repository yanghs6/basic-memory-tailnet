# Single lifecycle interface for this repo. Run `make help`.
SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

# A worktree .git file points at the main repo .git dir by absolute path; mount it so git works in containers.
GIT_COMMON_DIR := $(shell git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
# .env lives only in the main checkout (the parent of the common git dir), whichever checkout runs make.
# Outside git there is no main checkout to find, so fall back to the current directory.
MAIN_ROOT := $(if $(GIT_COMMON_DIR),$(abspath $(GIT_COMMON_DIR)/..),$(CURDIR))
-include $(MAIN_ROOT)/.env
# Same defaults as DEFAULT_BM_PORT, DEFAULT_SB_PORT and DEFAULT_BM_WEB_PORT in scripts/lib/common.sh.
BM_PORT := $(or $(BM_PORT),8737)
SB_PORT := $(or $(SB_PORT),3000)
BM_WEB_PORT := $(or $(BM_WEB_PORT),8738)
export BM_VM_HOST BM_VM_USER BM_TAILNET_DOMAIN BM_VM_PUBLIC_IP BM_PORT SB_PORT BM_ACCESS BM_ACCESS_CHECK_URL BM_TUNNEL_MCP_PORT BM_TUNNEL_WEB_PORT BM_MEMORY_DEVICE BM_MEMORY_MCP_URL BM_MEMORY_EXCLUDE
export BM_WEB BM_WEB_HOST BM_WEB_PORT BM_WEB_GITHUB_USER_ID BM_WEB_GITHUB_CLIENT_ID
# Only the targets that hand the SilverBullet login to compose or the VM, or log in to check it, see it; make
# review's CLIs and the read-only probe do not.
local-up local-down local-logs local-verify deploy restore verify: export SB_USER := $(SB_USER)
# make reads .env as makefile text (# starts a comment, $ expands), so the same targets also get the path of that file
# (never the value) and require_sb_user in scripts/lib/sb.sh compares SB_USER with its raw line.
local-up local-down local-logs local-verify deploy restore verify: export SB_ENV_FILE := $(MAIN_ROOT)/.env
# The web connector's three secrets, like SB_USER: only the targets that hand them to compose or the VM see them.
local-up local-down local-logs local-verify deploy restore: export BM_WEB_GITHUB_CLIENT_SECRET := $(BM_WEB_GITHUB_CLIENT_SECRET)
local-up local-down local-logs local-verify deploy restore: export BM_WEB_JWT_KEY := $(BM_WEB_JWT_KEY)
local-up local-down local-logs local-verify deploy restore: export BM_WEB_TUNNEL_TOKEN := $(BM_WEB_TUNNEL_TOKEN)
# BM_WEB=on: the local targets also run the gateway (profile web, never the tunnel) at its local base URL. The compose
# commands stay the same; COMPOSE_PROFILES picks the services.
ifeq ($(BM_WEB),on)
local-up local-down local-logs local-verify: export COMPOSE_PROFILES := web
local-up local-down local-logs local-verify: export BM_WEB_BASE_URL := http://127.0.0.1:$(BM_WEB_PORT)
endif
REVIEW_BASE := $(or $(REVIEW_BASE),origin/main)
export REVIEW_BASE REVIEW_ALLOW_SAME_VENDOR REVIEW_MODEL REVIEW_EFFORT

SHELLCHECK_IMAGE := koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d
SHFMT_IMAGE := mvdan/shfmt:v3.12.0@sha256:307d265ffd25ce832899ae17c93ed5062fc3375c514bba8f52cbf52792735c4d
# The image's entrypoint is gitleaks and it trusts every directory (safe.directory '*'), so DOCKER_RUN fits it as is.
GITLEAKS_IMAGE := zricethezav/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f
TOOLS_IMAGE := bm-tools:local
COVERAGE_MIN := 80
DOCKER_RUN := docker run --rm -v "$(CURDIR):/repo" -v "$(GIT_COMMON_DIR):$(GIT_COMMON_DIR):ro" -w /repo
SH_FILES = $(shell git ls-files --cached --others --exclude-standard -- '*.sh' '*.bash' '*.bats' 'tests/stubs/*')

.PHONY: help tools-image lint fmt test coverage check local-up local-down local-logs local-verify gateway-lock check-git secret-scan review review-post review-record vm-bootstrap deploy verify probe status logs export-logs sb-fonts backup restore access-check tunnel memory-sync memory-index memory-hooks new-doc new-id new-script

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
ifeq ($(BM_WEB),on)
LOCAL_DATA_DIRS += .local-data/gateway
endif
# The gateway image is named once, in its compose.yaml service; gateway-lock compiles the lock file inside it.
GATEWAY_IMAGE = $(shell awk '$$0 == "  gateway:" { inside = 1; next } inside && /^  [^ ]/ { exit } inside && $$1 == "image:" { print $$2; exit }' compose.yaml)
PIP_TOOLS_VERSION := 7.6.2
# The user that serves the gateway's public path (APP_UID in gateway/boot.py, BM_CONTAINER_UID in scripts/lib/vm.sh);
# local-verify runs the gateway tests as this user too, never as root.
GATEWAY_USER := 1000:1000

local-up: ## Start Basic Memory and SilverBullet locally (127.0.0.1:BM_PORT, SB_PORT) and wait until healthy; BM_WEB=on adds the gateway (BM_WEB_PORT)
	@. scripts/lib/vm.sh && web_mode >/dev/null
	. scripts/lib/sb.sh && require_sb_user
	scripts/check-local-stack.sh
	mkdir -p $(LOCAL_DATA_DIRS)
	. scripts/lib/sb.sh && sb_space_apply local "rerun 'make local-up'" $(COMPOSE) up -d --wait --force-recreate basic-memory
	$(COMPOSE) up -d --wait

local-down: ## Stop the local containers (data in .local-data/ is kept)
	scripts/check-local-stack.sh
	$(COMPOSE) down

local-logs: ## Show recent local container logs
	$(COMPOSE) logs --tail=200

local-verify: ## Verify the local MCP endpoint (plain and *.ts.net Host header) and the local SilverBullet login; BM_WEB=on also checks the gateway
	scripts/verify-mcp.sh "http://127.0.0.1:$(BM_PORT)/mcp"
	scripts/verify-mcp.sh --host-header agent-hub.example.ts.net "http://127.0.0.1:$(BM_PORT)/mcp"
	scripts/verify-sb.sh "http://127.0.0.1:$(SB_PORT)"
ifeq ($(BM_WEB),on)
	scripts/verify-web.sh "http://127.0.0.1:$(BM_WEB_PORT)"
	$(COMPOSE) exec -T --user $(GATEWAY_USER) gateway python -m unittest -v test_gateway
endif

gateway-lock: ## Pin gateway/requirements.in and every dependency with hashes into gateway/requirements.txt (pip-compile in the gateway image)
	docker run --rm -v "$(CURDIR)/gateway:/gateway:ro" -w /gateway $(GATEWAY_IMAGE) sh -c 'pip install --quiet --disable-pip-version-check --root-user-action=ignore pip-tools==$(PIP_TOOLS_VERSION) && pip-compile --quiet --generate-hashes --allow-unsafe --strip-extras --output-file=- requirements.in' >gateway/requirements.txt.partial
	mv gateway/requirements.txt.partial gateway/requirements.txt

access-check: ## Report which access path (tailscale or ssh) works on this network; run it on every network you use
	scripts/check-access.sh

tunnel: ## ssh mode: forward MCP and the web UI to 127.0.0.1:BM_TUNNEL_MCP_PORT and BM_TUNNEL_WEB_PORT (Ctrl-C stops)
	scripts/open-tunnel.sh

memory-sync: ## Mirror this Mac's Claude Code and Codex memory files to Basic Memory (HOOK=1: in the background, always exit 0; FULL=1: rewrite everything after a restore)
	scripts/sync-agent-memory.sh $(if $(HOOK),--hook) $(if $(FULL),--full)

memory-index: ## Print the Basic Memory index of this project and global notes for a SessionStart hook on stdin (MEMORY_AGENT=claude-code|codex)
	scripts/show-memory-index.sh "$(MEMORY_AGENT)"

memory-hooks: ## Add the memory-sync and memory-index hooks to Claude Code and Codex (REMOVE=1 removes them; ask the user first)
	scripts/install-memory-hooks.sh $(if $(REMOVE),--remove)

check-git: ## Check the git policy for the current branch against origin/main (name, commit trailers, worktree config)
	scripts/check-git.sh origin/main

# git log reads every ref through the read-only common dir mount, which also resolves a linked worktree's .git file.
secret-scan: ## Scan every commit of every local ref for secrets with gitleaks (values redacted; run git fetch origin first)
	$(DOCKER_RUN) $(GITLEAKS_IMAGE) git --redact --verbose --log-opts=--all /repo

new-doc: ## Create a document from its template: TYPE=<type> SLUG=<slug> [ID=<id>] (types and rules: docs/README.md)
	scripts/create-doc.sh "$(TYPE)" "$(SLUG)" "$(ID)"

new-id: ## Print one unused document id, e.g. for a draft on the Basic Memory draft board (run git fetch origin first)
	@scripts/create-id.sh

new-script: ## Create a script and its pair test from the templates: NAME=<name> [KIND=script|remote|lib] (rules: the script-authoring skill)
	scripts/create-script.sh "$(NAME)" "$(KIND)"

review: ## Read-only review by another vendor: BRANCH=<branch> REVIEWER=codex|claude [ROUND=1] [REVIEW_BASE=<sha>] [REVIEW_MODEL=<model>] [REVIEW_EFFORT=low|medium|high|xhigh|max]
	scripts/review-branch.sh "$(BRANCH)" "$(REVIEWER)" "$(or $(ROUND),1)"

review-post: ## Post a review round's reports to its PR: PR=<number> BRANCH=<branch> REVIEWER=codex|claude [ROUND=1]
	scripts/post-review.sh "$(PR)" "$(BRANCH)" "$(REVIEWER)" "$(or $(ROUND),1)"

review-record: ## Create or update the PR's Review record comment: PR=<number> FILE=<findings table file>
	scripts/post-review-record.sh "$(PR)" "$(FILE)"

vm-bootstrap: ## First-time VM setup (HOST=<public-ip>, or the SSH host alias in ssh mode; tailscale mode asks for an auth key)
	scripts/bootstrap-vm.sh "$(HOST)"

deploy: ## Copy compose.yaml, the VM .env and the SilverBullet space files to the VM, then start Basic Memory and SilverBullet (waits until healthy)
	scripts/deploy-stack.sh

verify: ## Full VM check: MCP write/read/delete, SilverBullet login, loopback binding, exposure (Serve in tailscale mode; Tailscale off and sshd key-only in ssh mode), closed public ports
	scripts/verify-vm.sh

probe: ## Read-only VM check: same as verify but writes no notes and does not log in to SilverBullet
	scripts/verify-vm.sh --read-only

status: ## Show VM containers, memory and swap use, and tailscale serve (ssh mode: whether Tailscale is off)
	scripts/show-status.sh

logs: ## Show the last 200 lines of the VM container logs
	scripts/show-logs.sh

export-logs: ## Download the VM container logs since SINCE (default 24h) as one JSON Lines file into the main checkout's log-exports/
	scripts/export-logs.sh "$(SINCE)"

sb-fonts: ## Convert the D2Koding Nerd Font to WOFF2 and upload it to the VM notes folder (LOCAL=1: the local stack)
	scripts/upload-sb-fonts.sh $(if $(LOCAL),--local)

backup: ## Download a consistent backup of VM data into the main checkout's backups/ (brief container stop)
	scripts/backup-notes.sh

restore: ## Restore BACKUP=<main checkout>/backups/bm-<stamp>.tgz to the VM (asks for yes), then verify
	scripts/restore-notes.sh "$(BACKUP)"
	scripts/verify-vm.sh
