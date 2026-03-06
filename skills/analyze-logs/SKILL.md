---
name: analyze-logs
description: >
  Analyzes log files against ticket context and the Knowledge Center to determine
  root cause. Pre-filters logs to manage token usage, matches against known patterns,
  builds a timeline, determines category and confidence, generates a response for
  the appropriate team, and runs a built-in verification pass. Use after logs are
  placed in the ticket's logs/ directory.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Analyze Logs

You are analyzing log files to determine root cause and generate a response for a support ticket.

**Argument**: Ticket ID (e.g., `/analyze-logs PROJ-123`)

If no ticket ID is provided, ask the user for one.

## Current State

!`echo "=== Active tickets with logs ===" && for d in {{WORKSPACE}}/tickets/*/logs; do [ -d "$d" ] && t=$(basename "$(dirname "$d")") && echo "  $t: $(ls "$d"/*.txt 2>/dev/null | wc -l | tr -d ' ') log files | $([ -f "{{WORKSPACE}}/tickets/$t/analysis.md" ] && echo "analyzed" || echo "not analyzed") | $([ -d "{{WORKSPACE}}/tickets/$t/data" ] && echo "has data" || echo "no data")"; done || echo "  No tickets with logs"`

## Prerequisites

Read `{{WORKSPACE}}/tickets/{ticket_id}/ticket-details.yaml`.

If it doesn't exist: **"Ticket not fetched yet. Run `/fetch-ticket {ticket_id}` first."** and stop.

Check for log files in `{{WORKSPACE}}/tickets/{ticket_id}/logs/`:

If no log files exist, check `{{WORKSPACE}}/log-archive/{ticket_id}/`:
- If archive has files: **"Log files found in archive. Copy them to the ticket directory?"**
  - If user confirms, copy and rename: `cp {{WORKSPACE}}/log-archive/{ticket_id}/* {{WORKSPACE}}/tickets/{ticket_id}/logs/ && bash {{TOOLKIT}}/scripts/rename-logs.sh {{WORKSPACE}}/tickets/{ticket_id}/logs/`
- If no files anywhere: **"No log files found. Run `/generate-log-request {ticket_id}` to prepare a request for the support team."** and stop.

---

## Phase 1: Context Gathering

### Step 1: Read Ticket Context

From `ticket-details.yaml`, extract:
- Summary and description (the reported problem)
- All extracted identifiers (from `extracted.identifiers`, dates, endpoints)
- Additional context (from `--context` flag)
- Service area guess

### Step 2: Load Context Files

**KC match** — Read the `kc_match` section from `ticket-details.yaml` (populated by `/fetch-ticket`):
- If `kc_match.pattern_id` is not null: use the persisted match (log_signatures, category, resolution). This avoids reading the full `issues.yaml`.
- If `kc_match.pattern_id` is null or `kc_match` section is missing: fall back to reading `{{WORKSPACE}}/data/knowledge-center/issues.yaml` for full pattern scanning.

