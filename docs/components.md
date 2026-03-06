# Components Reference

## Log Database (`data/log-database/`)

Categorized database of all meaningful log types produced by this service.

| File | Format | Purpose |
|------|--------|---------|
| `log-types.yaml` | YAML (source of truth) | Machine-readable log type definitions |
| `LOG_DATABASE.md` | Markdown (auto-generated) | Human-readable reference |

Each entry maps a log pattern to its module, trigger, and meaning for ticket analysis.

**Setup**: Run `/init-log-database` to build the database from source code analysis (module by module).
**Maintenance**: Run `/update-log-database` to incrementally map unmapped tickets from `log-archive/` (up to 10 per run), discover new log patterns, and update frequency data.

## Knowledge Center (`data/knowledge-center/`)

Living knowledge base of recurring issue patterns from past support tickets.

| File | Format | Purpose |
|------|--------|---------|
| `issues.yaml` | YAML (source of truth) | Issue patterns with log signatures and resolutions |
| `KNOWLEDGE_CENTER.md` | Markdown (auto-generated) | Human-readable reference |

Auto-updates when new patterns are discovered during analysis. Run `/update-knowledge-center` periodically to consolidate draft patterns, deduplicate, and promote to confirmed.

## Scripts (`scripts/`)

| Script | Purpose |
|--------|---------|
| `lib/common.sh` | Shared helpers (config loading, activity logging, etc.) |
| `setup/verify-jira-access.sh` | Verify Jira API credentials and access |
| `setup/install-skills.sh` | Compile skill templates and install to `.claude/skills/` |
| `setup/bootstrap.sh` | One-time workspace initialization for a new service |
| `log-activity.sh` | Manually record a ticket activity entry |
| `fetch-ticket.sh` | Fetch ticket details from Jira (called by `/fetch-ticket`) |
| `rename-logs.sh` | Standardize Grafana export filenames to `YYYY-MM-DD_api-prod.txt` |
| `close-ticket.sh` | Move a ticket directory from `tickets/` to `log-archive/` |
| `check-ticket-status.sh` | Fetch current Jira status for a ticket (used by `/close-ticket` and `/update-log-database`) |

## Templates (`templates/`)

Canonical templates for all generated files. Templates are the single source of truth for file structure.

| Template | Used by |
|----------|---------|
| `ticket-details.yaml` | `/fetch-ticket` |
| `log-request.md` | `/generate-log-request` |
| `data-request.md` | `/generate-data-request` |
| `analysis.md` | `/analyze-logs` |
| `activity-log.yaml` | All skills (auto-tracking) |
| `work-history.md` | `/generate-work-history` |
| `log-types.yaml` | `/init-log-database` |
| `issues.yaml` | `/init-knowledge-center` |
| `config.yaml` | Blueprint for new services |
