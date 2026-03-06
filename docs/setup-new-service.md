# Setting Up for a New Service

This toolkit is distributed as a git submodule. Skills are authored as templates with `{{VARIABLE}}` placeholders and compiled to concrete files during setup. The steps below walk through the full setup from scratch.

## Prerequisites

- **Git repository** for the service you want to add the toolkit to
- **Claude Code CLI** installed
- **Jira Cloud API token** (instructions in Step 3)
- **bash**, **curl**, **jq**, **python3**

## Step 1: Add the toolkit as a git submodule

```bash
mkdir -p support
git submodule add <toolkit-repo-url> support/toolkit
```

**Purpose**: Downloads the shared toolkit code into `support/toolkit/`. The `support/` directory becomes your workspace — all per-service data (config, tickets, logs) lives here alongside the shared toolkit.

**Outcome**: `support/toolkit/` contains scripts, skill templates, UI, and file templates. Nothing is configured yet.

## Step 2: Bootstrap the workspace

```bash
bash support/toolkit/scripts/setup/bootstrap.sh
```

**Purpose**: Creates the workspace directory structure and copies starter files from the toolkit templates.

**Outcome**:
- `support/config.yaml` — service configuration file (from template, needs manual fields filled in)
- `support/.env.example` — credential template
- `support/.gitignore` — ignores `.env`, `tickets/`, `log-archive/`, `reports/`
- `support/data/`, `support/tickets/`, `support/log-archive/`, `support/reports/` — empty directories
- Skills are compiled and installed into `.claude/skills/` (with empty config values for now)

## Step 3: Configure Jira credentials

```bash
cp support/.env.example support/.env
```

Edit `support/.env` with your Jira credentials:

```
JIRA_BASE_URL=https://yourorg.atlassian.net
JIRA_EMAIL=your.email@company.com
JIRA_API_TOKEN=your-token-here
```

To get an API token: go to https://id.atlassian.com/manage-profile/security/api-tokens, click **Create API token**, name it "M&S Log Analysis Toolkit", and copy it.

**Purpose**: Jira API access is required for fetching tickets and building the Knowledge Center.

**Outcome**: `.env` file with credentials. This file is gitignored and never committed.

## Step 4: Fill in the manual configuration fields

Edit `support/config.yaml` and fill in all fields marked `[MANUAL]`.

**Critical fields** — these directly affect generated LogQL queries, ticket matching, and data requests. Getting them wrong produces broken queries or missed tickets:

| Field | What it controls | Example |
|-------|------------------|---------|
| `service.name` | Service identifier used in skill templates and reports | `my-service-api` |
| `jira.project_key` | Which Jira project to query for tickets | `PROJ` |
| `loki.app_label` | The `app=` label in generated LogQL queries — **must match your Grafana/Loki setup exactly** | `my-service-api-prod` |
| `loki.namespace` | The `namespace=` label in generated LogQL queries — **must match exactly** | `my-namespace-prod` |
| `loki.timezone` | Timezone for log timestamp interpretation and time range calculations | `America/New_York` |
| `service_classification.keywords` | Terms used to identify this service's tickets on the shared Jira board. Affects `/init-knowledge-center` ticket filtering | `["my-service", "module-name"]` |
| `database.type` | Database engine — affects SQL syntax in generated data requests | `postgresql` |

**Non-critical fields** — used for display, file naming, and cosmetic purposes. Can be filled in later or left approximate:

| Field | What it controls | Example |
|-------|------------------|---------|
| `service.display_name` | Header text in the dashboard UI and reports | `My Service API` |
| `service.description` | Descriptive text, used only for documentation | `Handles order processing, payments...` |
| `loki.cluster` | Informational only — not used in queries | `prod` |
| `loki.short_label` | Shorthand used when renaming downloaded log files (e.g., `2026-02-10_api-prod.txt`) | `api-prod` |

**Purpose**: These fields cannot be auto-detected — they require knowledge of your infrastructure, Jira project, and Grafana setup.

**Outcome**: `config.yaml` has all manual fields filled in. The `[AUTO]` sections (modules, channels, integrations) are still empty — Step 6 fills those.

## Step 5: Verify Jira access

In Claude Code:

```
/verify-jira-access
```

Or via script:

