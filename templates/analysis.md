# Analysis: {ticket_id}

## Summary
{one_to_two_sentence_summary_of_findings}

## Category
{outcome_category}
<!-- One of: Expected System Behavior, External Integration Issue, Business Rule Rejection, Actual Bug, Insufficient Information -->

## Confidence
{confidence_level} ({confidence_percentage}%) — {reasoning}
<!-- e.g., "High (85%) — Matches known pattern `service-data-mismatch`" -->

## Timeline
| Time (UTC+3) | Event |
|---|---|
| {timestamp} | {event_description} |

## Root Cause
{detailed_root_cause_explanation}

## Key Log Entries
- `{log_entry_summary}` ({channel}.{severity})

## Production Data Findings
{data_findings_if_available}
<!-- "N/A — no production data requested" or details from data-request results -->

## Recommended Response
**Respond to**: {recipient}
**Message**:
> {response_message_for_support_or_integration_team}

## Verification Notes
- {verification_note}
<!-- e.g., "Analysis confirmed by verification pass" -->
<!-- e.g., "Alternative explanation considered: ..." -->

## Knowledge Center Update
{kc_update_status}
<!-- "No new patterns detected (matches existing `pattern-id`)" -->
<!-- or "New pattern proposed: [description]. Added as draft to issues.yaml." -->
