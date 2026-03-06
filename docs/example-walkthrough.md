# Example: Working a Ticket End-to-End

Here's what a complete investigation looks like for a sample ticket.

## Step 1: Fetch the ticket

```
> /fetch-ticket ABCD-1660
```

Output:
```
=== Ticket Fetched: ABCD-1660 ===

Summary: Module request failing for company 12345678
Status: Open | Priority: Medium
Service Area: *Module Name*

Identifiers:
  - Company IDs: 1231212, 1234254, 13482993, 12389493
  - Key dates: 2026-02-10, 2026-02-11

Suspected Pattern: integration-module-failure — "Integration API for a module check failure" (confidence: high)
  Category: external_integration_issue
  Expected resolution: external_integration_response

Ticket details: logs/tickets/ABCD-1660/ticket-details.yaml
```

The skill fetched the ticket from Jira, extracted identifiers, matched it against the Knowledge Center, and saved the match in `ticket-details.yaml` for downstream skills.

**Next step suggested**: "Run `/generate-log-request ABCD-1660` to prepare a log request for the support team."

## Step 2: Generate log request

```
> /generate-log-request ABCD-1660
```

The skill reads the KC match from `ticket-details.yaml` (no need to re-scan the full KC), builds a LogQL query optimized for this ticket:

```logql
{app="app-name", namespace="namespace-prod"}
  |= "12345678"
  != "Matched route"
  != "/health"
  ...
```

Output saved to `logs/tickets/ABCD-1660/log-request.md`. Copy the LogQL query and time range to the support team.

## Step 3: Receive and place logs

After the support team exports the logs from Grafana:

1. Place the downloaded files in `logs/tickets/ABCD-1660/logs/`
2. Rename them (optional — the analyze skill handles any format):

```bash
bash logs/toolkit/scripts/rename-logs.sh logs/tickets/ABCD-1660/logs/
# Renamed 7 files: Explore-logs-2026-02-10... -> 2026-02-10_api-prod.txt
```

## Step 4: Analyze

```
> /analyze-logs ABCD-1660
```

The skill:
1. Reads the ticket context and KC match
2. Pre-filters logs via grep (extracts only ERROR/CRITICAL + identifier-matching lines)
3. Removes noise (health checks, cache debug, etc.)
4. Matches filtered lines against the KC pattern's log signatures
5. Builds a timeline from actual timestamps
6. Runs a built-in verification pass (checks for missed errors, contradictions, timeline gaps)
7. Generates a response for the appropriate team

Output:
```
=== Analysis: ABCD-1660 ===

Category: External Integration Issue
Confidence: 95%
Pattern: integration-module-failure
Verification: CONFIRMED

Root Cause: *Integration name& returned 502/timeout errors during Feb 10-11,
causing module/create to fail after ~55s for company ID 12345678.

Response for: Integration Team
```

The analysis and recommended response are written to `logs/tickets/ABCD-1660/analysis.md`.

## Step 5: (If needed) Request production data

If the analysis identifies data questions, or if the root cause is unclear:

```
> /generate-data-request ABCD-1660
```

This discovers the relevant Doctrine entities, generates PostgreSQL queries filtered by the ticket's identifiers, and writes them to `data-request.md`. After receiving results, place them in `logs/tickets/ABCD-1660/data/` and re-run `/analyze-logs`.

## Step 6: Close the ticket

After reviewing and sending the response:

```
> /close-ticket ABCD-1660
```

This archives the ticket from `tickets/` to `log-archive/`, checks Jira status, and logs the closure. The ticket is now eligible for `/update-log-database` and `/update-knowledge-center`.

## Throughout: Work history

Every skill above automatically logs its activity and regenerates the weekly work history. Check it anytime:

```
> /generate-work-history this week
```

```
=== Work History: Week 2026-W08 ===

3 tickets worked on, 12 activities across 4 days
Total estimated time: ~145 minutes

Written to: logs/tickets/work-history-2026-W08.md
```

Use this for Tempo time entries.
