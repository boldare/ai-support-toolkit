---
name: generate-work-history
description: >
  Generates a Tempo-ready weekly work summary from ticket activity logs.
  Scans all ticket directories for activities within a time range, groups by
  date and ticket, estimates time per action, and writes a formatted summary.
  Use standalone for reporting; also runs automatically after each skill.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Generate Work History

You are generating a weekly work summary from ticket activity logs.

**Argument**: Time range (e.g., `/generate-work-history this week`, `/generate-work-history last week`, `/generate-work-history 2026-02-10 to 2026-02-14`)

If no time range is provided, default to **this week** (Monday to Friday of the current week).

## Current State

!`echo "=== This week ===" && date +%Y-W%V && echo "" && echo "=== Existing work history files ===" && ls {{WORKSPACE}}/tickets/work-history-*.md 2>/dev/null || echo "  None yet" && echo "" && echo "=== Tickets with activity logs ===" && (ls {{WORKSPACE}}/tickets/*/activity-log.yaml {{WORKSPACE}}/log-archive/*/activity-log.yaml 2>/dev/null | wc -l | tr -d ' ') && echo " activity logs found"`

## Instructions

### Step 1: Parse Time Range

Interpret the user's specification:
- **"this week"**: Monday to Friday of the current week
- **"last week"**: Monday to Friday of the previous week
- **"YYYY-MM-DD to YYYY-MM-DD"**: explicit date range
- **"week of YYYY-MM-DD"**: Monday-Friday of the week containing that date

Determine:
- Start date and end date
- ISO week number (`YYYY-WXX`) for the filename

```bash
date +%Y-W%V
```

### Step 2: Find Activity Logs

Scan both active and archived tickets:

```bash
ls {{WORKSPACE}}/tickets/*/activity-log.yaml {{WORKSPACE}}/log-archive/*/activity-log.yaml 2>/dev/null
```

### Step 3: Collect Activities in Range

For each activity log:
- Read the file
- Check each `activities` entry's `timestamp`
- Include entries where the date falls within the target range
- Collect: ticket_id, timestamp, action, description

### Step 4: Group and Sort

1. Group activities by date (YYYY-MM-DD)
2. Within each date, group by ticket
3. Sort chronologically within each group

### Step 5: Estimate Time per Activity

Apply default time estimates:

| Action | Minutes |
|--------|---------|
| ticket_fetched | 5 |
| log_request_prepared | 10 |
| data_request_prepared | 10 |
| log_analysis | 15 |
| analysis_verified | 10 |
| communication_with_support | 5 |
| communication_with_integration | 5 |
| logs_received | 5 |
| data_received | 5 |
| response_sent | 10 |
| manual_analysis | 15 |
| logs_renamed | 2 |

If `duration_seconds` is recorded in the activity entry and is not null, use that instead (convert to minutes, round to nearest 5).

### Step 6: Write Output

Write to `{{WORKSPACE}}/tickets/work-history-{YYYY}-W{XX}.md` following the template at `{{TOOLKIT}}/templates/work-history.md`.

Structure:
- One section per day that had activity (with day name and date)
- Table per day: Ticket | Activity Summary | Approx. Time
- Summary table at bottom: Ticket | Total Time | Current Status

For current status, check:
- `ticket-details.yaml` `status` field if available
- Whether `analysis.md` exists (analyzed)
- Whether `log-request.md` exists (log request sent)

### Step 7: Report

Display the summary:
```
=== Work History: Week {YYYY}-W{XX} ===

{N} tickets worked on, {M} activities across {D} days
Total estimated time: ~{T} minutes

Written to: {{WORKSPACE}}/tickets/work-history-{YYYY}-W{XX}.md
```

## Important Rules

- **Don't overcount** — if the same activity appears twice (e.g., duplicate log_activity calls), deduplicate by timestamp + action.
- **Round totals** to nearest 5 minutes.
- **Include all tickets** — both `tickets/` and `log-archive/` directories.
- **Don't create activity entries** — this skill only reads existing activity logs.
