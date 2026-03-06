---
name: update-log-database
description: >
  Incrementally maps unmapped ticket logs into the log type database.
  Processes up to 10 tickets per run, updating frequency data, discovering
  new log patterns, and improving examples. Use when new ticket logs are
  available or to continue mapping the backlog.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Update Log Database

You are maintaining the log type database for the {{DISPLAY_NAME}} M&S toolkit.

## Current State

!`echo "=== Mapped tickets ===" && grep -A200 'mapped_tickets:' {{WORKSPACE}}/data/log-database/log-types.yaml | grep '^\s*-' | wc -l | tr -d ' ' && echo "=== Total ticket directories ===" && ls -d {{WORKSPACE}}/log-archive/* 2>/dev/null | wc -l | tr -d ' '`

## Instructions

### Step 1: Read current state

Parse `{{WORKSPACE}}/data/log-database/log-types.yaml` to extract:
- The `mapped_tickets` list (tickets already analyzed)
- All known tag IDs (the `tag` field from each entry in `log_types`)
- Current `total_log_types` count

### Step 2: Find unmapped tickets

List all `{{WORKSPACE}}/log-archive/*` directories. Subtract the `mapped_tickets` list.

**Jira status guard** — For each candidate ticket, verify it's in a final Jira status:

```bash
bash {{TOOLKIT}}/scripts/check-ticket-status.sh {ticket_id}
```

Read `jira.final_statuses` from `{{WORKSPACE}}/config.yaml`. Only include tickets whose Jira status is in the `final_statuses` list.

If any tickets are skipped due to non-final status, report:
**"Skipped {N} tickets not in final Jira status: {list with current status}. Close them with `/close-ticket` or wait for Jira status update."**

If `.env` is not configured (no Jira access), skip the guard with a warning:
**"WARNING: Jira access not configured — cannot verify ticket status. Mapping all archived tickets."**

Sort remaining by ticket number **descending** (newest first). Take up to **10**.

If none remain, report **"All tickets mapped! (N/N)"** and stop.

### Step 3: Scan each unmapped ticket

For each ticket directory, use `grep` (not full file reads) across all `.txt` and `.json` files:

**a) Known tag scan** — Build a combined regex from all known tags and scan each ticket in one pass:
```bash
# Build combined pattern from all known tags (e.g., TAG1|TAG2|TAG3)
TAGS=$(grep '^\s*tag:' {{WORKSPACE}}/data/log-database/log-types.yaml | sed 's/.*tag: *"\(.*\)"/\1/' | paste -sd'|' -)
# Scan each ticket with one grep command instead of N
grep -oE "\[($TAGS)\]" {{WORKSPACE}}/log-archive/{ticket_id}/**/*.{txt,json} | sort | uniq -c | sort -rn
```
This produces a frequency count of which tags appear in each ticket. Record the results for all tickets in the batch before updating.

**b) New pattern discovery** — Broad scan for bracket-tagged patterns not in the known set:
```
grep -oE '\[[A-Z][A-Z0-9_]+\]' {{WORKSPACE}}/log-archive/{ticket_id}/**/*.{txt,json} | sort -u
```
For any new `[TAG]` patterns found that don't match existing tags, examine surrounding context (a few lines around each match) to classify them:
- Determine: `severity`, `channel`, `module`, `source` (best effort from context)
- Determine: `indicates` category (`external_integration_issue`, `expected_behavior`, `business_rule_rejection`, `data_quality_issue`, `internal_error`)
- Extract a real `example` line
- Create a new entry following the existing YAML schema

**c) Better examples** — If you find a real log line for any existing entry whose `example` looks synthetic/generic, capture the real one.

### Step 4: Update log-types.yaml

After scanning all tickets in this batch:

1. **Add new log types** discovered in step 3b, placed in the appropriate module section
2. **Update `common_in_tickets`** for ALL entries:
   - Count how many of the *total mapped tickets* (old + new) contain each tag
   - Set `common_in_tickets: true` if the tag appears in **>=30%** of all mapped tickets, `false` otherwise
3. **Replace examples** with better real examples found in step 3c
4. **Append** the newly processed ticket IDs to `mapped_tickets` (keep sorted by ticket number)
5. **Update `total_log_types`** count in metadata
6. **Update `generated`** date in metadata to today

### Step 5: Verify File Structure Against Template

Read `{{TOOLKIT}}/templates/log-types.yaml` and verify the updated file conforms to the schema:

1. **Metadata section** — must contain: `version`, `generated`, `source_commit`, `total_log_types`, `total_noise_patterns`, `mapped_tickets`
2. **Every log type entry** (including newly added ones) must have all required fields:
   - `id`, `tag`, `severity`, `channel`, `module`, `source`, `message_template`, `trigger`, `indicates`, `context_fields`, `common_in_tickets`, `example`
3. **Field values** — validate:
   - `severity` is one of: `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`
   - `indicates` is one of: `external_integration_issue`, `expected_behavior`, `business_rule_rejection`, `data_quality_issue`, `internal_error`
   - `common_in_tickets` is a boolean
   - `context_fields` is a list (can be empty `[]`)
4. **YAML parseable**: `python3 -c "import yaml; yaml.safe_load(open('{{WORKSPACE}}/data/log-database/log-types.yaml'))"`

Fix any missing fields or invalid values before proceeding.

### Step 6: Regenerate LOG_DATABASE.md

Rewrite `{{WORKSPACE}}/data/log-database/LOG_DATABASE.md` to reflect the updated data. Follow the existing format:
- Update the header line with new counts and date
- Update frequency columns to show `X/N` where N = total mapped tickets
- Update "Key insight" paragraphs if frequencies changed significantly
- Keep the same section structure (Quick Reference, Noise Patterns, Log Types by Module, Actionability Guide, Architecture Notes)

### Step 7: Report

Summarize what changed:
- Tickets processed (list them)
- New log types discovered (if any, list tag + module)
- Tags whose `common_in_tickets` flipped (true->false or false->true)
- Updated examples (if any)
- New totals: mapped tickets count, total log types count

## Important Rules

- **Never read entire log files** — they can be megabytes. Use grep for targeted scanning only.
- **Preserve existing YAML structure** — comments, section headers, ordering within sections.
- **Don't remove entries** — only add new ones or update fields on existing ones.
- **30% threshold** is based on total mapped tickets (old + new batch combined).
- **Sort mapped_tickets** by ticket number ascending.
- **Validate** the YAML is parseable after editing: `python3 -c "import yaml; yaml.safe_load(open('{{WORKSPACE}}/data/log-database/log-types.yaml'))"`.
