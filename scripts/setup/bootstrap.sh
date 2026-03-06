#!/usr/bin/env bash
# bootstrap.sh — One-time workspace initialization for the M&S Log Analysis Toolkit.
#
# Creates the workspace directory structure, copies template files, and sets up
# .gitignore. Run this once when adding the toolkit to a new service repository.
#
# Usage:
#   bash toolkit/scripts/setup/bootstrap.sh
#   bash support/toolkit/scripts/setup/bootstrap.sh
#
# The workspace root is the parent directory of the toolkit directory.
# After running, fill in config.yaml and then run /init-workspace.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WS_ROOT="$(dirname "$TK_ROOT")"

echo "=== M&S Log Analysis Toolkit — Bootstrap ==="
echo ""
echo "Toolkit:   $TK_ROOT"
echo "Workspace: $WS_ROOT"
echo ""

# ---------------------------------------------------------------------------
# Guard: don't re-bootstrap if workspace is already set up
# ---------------------------------------------------------------------------
if [[ -f "$WS_ROOT/config.yaml" ]]; then
    echo "Workspace already initialized (config.yaml exists)."
    echo "To re-initialize, remove config.yaml first."
    exit 0
fi

# ---------------------------------------------------------------------------
# Create directory structure
# ---------------------------------------------------------------------------
echo "Creating directory structure..."

mkdir -p "$WS_ROOT/data/log-database"
mkdir -p "$WS_ROOT/data/knowledge-center"
mkdir -p "$WS_ROOT/tickets"
mkdir -p "$WS_ROOT/log-archive"
mkdir -p "$WS_ROOT/reports"

echo "  data/"
echo "  data/log-database/"
echo "  data/knowledge-center/"
echo "  tickets/"
echo "  log-archive/"
echo "  reports/"

# ---------------------------------------------------------------------------
# Copy template files
# ---------------------------------------------------------------------------
echo ""
echo "Copying template files..."

if [[ -f "$TK_ROOT/templates/config.yaml" ]]; then
    cp "$TK_ROOT/templates/config.yaml" "$WS_ROOT/config.yaml"
    echo "  config.yaml (from template — fill in your service details)"
else
    echo "  WARNING: templates/config.yaml not found in toolkit"
fi

if [[ -f "$TK_ROOT/.env.example" ]]; then
    cp "$TK_ROOT/.env.example" "$WS_ROOT/.env.example"
    echo "  .env.example (copy to .env and add your Jira credentials)"
fi

# ---------------------------------------------------------------------------
# Create workspace .gitignore
# ---------------------------------------------------------------------------
if [[ ! -f "$WS_ROOT/.gitignore" ]]; then
    cat > "$WS_ROOT/.gitignore" <<'EOF'
# Credentials (never commit)
.env

# Active ticket workspaces (contain PII from support tickets)
tickets/

# Raw log archive (large files, may contain PII)
log-archive/

# Reports (regenerable)
reports/
EOF
    echo "  .gitignore"
fi

# ---------------------------------------------------------------------------
# Run install-skills.sh
# ---------------------------------------------------------------------------
echo ""
echo "Installing skills..."
TOOLKIT_WORKSPACE="$WS_ROOT" bash "$TK_ROOT/scripts/setup/install-skills.sh"

# ---------------------------------------------------------------------------
# Next steps
# ---------------------------------------------------------------------------
echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "Next steps:"
echo ""
echo "  1. Edit config.yaml — fill in the [MANUAL] fields:"
echo "     - service.name, service.display_name, service.description"
echo "     - jira.project_key"
echo "     - loki.app_label, loki.namespace, loki.cluster, loki.timezone, loki.short_label"
echo "     - service_classification.keywords"
echo "     - database.type"
echo ""
echo "  2. Copy .env.example to .env and add your Jira credentials"
echo ""
echo "  3. Run /verify-jira-access to test your Jira connection"
echo ""
echo "  4. Run /init-workspace to auto-detect modules, channels, and integrations"
echo ""
echo "  5. Run /init-log-database to build the log type database from codebase analysis"
echo ""
echo "  6. Run /init-knowledge-center to build the issue knowledge center from tickets"
echo ""
