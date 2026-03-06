#!/usr/bin/env bash
# close-ticket.sh — Move a ticket from tickets/ to log-archive/.
#
# Usage: ./scripts/close-ticket.sh <ticket_id>
#
# Moves {workspace}/tickets/{ticket_id}/ -> {workspace}/log-archive/{ticket_id}/
# The skill (close-ticket/SKILL.md) handles UX (confirmation, warnings, logging).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_tools mv

TICKET_ID="${1:?Usage: $0 <ticket_id>}"
WS="$(workspace_root)"

SRC="$WS/tickets/$TICKET_ID"
DST="$WS/log-archive/$TICKET_ID"

if [[ ! -d "$SRC" ]]; then
    echo "ERROR: Ticket directory not found: $SRC" >&2
    exit 1
fi

if [[ -d "$DST" ]]; then
    echo "ERROR: Archive directory already exists: $DST" >&2
    echo "Remove it first or use a different ticket ID." >&2
    exit 2
fi

mkdir -p "$(dirname "$DST")"
mv "$SRC" "$DST"

echo "Archived: $SRC -> $DST"
