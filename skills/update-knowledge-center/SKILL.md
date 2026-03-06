---
name: update-knowledge-center
description: >
  Consolidates Knowledge Center patterns: merges duplicate drafts, updates
  frequency counts, promotes recurring drafts to confirmed, and cross-references
  with the log database. Run periodically after analyzing multiple tickets.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, AskUserQuestion
---

# Update Knowledge Center

**No arguments required.** Processes all draft patterns and archived tickets.

## Current State

!`echo "=== KC Status ===" && ([ -f {{WORKSPACE}}/data/knowledge-center/issues.yaml ] && echo "Patterns: $(grep 'total_patterns:' {{WORKSPACE}}/data/knowledge-center/issues.yaml | head -1)" && echo "Draft: $(grep -c 'status: \"draft\"' {{WORKSPACE}}/data/knowledge-center/issues.yaml 2>/dev/null || echo 0)" && echo "Confirmed: $(grep -c 'status: \"confirmed\"' {{WORKSPACE}}/data/knowledge-center/issues.yaml 2>/dev/null || echo 0)" || echo "NOT INITIALIZED") && echo "" && echo "=== Analyzed tickets ===" && echo "Active: $(ls {{WORKSPACE}}/tickets/*/analysis.md 2>/dev/null | wc -l | tr -d ' ')" && echo "Archived: $(ls {{WORKSPACE}}/log-archive/*/analysis.md 2>/dev/null | wc -l | tr -d ' ')"`

## Prerequisites

`{{WORKSPACE}}/data/knowledge-center/issues.yaml` must exist. If not: **"KC not initialized. Run `/init-knowledge-center` or analyze a ticket with `/analyze-logs` first (it auto-scaffolds the KC)."** and stop.

## Instructions

### Step 1: Load Current KC

Read `{{WORKSPACE}}/data/knowledge-center/issues.yaml`. Parse all patterns, noting:
- Total patterns, draft count, confirmed count
- Pattern IDs, titles, categories, example_tickets lists

### Step 2: Scan Analyzed Tickets

Find all tickets with completed analyses:
```bash
ls {{WORKSPACE}}/log-archive/*/analysis.md {{WORKSPACE}}/tickets/*/analysis.md 2>/dev/null
```

For each analysis.md, extract:
- Root cause category
- Pattern ID referenced (if any)
- Key log signatures observed
- Service area

### Step 3: Identify Duplicates

Compare draft patterns against each other and against confirmed patterns:
- **Same root cause + same service area + same log signatures** -> merge into one pattern
- **Same root cause + different service area** -> keep separate (different manifestation)
- **Similar but distinct** -> keep separate, note relationship

For each merge candidate, present to user:
```
Merge candidates:
  1. {draft_id_1} — "{title}" ({N} tickets)
     + {draft_id_2} — "{title}" ({N} tickets)
     -> Proposed merged title: "{merged_title}"

  2. {draft_id_3} — similar to confirmed {confirmed_id}
     -> Propose adding tickets to existing pattern
```

Ask: **"Approve these merges? (yes/adjust/skip)"**

If no duplicates found, report **"No duplicates detected."** and continue.

### Step 4: Update Frequency

For each pattern (draft and confirmed), count total tickets:
- Count entries in `example_tickets`
- Update `frequency`: rare (1), occasional (2-4), common (5-9), very_common (10+)

### Step 5: Promote Drafts

Patterns eligible for promotion to `confirmed`:
- Have 2+ tickets (recurrence confirmed)
- Have log_signatures with at least 1 required entry
- Have a non-empty resolution

Present promotion candidates:
```
Ready for promotion (2+ tickets, complete data):
  - {draft_id}: "{title}" — {N} tickets, {category}
```

Ask: **"Promote these to confirmed? (yes/select/skip)"**

If no patterns eligible, report **"No drafts ready for promotion (need 2+ tickets with complete data)."** and continue.

### Step 6: Cross-Reference Log Database

Read `{{WORKSPACE}}/data/log-database/log-types.yaml`.

For each KC pattern:
- Verify that `log_signatures.required` tags exist in the log database
- Verify channels match
- Flag any signatures referencing unknown tags: **"Pattern {id} references unknown log type {tag}"**
- Suggest additional signatures based on log types in the same module

### Step 7: Update Statistics

Recalculate:
- `total_patterns` count
- `total_tickets_classified` (sum of all unique tickets across all patterns)
- `statistics.by_service_area`
- `statistics.by_resolution_type`
- `statistics.by_external_service`
- Category `ticket_count` values

### Step 8: Write Updated KC

Write the updated `issues.yaml`. Validate:
```bash
python3 -c "import yaml; yaml.safe_load(open('{{WORKSPACE}}/data/knowledge-center/issues.yaml'))"
```

### Step 9: Regenerate KNOWLEDGE_CENTER.md

Rewrite `{{WORKSPACE}}/data/knowledge-center/KNOWLEDGE_CENTER.md` from the updated YAML.

### Step 10: Report

```
=== Knowledge Center Updated ===

Patterns:     {total} ({confirmed} confirmed, {draft} draft)
Merged:       {N} duplicate patterns consolidated
Promoted:     {N} drafts -> confirmed
New tickets:  {N} analyses incorporated
Frequency changes: {list of patterns whose frequency changed}

Files updated:
  - {{WORKSPACE}}/data/knowledge-center/issues.yaml
  - {{WORKSPACE}}/data/knowledge-center/KNOWLEDGE_CENTER.md
```

## Important Rules

- **Never delete patterns** — merge or flag, don't remove.
- **User confirms merges and promotions** — don't auto-merge without review.
- **Preserve confirmed pattern data** — only extend, never reduce confirmed patterns.
- **Validate YAML after every write.**
