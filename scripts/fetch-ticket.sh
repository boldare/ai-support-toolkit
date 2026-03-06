#!/usr/bin/env bash
# fetch-ticket.sh — Fetch a Jira ticket and generate ticket-details.yaml.
#
# Usage:
#   ./scripts/fetch-ticket.sh PROJ-123
#   ./scripts/fetch-ticket.sh PROJ-123 --context "User reports request fails for ID 12345"
#
# Output: logs/tickets/{ticket_id}/ticket-details.yaml
#
# Requires: curl, jq
# Auth: JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN from .env

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_tools curl jq

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 <ticket_id> [--context \"extra context\"]"
    echo ""
    echo "Arguments:"
    echo "  ticket_id    Jira ticket ID (e.g., PROJ-123)"
    echo "  --context    Optional additional context about the issue"
    echo ""
    echo "Example:"
    echo "  $0 PROJ-123 --context \"User reports request fails for ID 12345\""
    exit 1
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    usage
fi

TICKET_ID="$1"
shift
ADDITIONAL_CONTEXT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --context)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --context requires a value" >&2
                exit 1
            fi
            ADDITIONAL_CONTEXT="$2"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage
            ;;
    esac
done

# Validate ticket ID format
if [[ ! "$TICKET_ID" =~ ^[A-Z]+-[0-9]+$ ]]; then
    echo "ERROR: Invalid ticket ID format: $TICKET_ID (expected e.g., PROJ-123)" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Load environment and build auth
# ---------------------------------------------------------------------------
load_env

AUTH=$(printf '%s:%s' "$JIRA_EMAIL" "$JIRA_API_TOKEN" | base64)
API_BASE="$JIRA_BASE_URL/rest/api/3"
CURL_OPTS=(-s -w "\n%{http_code}" -H "Authorization: Basic $AUTH" -H "Content-Type: application/json")

# ---------------------------------------------------------------------------
# Helper: strip HTML tags to plain text
# ---------------------------------------------------------------------------
strip_html() {
    sed -e 's/<br[[:space:]]*\/?>/\n/gi' \
        -e 's/<\/p>/\n/gi' \
        -e 's/<\/li>/\n/gi' \
        -e 's/<\/tr>/\n/gi' \
        -e 's/<\/div>/\n/gi' \
        -e 's/<[^>]*>//g' \
        -e 's/&amp;/\&/g' \
        -e 's/&lt;/</g' \
        -e 's/&gt;/>/g' \
        -e 's/&quot;/"/g' \
        -e "s/&#39;/'/g" \
        -e 's/&nbsp;/ /g' \
        -e '/^[[:space:]]*$/d'
}

# ---------------------------------------------------------------------------
# Helper: extract text from ADF JSON (fallback)
# ---------------------------------------------------------------------------
extract_adf_text() {
    jq -r '[.. | .text? // empty] | join(" ")' 2>/dev/null || echo "(could not parse description)"
}

# ---------------------------------------------------------------------------
# Helper: escape YAML string (double-quoted)
# ---------------------------------------------------------------------------
yaml_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    printf '%s' "$str"
}

# ---------------------------------------------------------------------------
# Fetch ticket details
# ---------------------------------------------------------------------------
echo "Fetching ticket $TICKET_ID..."

FIELDS="summary,description,status,priority,created,resolutiondate,labels,attachment"
RESPONSE=$(curl "${CURL_OPTS[@]}" \
    "$API_BASE/issue/$TICKET_ID?expand=renderedFields&fields=$FIELDS" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200) ;;
    404)
        echo "ERROR: Ticket $TICKET_ID not found." >&2
        exit 1
        ;;
    401)
        echo "ERROR: Authentication failed. Run verify-jira-access.sh to check your credentials." >&2
        exit 1
        ;;
    000)
        echo "ERROR: Cannot reach Jira server at $JIRA_BASE_URL. Check your network connection." >&2
        exit 1
        ;;
    *)
        echo "ERROR: Unexpected response (HTTP $HTTP_CODE)" >&2
        echo "$BODY" | head -5 >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Extract fields from response
# ---------------------------------------------------------------------------
SUMMARY=$(echo "$BODY" | jq -r '.fields.summary // "No summary"')
STATUS=$(echo "$BODY" | jq -r '.fields.status.name // "Unknown"')
PRIORITY=$(echo "$BODY" | jq -r '.fields.priority.name // "Unknown"')
CREATED=$(echo "$BODY" | jq -r '.fields.created // "Unknown"')
RESOLVED=$(echo "$BODY" | jq -r '.fields.resolutiondate // "null"')
LABELS=$(echo "$BODY" | jq -r '(.fields.labels // []) | map("\"" + . + "\"") | join(", ")')
ATTACHMENTS=$(echo "$BODY" | jq -r '(.fields.attachment // []) | map("\"" + .filename + "\"") | join(", ")')