```bash
bash support/toolkit/scripts/setup/verify-jira-access.sh
```

**Purpose**: Tests that your Jira credentials work and that you have access to the configured project. Checks: prerequisites, `.env` file, API connectivity, authentication, project access, and search capability.

**Outcome**: Either all checks pass (proceed to Step 6) or you get specific error messages to fix (wrong URL, expired token, missing project access, etc.).

## Step 6: Auto-detect modules, channels, and integrations

In Claude Code:

```
/init-workspace
```

**Purpose**: Analyzes your service's codebase to auto-detect the module structure, logging channels, endpoint prefixes, and external integration clients. This replaces manually writing 100+ lines of config.

**What it does**:
1. Detects language, framework, and logging library
2. Discovers all modules/bounded contexts and their log channels
3. Discovers external service clients and their log channels
4. Maps endpoint prefixes for each module
5. Presents findings for your review
6. Writes `support/data/codebase-profile.yaml` (reused by `/init-log-database`)
7. Populates the `[AUTO]` sections of `support/config.yaml`
8. Re-runs `install-skills.sh` to recompile skills with complete config values

**Outcome**: `config.yaml` is fully populated. `codebase-profile.yaml` caches the codebase analysis. All skills in `.claude/skills/` are compiled with correct paths and service-specific values.

## Step 7: Build the Log Database

In Claude Code:

```
/init-log-database
```

**Purpose**: Analyzes source code to catalog every log-producing code path in the service. This database drives the automated log analysis — without it, `/analyze-logs` can't map log entries to their meaning.

**What it does**:
1. Reads the codebase profile (skips re-discovery from Step 6)
2. For each module: finds exception handlers, logging decorators, and direct logger calls
3. Creates a typed entry for each log pattern (tag, severity, channel, trigger, meaning)
4. Builds a noise pattern list (health checks, debug lines, etc.) for filtering

**Outcome**: `support/data/log-database/log-types.yaml` and `LOG_DATABASE.md` — the complete log type database for your service.

## Step 8: Build the Knowledge Center

In Claude Code:

```
/init-knowledge-center
```

**Purpose**: Fetches historical Jira tickets, classifies them by service area and issue type, groups recurring patterns, and cross-references with the Log Database and codebase. This enables pattern matching — when a new ticket arrives, the toolkit can immediately suggest the likely root cause.

**What it does**:
1. Fetches tickets from Jira matching your service classification keywords
2. Filters out false positives (tickets mentioning your service incidentally)
3. Classifies each ticket by service area, resolution type, and root cause
4. Groups recurring patterns into issue entries with log signatures
5. Traces code paths for each pattern
6. Checks git history for fixes

**For new services with no history**: If the JQL search returns zero tickets, the skill scaffolds an empty but valid KC structure. The KC will grow automatically as you analyze tickets — `/analyze-logs` auto-drafts new patterns to `issues.yaml`, and `/update-knowledge-center` consolidates them.

**Outcome**: `support/data/knowledge-center/issues.yaml` and `KNOWLEDGE_CENTER.md` — the issue knowledge center for your service.

## Step 9: Test with a real ticket

```
/fetch-ticket YOUR-PROJECT-1234
```

**Purpose**: Validates the full pipeline by running an actual ticket investigation.

**Outcome**: If the ticket matches a Knowledge Center pattern, you'll see the suspected root cause and suggested resolution. If not, the toolkit will note that dynamic analysis is needed. Either way, this confirms everything is wired up correctly.

## Summary

| Step | Command | Creates |
|------|---------|---------|
| 1 | `git submodule add` | `support/toolkit/` |
| 2 | `bootstrap.sh` | Workspace dirs, starter `config.yaml`, `.gitignore` |
| 3 | Manual | `support/.env` |
| 4 | Manual | `config.yaml` manual fields filled |
| 5 | `/verify-jira-access` | Confirms Jira connectivity |
| 6 | `/init-workspace` | `codebase-profile.yaml`, auto-detected config, compiled skills |
| 7 | `/init-log-database` | `log-types.yaml`, `LOG_DATABASE.md` |
| 8 | `/init-knowledge-center` | `issues.yaml`, `KNOWLEDGE_CENTER.md` |
| 9 | `/fetch-ticket` | Validates the full pipeline |