**Log types** — Read only the `noise_patterns` section from `{{WORKSPACE}}/data/log-database/log-types.yaml` for Phase 2 pre-filtering. You do NOT need the full log type entries until Phase 3 Step 8 (and even then, only entries matching the ticket's service area module).

**Config** — Read `{{WORKSPACE}}/config.yaml` for response routing rules.

---

## Phase 2: Log Pre-Filtering (Critical for Token Management)

Log files are typically 5-15MB. **Do NOT read entire log files into context.** Use bash commands to extract only actionable lines.

### Step 3: Assess Volume

```bash
wc -l {{WORKSPACE}}/tickets/{ticket_id}/logs/*.txt
```

### Step 4: Extract Actionable Lines

Build a grep pattern from the ticket's identifiers and severity levels:

```bash
grep -n -E '(CRITICAL|ERROR|WARNING|{identifier_values}|{error_keyword})' \
  {{WORKSPACE}}/tickets/{ticket_id}/logs/*.txt | head -3000
```

Replace `{identifier_values}` with actual values from `extracted.identifiers` and `{error_keyword}` with values from the ticket.

### Step 5: Remove Noise

Apply noise patterns from `log-types.yaml` to further filter:

```bash
grep -v -E '(Matched route|/health|/readiness|/liveness|http_client\.INFO: Response: "20|OPTIONS HTTP|Container (starting|started)|User Deprecated|cache\.(INFO|DEBUG)|doctrine\.(INFO|DEBUG)|^\s*$)' \
  {output_from_step_4}
```

### Step 6: Handle Large Results

If still > 2000 lines after filtering:
- Narrow to CRITICAL/ERROR only (drop WARNING)
- Focus on the specific time window from the ticket
- Sample representative entries rather than reading all

---

## Phase 3: Analysis

### Step 7: Pattern Match Against Knowledge Center

**If `kc_match.pattern_id` exists in ticket-details.yaml** (common case):
1. Validate the match against actual logs — check if `kc_match.log_signatures.required` tags appear in the filtered lines
2. Check if `kc_match.log_signatures.supporting` tags also appear
3. Adjust confidence up (all signatures confirmed) or down (signatures missing despite match)
4. If the match is invalidated by the logs, fall back to full `issues.yaml` scan below

**If no KC match or match invalidated** (fall back):
1. Read `{{WORKSPACE}}/data/knowledge-center/issues.yaml`
2. For each pattern, check `log_signatures.required` against filtered logs
3. Check `log_signatures.supporting`
4. Compare error messages against the pattern's `root_cause`
5. Score: **high** (all required signatures present), **medium** (some required + context matches), **low** (weak match)

Record the best match and confidence score.

### Step 8: Deep Analysis

With the filtered log lines:

1. **Identify log types**: Map each significant entry to its log type from `log-types.yaml` (read only the module section matching the ticket's service area, not the full file)
2. **Extract timestamps**: Build a chronological timeline of events
3. **Trace request IDs**: If `request_id` is present, follow the full request lifecycle
4. **Identify the failure point**: Where in the chain did things go wrong?
   - Controller -> Handler -> Domain Service -> Port -> External API?
   - Which external service returned the error?
5. **Check for patterns**: Multiple establishments affected? Specific time window? Intermittent or consistent?

### Step 9: Incorporate Production Data

If files exist in `{{WORKSPACE}}/tickets/{ticket_id}/data/`:
- Read the data results
- Cross-reference with log findings
- Does the data confirm or contradict the log analysis?

### Step 10: Root Cause Determination

Based on all evidence, determine:

**Category** (one of):
- `Expected System Behavior` — system worked correctly, user expectation was wrong
- `External Integration Issue` — external service caused the failure
- `Business Rule Rejection` — request correctly rejected by business rules
- `Actual Bug` — genuine bug in {{SERVICE_NAME}}
- `Data Quality Issue` — misalignment between data sources
- `Insufficient Information` — cannot determine root cause from available data

**Confidence**: percentage + reasoning

**Timeline**: chronological event sequence with actual timestamps from logs

### Step 11: Generate Response

Based on category, check `config.yaml` `response.routing` for the action:

- **external_integration_issue**: Address the specific integration team. Include timestamps, identifiers, error messages, affected endpoints.
- **expected_behavior**: Explain to support team what happened and why it's correct.
- **business_rule_rejection**: Translate the technical rejection into user-friendly explanation.
- **actual_bug**: Draft a development ticket with reproduction steps.
- **insufficient_info**: List specific follow-up questions for the support team.

If a KC pattern matched, use `kc_match.resolution.response_template` from `ticket-details.yaml` as a starting point.

### Step 12: Code Path Trace (Complex Cases Only)

For `actual_bug` or unclear cases:
1. Find the relevant controller from the endpoint
2. Follow the command/query handler chain
3. Identify the exact code location of the failure

### Step 13: Knowledge Center Update

**a) If matches existing pattern** -> Note "matches `{pattern_id}`" in the analysis. No KC update needed.

**b) If variation of existing pattern** -> Note the variation. Append a comment to the matched pattern's `example_tickets` list in `issues.yaml`:
- Add `{ ticket: "{ticket_id}", date: "{today}", notes: "{variation_description}" }`

**c) If entirely new pattern** -> Auto-append a full draft pattern to `issues.yaml`:

1. Read current `{{WORKSPACE}}/data/knowledge-center/issues.yaml`
   - If it doesn't exist, create the scaffold (metadata + empty categories + empty issue_patterns) using the template at `{{TOOLKIT}}/templates/issues.yaml`

