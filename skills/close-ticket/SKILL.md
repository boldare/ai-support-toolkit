---
name: close-ticket
description: >
  Archives a completed ticket by moving it from tickets/ to log-archive/.
  Optionally checks Jira status to confirm the ticket is in a final state.
  Use after analysis is complete and the response has been sent.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Close Ticket

**Argument**: Ticket ID (e.g., `/close-ticket PROJ-123`)

## Current State

!`echo "=== Active tickets ===" && for d in {{WORKSPACE}}/tickets/*/; do [ -d "$d" ] && t=$(basename "$d") && [[ "$t" != work-history-* ]] && echo "  $t: $([ -f "$d/analysis.md" ] && echo "analyzed" || echo "not analyzed") | $([ -f "$d/ticket-details.yaml" ] && echo "fetched" || echo "not fetched")"; done || echo "  No active tickets"`

## Instructions

### Step 1: Validate Ticket Exists

Check that `{{WORKSPACE}}/tickets/{ticket_id}/` exists.
If not: **"Ticket directory not found. Nothing to close."** and stop.

Check that `{{WORKSPACE}}/tickets/{ticket_id}/ticket-details.yaml` exists.
If not: **"Ticket was never fetched. Run `/fetch-ticket {ticket_id}` first."** and stop.

### Step 2: Check Analysis Status

Check if `{{WORKSPACE}}/tickets/{ticket_id}/analysis.md` exists.
If not: warn **"This ticket has not been analyzed yet. Close anyway?"**
- If user says no -> stop
- If user says yes -> continue

### Step 3: Check Jira Status (Safety Guard)

Read `jira.final_statuses` from `{{WORKSPACE}}/config.yaml`.

Fetch current Jira status:
```bash
bash {{TOOLKIT}}/scripts/check-ticket-status.sh {ticket_id}
```

This returns the current status name. Check if it's in the `final_statuses` list.

- If status IS final -> proceed
- If status is NOT final -> warn: **"Ticket is still '{status}' in Jira (not a final status). Close anyway?"**
  - If user confirms -> proceed with warning noted
  - If user declines -> stop
- If the script fails (no .env, no Jira access) -> warn: **"Could not check Jira status. Close anyway?"**
  - If user confirms -> proceed (note "Jira status: unknown")
  - If user declines -> stop

### Step 4: Archive

Move the entire ticket directory:
```bash
bash {{TOOLKIT}}/scripts/close-ticket.sh {ticket_id}
```

If the script exits with code 2 (archive directory already exists): **"Archive directory already exists. Overwrite?"**
- If yes: `rm -rf {{WORKSPACE}}/log-archive/{ticket_id}` then re-run the script
- If no: stop

### Step 5: Log Activity

The ticket is now in `log-archive/`. Write the activity log entry directly to the archived location:

```bash
# Append closure entry to the archived ticket's activity log
cat >> {{WORKSPACE}}/log-archive/{ticket_id}/activity-log.yaml <<EOF
  - timestamp: "$(date -u '+%Y-%m-%dT%H:%M:%S')"
    action: "ticket_closed"
    description: "Ticket archived to log-archive/ (Jira status: {status})"
    duration_seconds: null
    source: "close-ticket"

EOF
```

Note: Do NOT use `log-activity.sh` or `log_activity()` from common.sh here — those functions use `ensure_ticket_dir` which creates the directory under `tickets/`. Since the ticket has been moved to `log-archive/`, write the activity log entry directly.

### Step 6: Update Work History

Regenerate work history: follow `{{TOOLKIT}}/skills/generate-work-history/SKILL.md` Steps 1-6.

### Step 7: Report

```
=== Ticket Closed: {ticket_id} ===

Jira status: {status}
Analysis: {present or absent}
Log files: {count} files archived
Data files: {count} files archived

Archived to: {{WORKSPACE}}/log-archive/{ticket_id}/

This ticket is now eligible for:
  - /update-log-database (log pattern mapping)
  - /update-knowledge-center (KC pattern consolidation)
```

### Step 8: Suggest Next Steps

- If other active tickets exist: **"Remaining active tickets: {list}. Continue with `/fetch-ticket` or `/analyze-logs`."**
- If many closed tickets unmapped: **"You have {N} unmapped archived tickets. Run `/update-log-database` to enrich the log database."**

## Important Rules

- **Never delete ticket data** — only move it.
- **Always check for existing archive directory** before moving.
- **Log the closure** — the activity log is the audit trail.
- **Jira status check is advisory, not blocking** — user can override. Some tickets get investigated before Jira is updated.