# Extract description: prefer renderedFields (HTML), fallback to ADF text extraction
RENDERED_DESC=$(echo "$BODY" | jq -r '.renderedFields.description // empty')
if [[ -n "$RENDERED_DESC" ]]; then
    DESCRIPTION=$(echo "$RENDERED_DESC" | strip_html)
else
    DESCRIPTION=$(echo "$BODY" | jq -r '.fields.description // ""' | extract_adf_text)
fi

# Trim leading and trailing empty lines from description
DESCRIPTION=$(echo "$DESCRIPTION" | awk 'NF{found=1} found' | awk '{lines[NR]=$0} END{for(i=NR;i>=1;i--) if(lines[i]~/[^ \t]/) {last=i; break} for(i=1;i<=last;i++) print lines[i]}')

# ---------------------------------------------------------------------------
# Fetch comments
# ---------------------------------------------------------------------------
echo "Fetching comments..."

COMMENTS_RESPONSE=$(curl "${CURL_OPTS[@]}" \
    "$API_BASE/issue/$TICKET_ID/comment?maxResults=100&expand=renderedBody" 2>&1)

COMMENTS_HTTP=$(echo "$COMMENTS_RESPONSE" | tail -1)
COMMENTS_BODY=$(echo "$COMMENTS_RESPONSE" | sed '$d')

COMMENTS_YAML=""
if [[ "$COMMENTS_HTTP" == "200" ]]; then
    COMMENT_COUNT=$(echo "$COMMENTS_BODY" | jq -r '.comments | length')
    for i in $(seq 0 $((COMMENT_COUNT - 1))); do
        CAUTHOR=$(echo "$COMMENTS_BODY" | jq -r ".comments[$i].author.displayName // \"Unknown\"")
        CDATE=$(echo "$COMMENTS_BODY" | jq -r ".comments[$i].created // \"Unknown\"")

        # Prefer rendered body (HTML), fallback to ADF
        CRENDERED=$(echo "$COMMENTS_BODY" | jq -r ".comments[$i].renderedBody // empty")
        if [[ -n "$CRENDERED" ]]; then
            CBODY=$(echo "$CRENDERED" | strip_html)
        else
            CBODY=$(echo "$COMMENTS_BODY" | jq -r ".comments[$i].body // \"\"" | extract_adf_text)
        fi

        # Indent comment body for YAML block scalar
        CBODY_INDENTED=$(echo "$CBODY" | sed 's/^/      /')

        COMMENTS_YAML+="  - author: \"$(yaml_escape "$CAUTHOR")\"
    date: \"$CDATE\"
    body: |
$CBODY_INDENTED
"
    done
else
    COMMENTS_YAML="  # Could not fetch comments (HTTP $COMMENTS_HTTP)
"
fi

# ---------------------------------------------------------------------------
# Extract identifiers (best-effort)
# ---------------------------------------------------------------------------
ALL_TEXT="$SUMMARY $DESCRIPTION $COMMENTS_YAML"

# Note: grep returns exit 1 when no match — use || true to avoid set -e abort

# ---------------------------------------------------------------------------
# Config-driven identifier extraction
# Reads identifier patterns from config.yaml `identifiers` section
# ---------------------------------------------------------------------------
WS_ROOT="$(workspace_root)"
CONFIG_FILE="$WS_ROOT/config.yaml"
IDENTIFIERS_YAML=""

if [[ -f "$CONFIG_FILE" ]]; then
    # Parse identifier entries from config.yaml
    # Each entry has: name, pattern, description
    in_identifiers=false
    current_name=""
    current_pattern=""

    while IFS= read -r line; do
        # Detect start of identifiers section
        if [[ "$line" =~ ^identifiers: ]]; then
            in_identifiers=true
            continue
        fi
        # Exit section on next top-level key
        if $in_identifiers && [[ "$line" =~ ^[a-z_] && ! "$line" =~ ^[[:space:]] ]]; then
            break
        fi
        if $in_identifiers; then
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue

            if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+name:[[:space:]]*\"?([^\"]+)\"? ]]; then
                # If we have a pending identifier from previous iteration, extract it
                if [[ -n "$current_name" && -n "$current_pattern" ]]; then
                    MATCHES=$(echo "$ALL_TEXT" | grep -oE "$current_pattern" | sort -u | head -10 || true)
                    MATCHES_YAML=$(echo "$MATCHES" | sed '/^$/d' | sed 's/^/      - "/' | sed 's/$/"/' || true)
                    if [[ -n "$MATCHES_YAML" ]]; then
                        IDENTIFIERS_YAML+="    $current_name:
$MATCHES_YAML
"
                    else
                        IDENTIFIERS_YAML+="    $current_name: []  # none detected
