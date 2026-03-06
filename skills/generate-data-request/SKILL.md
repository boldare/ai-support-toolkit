---
name: generate-data-request
description: >
  Generates SQL queries for the support team to run against the production
  PostgreSQL database. Discovers table schemas from Doctrine entities and
  builds queries with ticket-specific filters. Use when log analysis indicates
  production data is needed to confirm root cause.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Generate Data Request

You are generating SQL queries for the support team to run against the production database.

**Argument**: Ticket ID (e.g., `/generate-data-request PROJ-123`)

If no ticket ID is provided, ask the user for one.

## Current State

!`echo "=== Active tickets ===" && for d in {{WORKSPACE}}/tickets/*/; do [ -d "$d" ] && t=$(basename "$d") && echo "  $t: $([ -f "$d/ticket-details.yaml" ] && echo "fetched" || echo "not fetched") | $([ -f "$d/data-request.md" ] && echo "data request exists" || echo "no data request") | $([ -f "$d/analysis.md" ] && echo "analyzed" || echo "not analyzed")"; done || echo "  No active tickets"`

## Prerequisites

Read `{{WORKSPACE}}/tickets/{ticket_id}/ticket-details.yaml`.

If it doesn't exist: **"Ticket not fetched yet. Run `/fetch-ticket {ticket_id}` first."** and stop.

## Instructions

### Step 1: Determine Data Questions

Identify what production data would help investigate this ticket from multiple sources:

**From `{{WORKSPACE}}/tickets/{ticket_id}/analysis.md`** (if exists):
- Look for "Production Data Needed" section or unanswered questions about data state

**From `ticket-details.yaml`**:
- Data discrepancies, missing records, wrong statuses mentioned in description/comments

**From KC match** (read `kc_match` section in `ticket-details.yaml`):
- If `kc_match.data_queries_needed` is true, this pattern is known to require data verification
- Check `kc_match.category` for data-related categories (e.g., `data_quality_issue`)
- **Only if `kc_match` section is missing entirely**: fall back to reading `{{WORKSPACE}}/data/knowledge-center/issues.yaml`

Common data questions:
- What is the current status of the relevant entity?
- What does the record look like for the primary identifier?
- Are there duplicate records?
- What is the timeline of status changes?
- What data did we store from the external API response?

### Step 2: Discover Table Schemas

For each data question, find the relevant Doctrine entity:

1. Identify the module from the service area (use the module path from `codebase-profile.yaml`)
2. Read the entity files to find:
   - Table name (from `#[ORM\Table(name: "...")]` or class name convention)
   - Column names and types
   - Relationships (foreign keys)
3. Note any enum columns and their possible values

Use `Glob` and `Grep` to discover entities:
```
api/src/Module/{Module}/Domain/Entity/*.php
```

### Step 3: Generate SQL Queries

For each data question, write a PostgreSQL query:

- Use exact table and column names from the Doctrine entities
- Filter by ticket-specific identifiers (establishment ID, border number, etc.)
- Include `ORDER BY` for timestamp columns (most recent first)
- Add `LIMIT 50` to prevent oversized results
- Use clear column aliases where helpful
- Add SQL comments explaining what each part does

### Step 4: Write Output

Write to `{{WORKSPACE}}/tickets/{ticket_id}/data-request.md` following the template at `{{TOOLKIT}}/templates/data-request.md`.

For each query, include:
- A descriptive title
- The SQL query in a code block
- "What to look for" — what normal vs. problematic results look like

### Step 5: Auto-Log and Update Work History

```bash
bash {{TOOLKIT}}/scripts/log-activity.sh {ticket_id} "data_request_prepared" "Generated {N} SQL queries for production data"
```

Then regenerate work history for the current week by following `{{TOOLKIT}}/skills/generate-work-history/SKILL.md` Steps 1–6 (default time range: this week).

### Step 6: Report and Suggest Next Steps

- **"Data request written to `{{WORKSPACE}}/tickets/{ticket_id}/data-request.md`. Share with the support team."**
- **"After receiving results, place them in `{{WORKSPACE}}/tickets/{ticket_id}/data/` and run `/analyze-logs {ticket_id}`."**

## Output Checklist

Before finishing, verify:
- [ ] Table/column names match Doctrine entities (not guessed)
- [ ] Queries use ticket-specific identifiers as filters
- [ ] Each query has a clear purpose explained
- [ ] Results are limited to prevent huge dumps
- [ ] PostgreSQL syntax is correct (not MySQL)
- [ ] File written to correct path
- [ ] Activity logged and work history updated
