# M&S Log Analysis Toolkit

Automates the Maintenance & Support workflow for investigating Jira support tickets via Claude Code skills, bash scripts, and YAML data stores.

Skills are compiled from templates and installed into `.claude/skills/` for Claude Code invocation.

## Directory Structure

```
support/                              ← workspace (any name)
├── toolkit/                          ← git submodule (shared core)
│   ├── scripts/
│   │   ├── lib/common.sh            ← workspace_root() + toolkit_root()
│   │   ├── setup/
│   │   │   ├── bootstrap.sh         ← one-time service setup
│   │   │   ├── install-skills.sh    ← template variable processing
│   │   │   └── verify-jira-access.sh
│   │   ├── fetch-ticket.sh
│   │   ├── rename-logs.sh
│   │   ├── log-activity.sh
│   │   ├── close-ticket.sh
│   │   └── check-ticket-status.sh
│   ├── skills/                       ← templates with {{VARIABLE}} placeholders
│   ├── templates/
│   ├── ui/
│   ├── docs/
│   ├── .env.example                  ← credential template
│   ├── .env                          ← per-user credentials (gitignored)
│   ├── .gitignore
│   ├── README.md                     ← generic setup instructions
│   ├── VERSION
│   └── CHANGELOG.md
├── config.yaml                       ← per-service (tracked in host repo)
├── data/                             ← generated data (tracked in host repo)
│   ├── log-database/
│   ├── knowledge-center/
│   ├── codebase-profile.yaml
│   └── logging-standards.yaml
├── tickets/                          ← structured ticket workspaces (gitignored)
└── log-archive/                      ← completed tickets (gitignored)
```

## Quick Start

```bash
# 1. Set up (one-time)
cd logs
cp toolkit/.env.example toolkit/.env   # Edit with your Jira credentials
bash toolkit/scripts/setup/verify-jira-access.sh
bash toolkit/scripts/setup/install-skills.sh
```

Then in Claude Code:

```
/fetch-ticket PROJ-123              # Fetch ticket, match KC pattern
/generate-log-request PROJ-123      # Generate LogQL query for support team
# ... receive logs, place in tickets/PROJ-123/logs/ ...
/analyze-logs PROJ-123              # Analyze logs, generate response
/close-ticket PROJ-123              # Archive ticket when done
```

## Skills

**Workflow** (ticket investigation):

| Skill | Purpose |
|-------|---------|
| `/fetch-ticket <TICKET>` | Fetch Jira ticket, extract identifiers, match KC pattern |
| `/generate-log-request <TICKET>` | Generate LogQL query for the support team |
| `/generate-data-request <TICKET>` | Generate SQL queries for production data |
| `/analyze-logs <TICKET>` | Analyze logs against ticket context + KC, generate response |
| `/close-ticket <TICKET>` | Archive completed ticket from `tickets/` to `log-archive/` |
| `/generate-work-history [time range]` | Generate Tempo-ready weekly work summary |

**Setup and maintenance**:

| Skill | Purpose |
|-------|---------|
| `/verify-jira-access` | Verify Jira API credentials and project access |
| `/init-workspace` | Auto-detect modules, channels, and integrations from codebase |
| `/init-log-database` | Build the Log Database from source code analysis |
| `/update-log-database` | Map unmapped ticket logs into the Log Database (10 per batch) |
| `/init-knowledge-center` | Build the Knowledge Center from Jira ticket analysis |
| `/update-knowledge-center` | Consolidate draft KC patterns, deduplicate, promote to confirmed |

Every workflow skill auto-logs its activity and regenerates the weekly work history.

## Workflow

```
 1. /fetch-ticket <TICKET>             Fetch + KC pattern match
 2. /generate-log-request <TICKET>     LogQL query for support team
 3. Send log request, receive logs     [manual]
 4. /analyze-logs <TICKET>             Root cause + response
 5. Review and send response           [manual]
 6. /close-ticket <TICKET>             Archive to log-archive/
```

Optional at any point: `/generate-data-request` for production data, `/generate-work-history` for Tempo entries.

## Ticket Lifecycle

```
tickets/{TICKET}/                 Active investigation
    |
    |  /fetch-ticket -> /generate-log-request -> /analyze-logs
    v
/close-ticket <TICKET>            Archive (checks Jira status)
    |
    v
log-archive/{TICKET}/             Done — eligible for mapping
    |
    |  /update-log-database        Map log patterns
    |  /update-knowledge-center    Consolidate KC patterns
    
```

- `/close-ticket` checks Jira status as an advisory guard (configurable via `jira.final_statuses` in `config.yaml`)
- `/update-log-database` only maps archived tickets in a final Jira status
- `/analyze-logs` auto-drafts new KC patterns; `/update-knowledge-center` consolidates them

## Setup

### Jira API Token

1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Create token named "M&S Log Analysis Toolkit"
3. `cp toolkit/.env.example toolkit/.env` and fill in `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`
4. `bash toolkit/scripts/setup/verify-jira-access.sh`

### Configuration

Review `config.yaml` — key fields: `jira.project_key`, `loki.app_label`, `loki.namespace`, `service_classification.keywords`.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Auth failed (HTTP 401) | Verify `JIRA_EMAIL`, regenerate API token, check for trailing spaces in `.env` |
| Cannot reach Jira server | Check `JIRA_BASE_URL` format (`https://yourorg.atlassian.net`, no trailing slash), verify VPN |
| Cannot find workspace root | Run from within repo, or set `TOOLKIT_WORKSPACE=/path/to/workspace/` |
| Log files too large | Skill pre-filters noise; if still large, split by time range (1-2h chunks) |
| Activity log not updating | Ensure ticket directory exists (created by `/fetch-ticket`) |

## Further Documentation

| Document | Contents |
|----------|----------|
| [Components Reference](docs/components.md) | Log Database, Knowledge Center, Scripts, Templates detail |
| [Setting Up for a New Service](docs/setup-new-service.md) | Full 9-step guide for adding the toolkit to a new service |
| [Example Walkthrough](docs/example-walkthrough.md) | End-to-end ticket investigation example |
