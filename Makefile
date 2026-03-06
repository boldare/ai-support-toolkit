# M&S Log Analysis Toolkit — Makefile
# Run `make help` for usage information.

SCRIPTS_DIR := scripts
SETUP_DIR   := scripts/setup

# ─── Ticket Operations ───────────────────────────────────────────────────────

.PHONY: fetch-ticket
fetch-ticket: ## Fetch a Jira ticket and generate ticket-details.yaml (TICKET=PROJ-123 [CONTEXT="..."])
	@bash $(SCRIPTS_DIR)/fetch-ticket.sh $(TICKET) $(if $(CONTEXT),--context "$(CONTEXT)")

.PHONY: check-ticket-status
check-ticket-status: ## Check current Jira status for a ticket (TICKET=PROJ-123)
	@bash $(SCRIPTS_DIR)/check-ticket-status.sh $(TICKET)

.PHONY: close-ticket
close-ticket: ## Archive a ticket from tickets/ to log-archive/ (TICKET=PROJ-123)
	@bash $(SCRIPTS_DIR)/close-ticket.sh $(TICKET)

# ─── Log Operations ──────────────────────────────────────────────────────────

.PHONY: log-activity
log-activity: ## Log an activity entry for a ticket (TICKET=PROJ-123 ACTION="..." DESC="..." [DURATION=0])
	@bash $(SCRIPTS_DIR)/log-activity.sh $(TICKET) "$(ACTION)" "$(DESC)" $(DURATION)

.PHONY: rename-logs
rename-logs: ## Rename Grafana log exports to standardized format (DIR=path/to/logs/)
	@bash $(SCRIPTS_DIR)/rename-logs.sh $(DIR)

# ─── Setup ────────────────────────────────────────────────────────────────────

.PHONY: bootstrap
bootstrap: ## One-time workspace initialization (creates dirs, copies templates, installs skills)
	@bash $(SETUP_DIR)/bootstrap.sh

.PHONY: install-skills
install-skills: ## Process skill templates and install to .claude/skills/
	@bash $(SETUP_DIR)/install-skills.sh

.PHONY: verify-jira-access
verify-jira-access: ## Verify Jira API access is configured correctly
	@bash $(SETUP_DIR)/verify-jira-access.sh

# ─── Help ─────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help