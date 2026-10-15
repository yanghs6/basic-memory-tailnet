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
BM_PORT := $(or $(BM_PORT),8737)
SB_PORT := $(or $(SB_PORT),3000)
export BM_VM_HOST BM_VM_USER BM_TAILNET_DOMAIN BM_VM_PUBLIC_IP BM_PORT SB_PORT BM_ACCESS BM_ACCESS_CHECK_URL BM_TUNNEL_MCP_PORT BM_TUNNEL_WEB_PORT
# Only the targets that hand the SilverBullet login to compose or the VM, or log in to check it, see it; make
# review's CLIs and the read-only probe do not.
local-up local-down local-logs local-verify deploy restore verify: export SB_USER := $(SB_USER)
# make reads .env as makefile text (# starts a comment, $ expands), so the same targets also get the path of that file
# (never the value) and require_sb_user in scripts/lib/common.sh compares SB_USER with its raw line.
local-up local-down local-logs local-verify deploy restore verify: export SB_ENV_FILE := $(MAIN_ROOT)/.env
REVIEW_BASE := $(or $(REVIEW_BASE),origin/main)
export REVIEW_BASE REVIEW_ALLOW_SAME_VENDOR REVIEW_MODEL

SHELLCHECK_IMAGE := koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d
SHFMT_IMAGE := mvdan/shfmt:v3.12.0@sha256:307d265ffd25ce832899ae17c93ed5062fc3375c514bba8f52cbf52792735c4d
TOOLS_IMAGE := bm-tools:local
COVERAGE_MIN := 80
DOCKER_RUN := docker run --rm -v "$(CURDIR):/repo" -v "$(GIT_COMMON_DIR):$(GIT_COMMON_DIR):ro" -w /repo
SH_FILES = $(shell git ls-files --cached --others --exclude-standard -- '*.sh' '*.bash' 'tests/stubs/*')

.PHONY: help tools-image lint fmt test coverage check local-up local-down local-logs local-verify check-git review review-post review-record vm-bootstrap deploy verify probe status logs sb-fonts backup restore access-check tunnel

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
# SB_LOCAL_NOTES_DIR/SB_GITIGNORE_PENDING in scripts/lib/common.sh: removed only after Basic Memory was recreated.
SB_LOCAL_PENDING := .local-data/knowledge/basic-memory/.gitignore.pending

local-up: ## Start Basic Memory and SilverBullet locally (127.0.0.1:BM_PORT, SB_PORT) and wait until healthy
	. scripts/lib/common.sh && require_sb_user
	mkdir -p $(LOCAL_DATA_DIRS)
	gitignore_state="$$(scripts/sb-space.sh --local)" || exit 1; \
	  if [[ "$$gitignore_state" == changed ]]; then \
	    $(COMPOSE) up -d --wait --force-recreate basic-memory && rm -f $(SB_LOCAL_PENDING) \
	      && gitignore_state="$$(scripts/sb-space.sh --local)" && [[ "$$gitignore_state" == unchanged ]]; fi
	$(COMPOSE) up -d --wait

local-down: ## Stop the local containers (data in .local-data/ is kept)
	$(COMPOSE) down

local-logs: ## Show recent local container logs
	$(COMPOSE) logs --tail=200

local-verify: ## Verify the local MCP endpoint (plain and *.ts.net Host header) and the local SilverBullet login
	scripts/verify-mcp.sh "http://127.0.0.1:$(BM_PORT)/mcp"
	scripts/verify-mcp.sh --host-header agent-hub.example.ts.net "http://127.0.0.1:$(BM_PORT)/mcp"
	scripts/verify-sb.sh "http://127.0.0.1:$(SB_PORT)"

access-check: ## Report which access path (tailscale or ssh) works on this network; run it on every network you use
	scripts/access-check.sh

tunnel: ## ssh mode: forward MCP and the web UI to 127.0.0.1:BM_TUNNEL_MCP_PORT and BM_TUNNEL_WEB_PORT (Ctrl-C stops)
	scripts/tunnel.sh

check-git: ## Check the git policy for the current branch against origin/main (name, commit trailers, worktree config)
	scripts/check-git.sh origin/main

review: ## Read-only review by another vendor: BRANCH=<branch> REVIEWER=codex|claude [ROUND=1] [REVIEW_BASE=<sha>]
	scripts/review.sh "$(BRANCH)" "$(REVIEWER)" "$(or $(ROUND),1)"

review-post: ## Post a review round's reports to its PR: PR=<number> BRANCH=<branch> REVIEWER=codex|claude [ROUND=1] [REVIEW_MODEL=<model>]
	scripts/post-review.sh "$(PR)" "$(BRANCH)" "$(REVIEWER)" "$(or $(ROUND),1)"

review-record: ## Create or update the PR's Review record comment: PR=<number> FILE=<findings table file>
	scripts/review-record.sh "$(PR)" "$(FILE)"

vm-bootstrap: ## First-time VM setup (HOST=<public-ip>, or the SSH host alias in ssh mode; tailscale mode asks for an auth key)
	scripts/bootstrap-vm.sh "$(HOST)"

deploy: ## Copy compose.yaml to the VM and start Basic Memory (waits until healthy)
	scripts/deploy.sh

verify: ## Full VM check: MCP write/read/delete, SilverBullet login, loopback binding, exposure (Serve in tailscale mode; Tailscale off and sshd key-only in ssh mode), closed public ports
	scripts/verify-vm.sh

probe: ## Read-only VM check: same as verify but writes no notes and does not log in to SilverBullet
	scripts/verify-vm.sh --read-only

status: ## Show VM containers, memory and swap use, and tailscale serve (ssh mode: whether Tailscale is off)
	scripts/status.sh

logs: ## Show the last 200 lines of the VM container logs
	scripts/logs.sh

sb-fonts: ## Convert the D2Koding Nerd Font to WOFF2 and upload it to the VM notes folder (LOCAL=1: the local stack)
	scripts/sb-fonts.sh $(if $(LOCAL),--local)

backup: ## Download a consistent backup of VM data into the main checkout's backups/ (brief container stop)
	scripts/backup.sh

restore: ## Restore BACKUP=<main checkout>/backups/bm-<stamp>.tgz to the VM (asks for yes), then verify
	scripts/restore.sh "$(BACKUP)"
	scripts/verify-vm.sh
