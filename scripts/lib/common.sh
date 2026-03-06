#!/usr/bin/env bash
# common.sh — Shared helpers for M&S Log Analysis Toolkit scripts.
# Source this file from any script: source "$(dirname "$0")/../lib/common.sh"
#
# Provides:
#   workspace_root  — resolves the workspace directory (where config.yaml lives)
#   toolkit_root    — resolves the toolkit directory (workspace/toolkit/)
#   load_env        — sources .env and validates required vars
#   get_config      — simple YAML value lookup (top-level keys only)
#   log_activity    — appends a timestamped entry to a ticket's activity-log.yaml
#   require_tools   — checks that required CLI tools are available
#   ensure_ticket_dir — creates a ticket working directory if needed

set -euo pipefail

# Resolve the workspace root directory.
# This is where config.yaml, data/, tickets/, and log-archive/ live.
# Uses TOOLKIT_WORKSPACE env var if set, otherwise walks up from the calling
# script's location looking for config.yaml.
workspace_root() {
    if [[ -n "${_WORKSPACE_ROOT:-}" ]]; then echo "$_WORKSPACE_ROOT"; return; fi
    if [[ -n "${TOOLKIT_WORKSPACE:-}" ]]; then
        _WORKSPACE_ROOT="$TOOLKIT_WORKSPACE"
        echo "$_WORKSPACE_ROOT"
        return
    fi

    local dir
    dir="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"

    # Walk up until we find config.yaml (the workspace root marker)
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/config.yaml" ]]; then
            _WORKSPACE_ROOT="$dir"
            echo "$dir"
            return
        fi
        dir="$(dirname "$dir")"
    done

    echo "ERROR: Cannot find workspace root (config.yaml). Set TOOLKIT_WORKSPACE or run from within the workspace." >&2
    return 1
}

# Resolve the toolkit root directory.
# This is where scripts/, skills/, templates/, and ui/ live.
# Supports two layouts:
#   Submodule layout: workspace/toolkit/  (toolkit is a subdirectory)
#   Flat layout:      workspace/          (toolkit files are in workspace root)
toolkit_root() {
    if [[ -n "${_TOOLKIT_ROOT:-}" ]]; then echo "$_TOOLKIT_ROOT"; return; fi
    local ws
    ws="$(workspace_root)"
    if [[ -d "$ws/toolkit/scripts" ]]; then
        _TOOLKIT_ROOT="$ws/toolkit"
    else
        _TOOLKIT_ROOT="$ws"
    fi
    echo "$_TOOLKIT_ROOT"
}

# Load .env file from toolkit directory and validate required Jira variables.
load_env() {
    local tk
    tk="$(toolkit_root)"
    local env_file="$tk/.env"

    if [[ ! -f "$env_file" ]]; then
        echo "ERROR: .env file not found at $env_file" >&2
        echo "Copy .env.example to .env and fill in your Jira credentials." >&2
        return 1
    fi

    # Source .env (skip comments and blank lines)
    set -a
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        key="$(echo "$key" | xargs)"
        export "$key"="$value"
    done < "$env_file"
    set +a

    # Validate required variables
    local missing=()
    [[ -z "${JIRA_BASE_URL:-}" ]] && missing+=("JIRA_BASE_URL")
    [[ -z "${JIRA_EMAIL:-}" ]] && missing+=("JIRA_EMAIL")
    [[ -z "${JIRA_API_TOKEN:-}" ]] && missing+=("JIRA_API_TOKEN")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required variables in .env: ${missing[*]}" >&2
        return 1
    fi
}

# Simple YAML value lookup using grep/sed.
# Only works for top-level or simple nested scalar values (key: "value" or key: value).
# For complex nested structures, read the YAML directly from prompts.
#
# Usage: get_config "jira.project_key" → "PROJ"
get_config() {
    local key_path="$1"
    local ws
    ws="$(workspace_root)"
    local config_file="$ws/config.yaml"

    if [[ ! -f "$config_file" ]]; then
        echo "ERROR: config.yaml not found at $config_file" >&2
        return 1
    fi

    # Split key path on dots
    IFS='.' read -ra parts <<< "$key_path"

    if [[ ${#parts[@]} -eq 1 ]]; then
        # Top-level key
        sed -n "s/^${parts[0]}:[[:space:]]*[\"']*\([^\"']*\)[\"']*/\1/p" "$config_file" | head -1
    elif [[ ${#parts[@]} -eq 2 ]]; then
        # Two-level key: find the parent section, then the child key
        local in_section=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^${parts[0]}: ]]; then
                in_section=true
                continue
            fi
            if $in_section; then
                # Exit section if we hit a non-indented line (new top-level key)
                if [[ "$line" =~ ^[a-z_] && ! "$line" =~ ^[[:space:]] ]]; then
                    break
                fi
                # Match the child key
                if [[ "$line" =~ ^[[:space:]]+${parts[1]}:[[:space:]]*(.*) ]]; then
                    echo "${BASH_REMATCH[1]}" | sed 's/^[\"'\'']*//;s/[\"'\'']*$//'
                    return
                fi
            fi
        done < "$config_file"
    fi
}

# Append a timestamped activity entry to a ticket's activity-log.yaml.
#
# Usage: log_activity "PROJ-123" "ticket_fetched" "Fetched ticket details from Jira" [duration_seconds] [source]
log_activity() {
    local ticket_id="$1"
    local action="$2"
    local description="$3"
    local duration="${4:-}"
    local source="${5:-$(basename "$0")}"

    local ws
    ws="$(workspace_root)"
    local ticket_dir="$ws/tickets/$ticket_id"
    local activity_file="$ticket_dir/activity-log.yaml"

    ensure_ticket_dir "$ticket_id"

    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%S')"

    # Initialize file if it doesn't exist
    if [[ ! -f "$activity_file" ]]; then
        cat > "$activity_file" <<EOF
ticket_id: "$ticket_id"
activities:
EOF
    fi

    # Append entry
    {
        echo "  - timestamp: \"$timestamp\""
        echo "    action: \"$action\""
        echo "    description: \"$description\""
        if [[ -n "$duration" ]]; then
            echo "    duration_seconds: $duration"
        else
            echo "    duration_seconds: null"
        fi
        echo "    source: \"$source\""
        echo ""
    } >> "$activity_file"
}

# Check that required CLI tools are available.
#
# Usage: require_tools curl jq
require_tools() {
    local missing=()
    for tool in "$@"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required tools: ${missing[*]}" >&2
        echo "Install them and try again." >&2
        return 1
    fi
}

# Create a ticket working directory if it doesn't exist.
#
# Usage: ensure_ticket_dir "PROJ-123"
ensure_ticket_dir() {
    local ticket_id="$1"
    local ws
    ws="$(workspace_root)"
    local ticket_dir="$ws/tickets/$ticket_id"

    if [[ ! -d "$ticket_dir" ]]; then
        mkdir -p "$ticket_dir/logs" "$ticket_dir/data"
    fi
}
