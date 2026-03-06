# Production Data Request for {ticket_id}

## Context
{why_production_data_is_needed}
<!-- Brief explanation linking log analysis findings to the data questions -->

## Queries

### Query 1: {query_title}
```sql
{sql_query}
```
**What to look for**: {explanation_of_expected_vs_problematic_results}

### Query 2: {query_title}
```sql
{sql_query}
```
**What to look for**: {explanation_of_expected_vs_problematic_results}

<!-- Add more queries as needed -->

## Notes for Support Team
- Please return results as CSV or paste into a Jira comment
- Database: PostgreSQL
- If a table name doesn't match exactly, check the Doctrine entity mappings in the codebase
