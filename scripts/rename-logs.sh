#!/usr/bin/env bash
# rename-logs.sh — Rename Grafana log exports to a standardized format.
#
# Converts:  "Explore-logs-2025-10-08 12_13_23.txt" → "2025-10-08_api-prod.txt"
#
# Usage:
#   ./scripts/rename-logs.sh logs/tickets/PROJ-123/logs/
#   ./scripts/rename-logs.sh logs/archive/PROJ-456/
#
# Idempotent: files already in standard format are skipped.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <logs_directory>"
    echo ""
    echo "Example:"
    echo "  $0 logs/tickets/PROJ-123/logs/"
    exit 1
fi

TARGET_DIR="$1"

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "ERROR: Directory does not exist: $TARGET_DIR" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Derive short app label from config
# ---------------------------------------------------------------------------
SHORT_LABEL=$(get_config "loki.short_label" 2>/dev/null || echo "")
if [[ -z "$SHORT_LABEL" ]]; then
    # Fallback: use the full app_label
    SHORT_LABEL=$(get_config "loki.app_label" 2>/dev/null || echo "app")
fi

# ---------------------------------------------------------------------------
# Rename files
# ---------------------------------------------------------------------------
RENAMED=0
SKIPPED=0
WARNED=0

for file in "$TARGET_DIR"/*; do
    [[ -f "$file" ]] || continue

    filename=$(basename "$file")
    ext="${filename##*.}"
    base="${filename%.*}"

    # Already in standard format (YYYY-MM-DD_*) — skip
    if [[ "$filename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_ ]]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Match Grafana export pattern: "Explore-logs-YYYY-MM-DD HH_MM_SS"
    if [[ "$base" =~ ^Explore-logs-([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        DATE="${BASH_REMATCH[1]}"
        TARGET_NAME="${DATE}_${SHORT_LABEL}.${ext}"
        TARGET_PATH="$TARGET_DIR/$TARGET_NAME"

        # Handle duplicates: append _2, _3, etc.
        if [[ -f "$TARGET_PATH" ]]; then
            COUNTER=2
            while [[ -f "$TARGET_DIR/${DATE}_${SHORT_LABEL}_${COUNTER}.${ext}" ]]; do
                COUNTER=$((COUNTER + 1))
            done
            TARGET_NAME="${DATE}_${SHORT_LABEL}_${COUNTER}.${ext}"
            TARGET_PATH="$TARGET_DIR/$TARGET_NAME"
        fi

        mv "$file" "$TARGET_PATH"
        echo "  Renamed: $filename → $TARGET_NAME"
        RENAMED=$((RENAMED + 1))
    else
        echo "  WARNING: Unrecognized filename pattern: $filename" >&2
        WARNED=$((WARNED + 1))
    fi
done

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
echo ""
echo "Done: renamed $RENAMED, skipped $SKIPPED (already standard), warnings $WARNED"

# ---------------------------------------------------------------------------
# Log activity if ticket ID can be inferred from path
# ---------------------------------------------------------------------------
TICKET_ID=$(echo "$TARGET_DIR" | grep -oE '[A-Z]+-[0-9]+' | head -1)
if [[ -n "$TICKET_ID" ]]; then
    log_activity "$TICKET_ID" "logs_renamed" "Renamed $RENAMED log files to standard format (skipped $SKIPPED)" "" "rename-logs.sh"
fi