2. Build the new pattern entry from analysis findings:
   ```yaml
   - id: "{snake_case_id_from_root_cause}"
     title: "{one_line_description}"
     category: "{category_from_step_10}"
     frequency: "rare"              # Always starts as rare (1 ticket)
     service_area: "{module_from_ticket}"
     status: "draft"                # Draft until confirmed by /update-knowledge-center

     log_signatures:
       required:
         - log_type: "{tag_identified_in_step_8}"
           channel: "{channel}"
       supporting:
         - log_type: "{supporting_tag}"
           channel: "{channel}"

     root_cause: |
       {root_cause_from_step_10}

     verification_steps:
       - "{step_derived_from_analysis}"

     resolution:
       action: "{action_from_step_11}"
       response_template: |
         {response_from_step_11}
       respond_to: "{recipient_from_step_11}"

     example_tickets:
       - ticket: "{ticket_id}"
         date: "{today}"
         notes: "Initial discovery"

     code_references:
       - file: "{file_path_from_step_12_if_available}"
         context: "{description}"
   ```

3. Append to `issue_patterns` list in `issues.yaml`
4. Increment `total_patterns` in metadata
5. Update `last_updated` date
6. Update category `ticket_count` for the pattern's category
7. Validate YAML: `python3 -c "import yaml; yaml.safe_load(open('{{WORKSPACE}}/data/knowledge-center/issues.yaml'))"`

Note in `analysis.md`: "New KC pattern drafted: `{pattern_id}` (status: draft)"

---

## Phase 4: Built-in Verification

### Step 14: Independent Verification

Before writing the final analysis, run a self-verification pass:

**Completeness**: Are there CRITICAL/ERROR entries the analysis didn't account for? Re-run a targeted grep to check:
```bash
grep -c 'CRITICAL\|ERROR' {{WORKSPACE}}/tickets/{ticket_id}/logs/*.txt
```

**Contradictions**: Do any log entries suggest a different root cause? Are there successful requests that contradict a "service down" conclusion?

**Timeline integrity**: Does the timeline account for the full incident period? Are there unexplained gaps?

**Logical consistency**: Does the root cause explain ALL error entries, not just some?

**Response appropriateness**: Is the response addressed to the correct team per `config.yaml` routing?

**Alternative explanations**: What else could cause this pattern? Could a different KC pattern fit better?

If issues are found, adjust the analysis before writing. Note any uncertainties in the Verification Notes section.

---

## Phase 5: Output

### Step 15: Write Analysis

Write to `{{WORKSPACE}}/tickets/{ticket_id}/analysis.md` following the template at `{{TOOLKIT}}/templates/analysis.md`.

Include all sections:
- Summary, Category, Confidence, Timeline, Root Cause
- Key Log Entries (with `channel.severity` notation)
- Production Data Findings (or "N/A")
- Recommended Response (with recipient and message)
- Verification Notes (from Step 14)
- Knowledge Center Update status

### Step 16: Auto-Log and Update Work History

```bash
bash {{TOOLKIT}}/scripts/log-activity.sh {ticket_id} "log_analysis" "Analysis complete: {category} (confidence: {percentage}%, pattern: {pattern_id_or_none})"
```

Then regenerate work history for the current week by following `{{TOOLKIT}}/skills/generate-work-history/SKILL.md` Steps 1–6 (default time range: this week).

### Step 17: Report

Present the analysis summary to the user:
```
=== Analysis: {ticket_id} ===

Category: {category}
Confidence: {percentage}%
Pattern: {pattern_id_or_none}
Verification: {CONFIRMED or ISSUES_FOUND}

Root Cause: {one_sentence_summary}

Response for: {recipient}
```

Then display the recommended response message.

Suggest next steps:
- If `Insufficient Information`: **"Need more data. Run `/generate-log-request` or `/generate-data-request` for additional information."**
- If `Actual Bug`: **"A development ticket should be created with the reproduction steps in the analysis."**
- Otherwise: **"Analysis written to `{{WORKSPACE}}/tickets/{ticket_id}/analysis.md`. Review the response and share with the appropriate team."**

## Important Rules

- **Never read multi-MB log files directly** — always pre-filter with grep first.
- **Never guess timestamps** — use actual timestamps from log entries.
- **Never assume a specific external service** — verify which one from the log channel/URI.
- **Don't copy entire log blocks into the response** — summarize and quote key lines.
- **Always check the KC** — even if the issue seems obvious, match against known patterns.
- **Always run the work history regeneration** (Step 16) — even if analysis partially fails.
- **Always validate issues.yaml after writing** — a malformed YAML breaks all downstream skills.
- **Use unique pattern IDs** — check existing IDs before writing. Convention: `{service_area}_{short_description}` in snake_case.
