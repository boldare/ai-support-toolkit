---
name: init-knowledge-center
description: >
  Builds the Issue Knowledge Center from Jira ticket analysis, log database
  cross-referencing, and codebase tracing. Fetches tickets, classifies them
  by service area and issue type, groups recurring patterns, and produces
  issues.yaml + KNOWLEDGE_CENTER.md. Requires Jira API access and a populated
  log database. Use on first setup or to rebuild from scratch.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, AskUserQuestion, Task, WebFetch
---

# Init Knowledge Center

You are building the Issue Knowledge Center for the M&S toolkit by analyzing historical Jira tickets.

This skill forms the second stage of the data pipeline:
1. **`/init-log-database`** — builds the log type database from codebase analysis
2. **`/init-knowledge-center`** (this skill) — builds the issue knowledge center from ticket analysis
3. **`/update-log-database`** — enriches the log database with real ticket log data

## Current State

!`echo "=== Knowledge Center exists? ===" && ([ -f {{WORKSPACE}}/data/knowledge-center/issues.yaml ] && echo "YES — $(grep 'total_patterns:' {{WORKSPACE}}/data/knowledge-center/issues.yaml | head -1 | tr -d ' ')" || echo "NO — fresh init needed") && echo "" && echo "=== Log Database exists? ===" && ([ -f {{WORKSPACE}}/data/log-database/log-types.yaml ] && echo "YES — $(grep 'total_log_types:' {{WORKSPACE}}/data/log-database/log-types.yaml | head -1 | tr -d ' ')" || echo "NO — run /init-log-database first") && echo "" && echo "=== Jira access configured? ===" && ([ -f {{TOOLKIT}}/.env ] && echo "YES (.env exists)" || echo "NO — run /verify-jira-access first") && echo "" && echo "=== Ticket logs available? ===" && echo "$(ls -d {{WORKSPACE}}/log-archive/* {{WORKSPACE}}/tickets/* 2>/dev/null | wc -l | tr -d ' ') ticket directories found"`

## Prerequisites

Before running this skill:
1. **Jira API access** must be configured (run `/verify-jira-access`)
2. **Log Database** should be populated (run `/init-log-database`)
3. **config.yaml** must exist with service classification keywords

---

## Phase 1: Fetch Historical Tickets

### Step 1: Load Configuration

Read `{{WORKSPACE}}/config.yaml` to extract:
- `jira.base_url`, `jira.project_key`
- `service_classification.keywords` — terms that identify this service's tickets

Read `{{TOOLKIT}}/.env` to get credentials:
- `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`

### Step 2: Build JQL Query

Construct a JQL query that finds tickets related to this service. Use the keywords from config:

```
project = {project_key} AND (
  summary ~ "keyword1" OR summary ~ "keyword2" OR
  description ~ "keyword1" OR description ~ "keyword2" OR
  comment ~ "keyword1" OR comment ~ "keyword2"
)
ORDER BY created DESC
```

Present the JQL query and ask: **"Does this JQL look correct? Any adjustments?"**

### Step 3: Fetch Tickets

Use the Jira REST API to fetch all matching tickets with pagination:

```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE_URL/rest/api/3/search?jql={encoded_jql}&maxResults=100&startAt={offset}&fields=summary,description,status,resolution,priority,created,resolutiondate,labels,assignee,reporter,issuetype,comment"
```

For each ticket, also fetch comments:
```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_BASE_URL/rest/api/3/issue/{key}/comment"
```

**Extract lightweight ticket records** — For each fetched ticket, extract only these fields into a compact format before storing. Do NOT pass raw Jira JSON to subagents.

```yaml
# Lightweight ticket record (one per ticket)
- key: "{ticket_id}"
  summary: "{summary text}"
  status: "{status name}"
  resolution: "{resolution name or null}"
  priority: "{priority name}"
  created: "{date}"
  labels: ["{label1}", "{label2}"]
  description_text: "{plain text, max 2000 chars, stripped of ADF/HTML}"
  comments_text: |
    [{author}, {date}]: {comment body, max 500 chars each}
    ...
  # Only include first 10 comments, most recent first
```

This reduces each ticket from ~5-20KB of raw JSON to ~1-3KB of structured text. Report: **"Fetched {N} tickets. Proceeding to classification."**

**Zero tickets found** — This is expected for brand new services. Scaffold an empty but valid KC:

