---
name: generate-log-request
description: >
  Generates a LogQL query and log request document for the support team to fetch
  Grafana logs. Reads ticket details, matches Knowledge Center patterns, builds
  an optimized query with noise exclusions, and determines the time range.
  Use after fetching a ticket with /fetch-ticket.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Generate Log Request

You are generating a LogQL query and log request document for the support team.

**Argument**: Ticket ID (e.g., `/generate-log-request PROJ-123`)

If no ticket ID is provided, ask the user for one.

## Current State

!`echo "=== Active tickets ===" && ls -d {{WORKSPACE}}/tickets/* 2>/dev/null | while read d; do t=$(basename "$d"); echo "  $t: $([ -f "$d/ticket-details.yaml" ] && echo "fetched" || echo "not fetched") | $([ -f "$d/log-request.md" ] && echo "log request exists" || echo "no log request")"; done || echo "  No active tickets"`

## Prerequisites

Read `{{WORKSPACE}}/tickets/{ticket_id}/ticket-details.yaml`.

If it doesn't exist: **"Ticket not fetched yet. Run `/fetch-ticket {ticket_id}` first."** and stop.

## Instructions

### Step 1: Extract Identifiers from Ticket

From `ticket-details.yaml`, collect:
- **Primary identifier**: the most specific filter — an identifier from `extracted.identifiers`, or a unique error string
- **Supporting identifiers**: additional IDs, dates, endpoints
- **Service area**: from `extracted.service_area_guess`
- **Additional context**: from `additional_context` field

### Step 2: Read KC Match

Read the `kc_match` section from `ticket-details.yaml` (populated by `/fetch-ticket`).

- If `kc_match.pattern_id` is not null: use the persisted match data (confidence, log_signatures, resolution)
- If `kc_match.pattern_id` is null: **"No known pattern match — dynamic query generated."**
- **Only if `kc_match` section is missing entirely** (ticket fetched before this optimization): fall back to reading `{{WORKSPACE}}/data/knowledge-center/issues.yaml` and scanning all patterns manually

### Step 3: Determine Relevant Log Channels

Read `{{WORKSPACE}}/config.yaml`. Find the module(s) matching the service area under `modules`:
- Get their `log_channels` list
- If a KC pattern matched, include channels from `kc_match.log_signatures.required` and `kc_match.log_signatures.supporting`
- Always include `unhandled_exceptions` and `framework_exceptions` as fallback

### Step 4: Build LogQL Query

Construct the query:

```logql
{app="{{APP_LABEL}}", namespace="{{NAMESPACE}}"}
  |= "{primary_identifier}"
  != "Matched route"
  != "/health"
  != "/readiness"
  != "/liveness"
  != "http_client.INFO: Response: \"20"
  != "OPTIONS HTTP"
  != "Container starting"
  != "Container started"
```

Rules:
- **`|=`** filter: use the primary identifier (establishment ID, border number, or error keyword)
- **`!=`** filters: include the most impactful noise patterns from `{{WORKSPACE}}/data/log-database/log-types.yaml` `noise_patterns`
- If the primary identifier is very common (e.g., a short date), add a second `|=` filter for the channel name
- Do NOT over-filter — capture surrounding context, not just the exact error line

### Step 5: Determine Time Range

- Use dates from `ticket-details.yaml` (`extracted.dates_mentioned`, `created` date)
- Add **1-day buffer** before the earliest date and after the latest date
- Express in the timezone specified in `config.yaml` `loki.timezone`
- If no specific dates found, use the ticket creation date +/- 2 days

### Step 6: Estimate Size and Set Line Limit

- Default line limit: **5000**
- Time range > 3 days: increase to **10000**
- Very specific query (unique error string): reduce to **2000**
- Estimate: ~0.5KB per line (5000 lines = ~2.5MB)

### Step 7: Assess Production Data Need

Check if the matched KC pattern mentions data queries or data verification. Also assess:
- Does the ticket mention data discrepancies?
- Is the issue about missing/wrong records (not API errors)?
- Would database state help confirm the root cause?

If yes: note that `/generate-data-request` should be run next.

### Step 8: Write Output

Write to `{{WORKSPACE}}/tickets/{ticket_id}/log-request.md` following the template at `{{TOOLKIT}}/templates/log-request.md`.

### Step 9: Auto-Log and Update Work History

```bash
bash {{TOOLKIT}}/scripts/log-activity.sh {ticket_id} "log_request_prepared" "Generated LogQL query (pattern: {pattern_id_or_none}, confidence: {level})"
```

Then regenerate work history for the current week by following `{{TOOLKIT}}/skills/generate-work-history/SKILL.md` Steps 1–6 (default time range: this week).

### Step 10: Report and Suggest Next Steps

Display the generated log request summary, then:
- **"Log request written to `{{WORKSPACE}}/tickets/{ticket_id}/log-request.md`. Share with the support team."**
- If production data needed: **"Also run `/generate-data-request {ticket_id}` for SQL queries."**
- **"After receiving logs, place them in `{{WORKSPACE}}/tickets/{ticket_id}/logs/` and run `/analyze-logs {ticket_id}`."**

## Output Checklist

Before finishing, verify:
- [ ] LogQL query is syntactically valid
- [ ] Time range covers the incident period with buffer
- [ ] Primary identifier is the most specific available filter
- [ ] Noise exclusions are included
- [ ] Line limit is appropriate for the time range
- [ ] Production data need is assessed
- [ ] File written to correct path
- [ ] Activity logged and work history updated
