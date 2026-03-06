#!/usr/bin/env bash
# log-activity.sh — Manually record an activity entry for a ticket.
#
# Usage:
#   ./scripts/log-activity.sh PROJ-123 "communication_with_support" "Sent log request to support team"
#   ./scripts/log-activity.sh PROJ-123 "logs_received" "Log files placed in ticket directory" 0
#
# Arguments:
#   $1 — Ticket ID (e.g., PROJ-123)
#   $2 — Action type (e.g., communication_with_support, logs_received, response_sent)
#   $3 — Description of the activity
#   $4 — (Optional) Duration in seconds
#
# Common action types:
#   communication_with_support  — Sent message to / received from support team
#   communication_with_integration — Sent to / received from integration team
#   logs_received               — Log files placed in ticket directory
#   data_received               — Production data results placed in ticket directory
#   response_sent               — Final response sent
#   manual_analysis             — Manual investigation outside the toolkit

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <ticket_id> <action> <description> [duration_seconds]"
    echo ""
    echo "Example:"
    echo "  $0 PROJ-123 \"communication_with_support\" \"Sent log request to support team\""
    exit 1
fi

TICKET_ID="$1"
ACTION="$2"
DESCRIPTION="$3"
DURATION="${4:-}"

log_activity "$TICKET_ID" "$ACTION" "$DESCRIPTION" "$DURATION" "manual"

echo "Activity logged for $TICKET_ID: [$ACTION] $DESCRIPTION"
