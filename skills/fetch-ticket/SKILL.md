---
name: fetch-ticket
description: >
  Fetches a Jira ticket and generates ticket-details.yaml with structured data.
  Automatically matches the ticket against Knowledge Center patterns and reports
  the suspected issue. Use as the first step when investigating a new ticket.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, AskUserQuestion
---

# Fetch Ticket

You are fetching a Jira ticket and preparing it for investigation.

**Argument**: Ticket ID (e.g., `/fetch-ticket PROJ-123`)

If no ticket ID is provided, ask the user for one.

## Current State

!`echo "=== Jira access ===" && ([ -f {{TOOLKIT}}/.env ] && echo "Configured (.env exists)" || echo "NOT CONFIGURED — run /verify-jira-access first") && echo "" && echo "=== Knowledge Center ===" && ([ -f {{WORKSPACE}}/data/knowledge-center/issues.yaml ] && echo "$(grep 'total_patterns:' {{WORKSPACE}}/data/knowledge-center/issues.yaml | head -1 | tr -d ' ') patterns available" || echo "Not initialized")`

## Instructions

### Step 1: Validate Prerequisites

Check that the ticket ID matches the expected format (`^[A-Z]+-[0-9]+$`).

If `{{TOOLKIT}}/.env` doesn't exist, tell the user: **"Run `/verify-jira-access` first to configure Jira credentials."** and stop.

### Step 2: Run Fetch Script

```bash
bash {{TOOLKIT}}/scripts/fetch-ticket.sh {ticket_id}
```

If the user provided a `--context` value, pass it through:
```bash
bash {{TOOLKIT}}/scripts/fetch-ticket.sh {ticket_id} --context "{context}"
```

If the script fails, report the error and help the user troubleshoot:
- **404**: "Ticket not found — check the ticket ID"
- **401**: "Authentication failed — run `/verify-jira-access`"
- **000**: "Cannot reach Jira server — check your network/VPN"

### Step 3: Read Generated Ticket Details

Read the generated file:
```
{{WORKSPACE}}/tickets/{ticket_id}/ticket-details.yaml
```

Extract and display to the user:
- Summary
- Status and priority
- Key identifiers found (from `config.yaml` `identifiers` patterns, plus dates)
- Service area guess

### Step 4: Match Against Knowledge Center

Read `{{WORKSPACE}}/data/knowledge-center/issues.yaml`.

For each `issue_patterns` entry, compare against the ticket:

1. **Keywords**: Does the ticket summary/description contain words from the pattern's `title` or `root_cause`?
2. **Service area**: Does the pattern's `service_area` match the ticket's `extracted.service_area_guess`?
3. **Error signatures**: Do `extracted.error_messages` match any `log_signatures` descriptions?
4. **External service**: Do the errors reference a known external service from `config.yaml` `integrations`?

Score each match:
- **High**: 2+ signals match (keywords + service area, or keywords + error signature)
- **Medium**: 1 signal matches clearly
- **Low**: Weak/partial match only
- **None**: No meaningful match

### Step 5: Persist KC Match

If a pattern matched (any confidence), update `ticket-details.yaml` to add the `kc_match` section:

```yaml
kc_match:
  pattern_id: "{matched_pattern_id}"
  confidence: "{high|medium|low}"
  title: "{pattern_title}"
  category: "{pattern_category}"
  service_area: "{pattern_service_area}"
  external_service: "{pattern_external_service or null}"
  log_signatures:
    required:
      - tag: "{tag_name}"
        channel: "{channel_name}"
    supporting:
      - tag: "{tag_name}"
        channel: "{channel_name}"
  resolution:
    action: "{resolution_action}"
    recipient: "{resolution_recipient}"
    response_template: "{key points from resolution.response_template or null}"
  data_queries_needed: {true|false}
```

This allows downstream skills (`/generate-log-request`, `/generate-data-request`, `/analyze-logs`) to read the match directly from `ticket-details.yaml` instead of re-scanning the full `issues.yaml`.

If no pattern matched, leave `kc_match.pattern_id` as `null`.

### Step 6: Report to User

Present the findings:

```
=== Ticket Fetched: {ticket_id} ===

Summary: {summary}
Status: {status} | Priority: {priority}
Service Area: {service_area_guess}

Identifiers:
  {for each identifier type from config.yaml: name — list or "none detected"}
  - Key dates: {list}

Suspected Pattern: {pattern_id} — "{pattern_title}" (confidence: {level})
  Category: {category}
  Expected resolution: {resolution.action}

Ticket details: {{WORKSPACE}}/tickets/{ticket_id}/ticket-details.yaml
```

If no pattern matches: **"No known pattern match. Dynamic analysis will be needed."**

If multiple patterns match with similar confidence, list the top 2-3 and ask: **"Which pattern seems most likely, or should I proceed with the top match?"**

### Step 7: Check for Existing Logs

Check if log files already exist:
```bash
ls {{WORKSPACE}}/tickets/{ticket_id}/logs/ 2>/dev/null
ls {{WORKSPACE}}/log-archive/{ticket_id}/ 2>/dev/null
```

If logs exist in `log-archive/` but not `tickets/`, suggest:
```
Log files found in log-archive/{ticket_id}/. Copy them to the ticket directory?
```

If the user confirms, copy and run rename:
```bash
cp {{WORKSPACE}}/log-archive/{ticket_id}/* {{WORKSPACE}}/tickets/{ticket_id}/logs/
bash {{TOOLKIT}}/scripts/rename-logs.sh {{WORKSPACE}}/tickets/{ticket_id}/logs/
```

### Step 8: Auto-Log and Update Work History

```bash
bash {{TOOLKIT}}/scripts/log-activity.sh {ticket_id} "ticket_fetched" "Fetched ticket details (status: {status}, pattern: {pattern_id_or_none})"
```

Then regenerate work history for the current week by following `{{TOOLKIT}}/skills/generate-work-history/SKILL.md` Steps 1–6 (default time range: this week).

### Step 9: Suggest Next Steps

Based on findings:
- If logs already exist: **"Logs are available. Run `/analyze-logs {ticket_id}` to analyze."**
- If no logs: **"Run `/generate-log-request {ticket_id}` to prepare a log request for the support team."**
- If pattern match suggests data is needed: **"This pattern may require production data. Run `/generate-data-request {ticket_id}` after analysis."**

## Important Rules

- **Never display the full API token** — only first/last 4 characters if debugging.
- **Don't modify `issues.yaml`** during this skill — only read it for pattern matching.
- **Ticket details are the source of truth** — if the script's extraction looks wrong, note it but don't override.
- **Always run the work history regeneration** — even if the main task fails, log what happened.