1. Create `{{WORKSPACE}}/data/knowledge-center/issues.yaml` with:
   - Full metadata section (version, service name, dates, counts at 0)
   - All six category definitions (from template at `{{TOOLKIT}}/templates/issues.yaml`)
   - Empty `issue_patterns: []`
   - Empty statistics

2. Create `{{WORKSPACE}}/data/knowledge-center/KNOWLEDGE_CENTER.md` with header noting "No patterns yet — KC will grow as tickets are analyzed."

3. Report:
```
=== Knowledge Center Initialized (Empty) ===

No historical tickets found matching service keywords.
This is normal for new services.

The KC will grow automatically as you analyze tickets:
  1. Run /fetch-ticket + /analyze-logs on incoming tickets
  2. New patterns are auto-drafted to issues.yaml
  3. Run /update-knowledge-center periodically to consolidate

Files created:
  - {{WORKSPACE}}/data/knowledge-center/issues.yaml (empty scaffold)
  - {{WORKSPACE}}/data/knowledge-center/KNOWLEDGE_CENTER.md
```

Skip Phases 2 and 3 (classification and pattern building) — there's nothing to classify. **Stop here.**

### Step 4: Exclude False Positives

Review the fetched tickets. The JQL `text ~` search can match tickets from other services if they mention our keywords incidentally.

**Negative signals** (likely false positive):
- Ticket primarily discusses a different service
- Our keywords only appear in tangential comments
- No establishment numbers or endpoints matching our service

**If an exclusion list exists** (from a previous run), apply it automatically.

Ask: **"I found {N} potential false positives. Review them?"** Show the list with brief reasons.

Store exclusions in `{{WORKSPACE}}/data/knowledge-center/excluded-tickets.yaml` for future runs.

---

## Phase 2: Classify and Build Issue Patterns

### Step 5: Classify Tickets

For each ticket (use subagents for parallelism — batch lightweight ticket records into groups of ~50):

Extract:
- **Service area**: Use module names from `config.yaml` `modules` section
- **Issue subtype**: specific issue within the service area
- **Resolution type**: external_integration_issue, expected_behavior, actual_bug, business_rule_rejection, data_quality_issue, insufficient_info
- **External service** involved: Use integration names from `config.yaml` `integrations` section, or "none"
- **Root cause summary**: 1-line description

Output format per ticket:
```
KEY | SERVICE_AREA | ISSUE_SUBTYPE | RESOLUTION_TYPE | EXTERNAL_SERVICE | ROOT_CAUSE_SUMMARY
```

### Step 6: Group Into Issue Patterns

Analyze the classification results to identify recurring patterns:
- Group tickets with the same service_area + issue_subtype + resolution_type
- For each group with 2+ tickets, create an issue pattern
- Single-ticket issues become patterns only if they represent a clear, distinct category

For each pattern, determine:
- **id**: snake_case identifier
- **title**: human-readable description
- **category**: from the resolution_type
- **frequency**: very_common (10+), common (5-9), occasional (2-4), rare (1)
- **service_area**: from classification
- **status**: confirmed (if clear pattern) or draft (if uncertain)

### Step 7: Cross-Reference with Log Database

Read `{{WORKSPACE}}/data/log-database/log-types.yaml` — for this one-time init, reading the full file is acceptable since you need to match across all modules. For each issue pattern:

1. **Match log signatures**: Which log types from the database would appear for this issue?
   - `required`: Log types that MUST appear for this pattern (reference by `tag` and `channel`)
   - `supporting`: Log types that often appear alongside
2. **Add channel information** from the log database entries
3. **Note any log types** mentioned in ticket comments

### Step 8: Cross-Reference with Codebase

For each issue pattern, use subagents to trace through the codebase. Each subagent should return results in this format:

```
PATTERN_ID | file_path:line | description
```

Trace:
1. **Code path**: Controller → Handler → Adapter chain that produces the observed logs
2. **External service calls**: Which adapters/clients are involved
3. **Business rules**: Any validation that might trigger the issue
4. **Exception hierarchy**: How domain exceptions map to HTTP responses

Add results as `code_references` with file paths and line numbers.

### Step 9: Check Git History for Fixes

For patterns with `status: fixed` or `fix_reference`:
- Search git log for the referenced ticket/commit
- Verify the fix exists and note the commit hash
- Check which release tag includes the fix

Add results as `git_references`.

---

## Phase 3: Write Output Files

