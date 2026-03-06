#!/usr/bin/env bash
# check-ticket-status.sh — Fetch current Jira status for a ticket.
#
# Usage: ./scripts/check-ticket-status.sh <ticket_id>
# Output: Prints the status name (e.g., "Done", "In Progress")
# Exit 0: success, Exit 1: error

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_tools curl jq
load_env

TICKET_ID="${1:?Usage: $0 <ticket_id>}"

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    "$JIRA_BASE_URL/rest/api/3/issue/$TICKET_ID?fields=status")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "ERROR: Jira API returned $HTTP_CODE" >&2
    exit 1
fi

STATUS=$(echo "$BODY" | jq -r '.fields.status.name // "Unknown"')
echo "$STATUS"
