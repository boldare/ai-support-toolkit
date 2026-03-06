# Log Request for {ticket_id}

## Summary
{brief_description_of_the_issue}

## Suspected Issue
{suspected_pattern_match_and_confidence}
<!-- e.g., "Likely matches pattern: `service-data-mismatch` (confidence: high)" -->
<!-- or "No known pattern match — dynamic query generated" -->

## LogQL Query

```logql
{logql_query}
```

**Time range**: {start_datetime} to {end_datetime} (UTC+3)
**Line limit**: {line_limit}
**Expected file size**: {estimated_size}

## Production Data Needed?
{yes_or_no_with_explanation}
<!-- If yes: "Run `prepare-data-request` prompt to generate SQL queries" -->

## Notes for Support Team
- Please export as plain text (.txt)
- Include both stderr and stdout streams if possible
- If the file is very large, splitting by hour is acceptable