### Step 10: Write issues.yaml

Create `{{WORKSPACE}}/data/knowledge-center/issues.yaml` following the issues.yaml template schema at `{{TOOLKIT}}/templates/issues.yaml`.

Include:
- Header metadata (version, date, total_patterns, total_tickets_classified)
- Statistics section (by_service_area, by_resolution_type, by_external_service)
- Categories section
- All issue patterns with full detail

### Step 11: Write KNOWLEDGE_CENTER.md

Generate `{{WORKSPACE}}/data/knowledge-center/KNOWLEDGE_CENTER.md` from the YAML:
- Key statistics table
- Code path architecture section (from codebase traces)
- Patterns organized by service area
- Fixed bugs summary table with git commits
- Triage decision tree
- Hotfix release timeline

### Step 12: Validate

**a) YAML parsing**:
```bash
python3 -c "import yaml; yaml.safe_load(open('{{WORKSPACE}}/data/knowledge-center/issues.yaml'))"
```

**b) Pattern count**:
```bash
python3 -c "
import re
with open('{{WORKSPACE}}/data/knowledge-center/issues.yaml', 'r') as f:
    content = f.read()
patterns = re.findall(r'^\s+- id:', content, re.MULTILINE)
print(f'Patterns: {len(patterns)}')
"
```

**c) Verify file structure against template**:

Read `{{TOOLKIT}}/templates/issues.yaml` and verify the generated file conforms to the schema:

1. **Top-level fields** — must contain:
   - `version`, `service`, `last_updated`, `total_patterns`, `total_tickets_classified`

2. **Statistics section** — must contain:
   - `by_service_area`, `by_resolution_type`, `by_external_service`

3. **Categories section** — each category must have:
   - `description`, `default_action`, `ticket_count`
   - All six categories must be present: `expected_behavior`, `external_integration_issue`, `business_rule_rejection`, `actual_bug`, `data_quality_issue`, `insufficient_info`

4. **Issue pattern entries** — each entry must have all required fields:
   - `id`, `title`, `category`, `frequency`, `service_area`, `status`
   - `log_signatures` with `required` and `supporting` lists (each entry: `log_type`, `channel`; `note` is optional)
   - `root_cause`, `verification_steps`
   - `resolution` with `action`, `response_template`, `respond_to`
   - `example_tickets` (each: `ticket`, `date`, `notes`)
   - `code_references` (each: `file`, `context`; `lines` is optional)
   - `data_queries` is optional (not all patterns need SQL queries)

5. **Field values** — validate:
   - `category` matches a key in the categories section
   - `frequency` is one of: `very_common`, `common`, `occasional`, `rare`
   - `status` is one of: `confirmed`, `draft`
   - `total_patterns` matches the actual count of patterns in `issue_patterns`

Report any missing fields or invalid values before proceeding.

### Step 13: Report

```
=== Init Knowledge Center Complete ===

Tickets fetched:     {N}
False positives:     {N} excluded
Tickets classified:  {N}
Issue patterns:      {N}
  - Confirmed:       {N}
  - Draft:           {N}
Service areas:       {list with counts}
Resolution types:    {list with counts}
Code references:     {N} patterns with code refs
Git references:      {N} patterns with git refs

Files created:
  - {{WORKSPACE}}/data/knowledge-center/issues.yaml
  - {{WORKSPACE}}/data/knowledge-center/KNOWLEDGE_CENTER.md
  - {{WORKSPACE}}/data/knowledge-center/excluded-tickets.yaml

Next steps:
  - Review KNOWLEDGE_CENTER.md for accuracy
  - Change draft patterns to confirmed after review
  - Run /update-log-database to enrich log database with ticket data
```

---

## Important Rules

- **Use subagents for parallelism** — classification and codebase tracing can be done in parallel batches.
- **Never read entire log files** — if checking log directories, use grep only.
- **Batch Jira API calls** — respect rate limits, use pagination.
- **Preserve existing exclusions** — if `excluded-tickets.yaml` exists, apply those exclusions automatically.
- **Cross-reference, don't duplicate** — log signatures should reference log types by their `tag` from log-types.yaml, not re-describe them.
- **Confidence over completeness** — it's better to have fewer confirmed patterns than many uncertain ones. Use `status: draft` for uncertain patterns.
- **Token management** — ticket data can be large. Use the extract-ticket-text.py pattern to pre-process raw ticket JSONs before classification.