"
                    fi
                fi
                current_name="${BASH_REMATCH[1]}"
                current_pattern=""
            elif [[ "$line" =~ pattern:[[:space:]]*\"?([^\"#]+)\"? ]]; then
                current_pattern=$(echo "${BASH_REMATCH[1]}" | xargs)
            fi
        fi
    done < "$CONFIG_FILE"

    # Process last identifier entry
    if [[ -n "$current_name" && -n "$current_pattern" ]]; then
        MATCHES=$(echo "$ALL_TEXT" | grep -oE "$current_pattern" | sort -u | head -10 || true)
        MATCHES_YAML=$(echo "$MATCHES" | sed '/^$/d' | sed 's/^/      - "/' | sed 's/$/"/' || true)
        if [[ -n "$MATCHES_YAML" ]]; then
            IDENTIFIERS_YAML+="    $current_name:
$MATCHES_YAML
"
        else
            IDENTIFIERS_YAML+="    $current_name: []  # none detected
"
        fi
    fi
fi

# If no identifiers configured, output empty map
if [[ -z "$IDENTIFIERS_YAML" ]]; then
    IDENTIFIERS_YAML="    # No identifier patterns configured in config.yaml
"
fi

# ---------------------------------------------------------------------------
# Generic extractors (universal — not config-driven)
# ---------------------------------------------------------------------------

# Dates (YYYY-MM-DD)
DATES=$(echo "$ALL_TEXT" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort -u | head -10 || true)
DATES_YAML=$(echo "$DATES" | sed '/^$/d' | sed 's/^/  - "/' | sed 's/$/"/' || true)

# Endpoints (URL paths)
ENDPOINTS=$(echo "$ALL_TEXT" | grep -oE '/[a-z_]+(/[a-z_]+)*' | sort -u | head -10 || true)
ENDPOINTS_YAML=$(echo "$ENDPOINTS" | sed '/^$/d' | sed 's/^/  - "/' | sed 's/$/"/' || true)

# Error messages (quoted strings after "error" or "exception")
ERROR_MSGS=$(echo "$ALL_TEXT" | grep -oiE '(error|exception|failed)[^"]*"[^"]*"' | head -5 || true)
ERROR_MSGS_YAML=$(echo "$ERROR_MSGS" | sed '/^$/d' | sed 's/^/  - "/' | sed 's/$/"/' || true)

# Guess service area from module names in config.yaml
SERVICE_AREA="Unknown"

if [[ -f "$CONFIG_FILE" ]]; then
    while IFS= read -r module_name; do
        # Convert CamelCase to lowercase words for matching
        # e.g., "EmployeeTransfer" -> "employee|transfer|employeetransfer"
        module_lower=$(echo "$module_name" | sed 's/\([A-Z]\)/ \1/g' | tr '[:upper:]' '[:lower:]' | xargs)
        module_words=$(echo "$module_lower" | tr ' ' '|')
        module_joined=$(echo "$module_lower" | tr -d ' ')
        pattern="${module_words}|${module_joined}"

        if echo "$ALL_TEXT" | grep -qiE "$pattern"; then
            SERVICE_AREA="$module_name"
            break
        fi
    done < <(grep '^\s*- name:' "$CONFIG_FILE" | sed 's/.*name: *"\(.*\)"/\1/')
fi

# ---------------------------------------------------------------------------
# Write ticket-details.yaml
# ---------------------------------------------------------------------------
ensure_ticket_dir "$TICKET_ID"

WS="$(workspace_root)"
OUTPUT_FILE="$WS/tickets/$TICKET_ID/ticket-details.yaml"

# Indent description for YAML block scalar
DESC_INDENTED=$(echo "$DESCRIPTION" | sed 's/^/  /')

CONTEXT_LINE="null"
if [[ -n "$ADDITIONAL_CONTEXT" ]]; then
    CONTEXT_LINE="\"$(yaml_escape "$ADDITIONAL_CONTEXT")\""
fi

cat > "$OUTPUT_FILE" <<YAML
# Ticket Details — $TICKET_ID
# Generated: $(date -u '+%Y-%m-%dT%H:%M:%S')
# Source: Jira API (fetch-ticket.sh)

ticket_id: "$TICKET_ID"
summary: "$(yaml_escape "$SUMMARY")"
status: "$STATUS"
priority: "$PRIORITY"
created: "$CREATED"
resolved: $RESOLVED

description: |
$DESC_INDENTED

comments:
$COMMENTS_YAML
labels: [$LABELS]
attachments: [$ATTACHMENTS]

additional_context: $CONTEXT_LINE

# Auto-extracted identifiers (best-effort extraction from description + comments)
extracted:
  identifiers:
${IDENTIFIERS_YAML}  dates_mentioned:
${DATES_YAML:-    # none detected}
  endpoints_mentioned:
${ENDPOINTS_YAML:-    # none detected}
  error_messages:
${ERROR_MSGS_YAML:-    # none detected}
  service_area_guess: "$SERVICE_AREA"
YAML

echo "Ticket details written to: $OUTPUT_FILE"

# ---------------------------------------------------------------------------
# Log activity
# ---------------------------------------------------------------------------
log_activity "$TICKET_ID" "ticket_fetched" "Fetched ticket details from Jira (status: $STATUS, priority: $PRIORITY)" "" "fetch-ticket.sh"

echo "Done. Activity logged."
