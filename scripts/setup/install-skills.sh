#!/usr/bin/env bash
# install-skills.sh — Process skill templates and install to .claude/skills/.
#
# Reads skill templates from toolkit/skills/, replaces {{VARIABLE}} placeholders
# with values from config.yaml, and writes concrete SKILL.md files to
# .claude/skills/<name>/. Only overwrites if content has changed.
#
# Usage:
#   ./scripts/setup/install-skills.sh
#   TOOLKIT_WORKSPACE=/path/to/workspace ./scripts/setup/install-skills.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
WS_ROOT="$(workspace_root)"
TK_ROOT="$(toolkit_root)"

# Find the git repo root
REPO_ROOT="$(cd "$WS_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"
if [[ -z "$REPO_ROOT" ]]; then
    echo "ERROR: Not inside a git repository." >&2
    exit 1
fi

SKILLS_SRC="$TK_ROOT/skills"
SKILLS_DST="$REPO_ROOT/.claude/skills"

if [[ ! -d "$SKILLS_SRC" ]]; then
    echo "ERROR: Skills directory not found at $SKILLS_SRC" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Compute template variables
# ---------------------------------------------------------------------------

# {{WORKSPACE}} — workspace path relative to repo root
if [[ "$WS_ROOT" == "$REPO_ROOT" ]]; then
    VAR_WORKSPACE="."
else
    VAR_WORKSPACE="${WS_ROOT#$REPO_ROOT/}"
fi

# {{TOOLKIT}} — toolkit path relative to repo root
if [[ "$TK_ROOT" == "$REPO_ROOT" ]]; then
    VAR_TOOLKIT="."
else
    VAR_TOOLKIT="${TK_ROOT#$REPO_ROOT/}"
fi

# Read values from config.yaml
VAR_PROJECT_KEY=$(get_config "jira.project_key" 2>/dev/null || echo "")
VAR_APP_LABEL=$(get_config "loki.app_label" 2>/dev/null || echo "")
VAR_NAMESPACE=$(get_config "loki.namespace" 2>/dev/null || echo "")
VAR_SERVICE_NAME=$(get_config "service.name" 2>/dev/null || echo "")
VAR_DISPLAY_NAME=$(get_config "service.display_name" 2>/dev/null || echo "")
VAR_SHORT_LABEL=$(get_config "loki.short_label" 2>/dev/null || echo "")

echo "=== Install Toolkit Skills ==="
echo ""
echo "Workspace:    $VAR_WORKSPACE"
echo "Toolkit:      $VAR_TOOLKIT"
echo "Service:      $VAR_SERVICE_NAME"
echo "App label:    $VAR_APP_LABEL"
echo "Namespace:    $VAR_NAMESPACE"
echo ""

# Warn about empty critical variables
WARN=0
for var_name in SERVICE_NAME APP_LABEL NAMESPACE; do
    eval "val=\$VAR_$var_name"
    if [[ -z "$val" ]]; then
        echo "WARNING: {{$var_name}} is empty — fill in config.yaml and re-run." >&2
        WARN=$((WARN + 1))
    fi
done
[[ $WARN -gt 0 ]] && echo ""

# ---------------------------------------------------------------------------
# Process each skill template
# ---------------------------------------------------------------------------
INSTALLED=0
SKIPPED=0
ERRORS=0

for skill_file in "$SKILLS_SRC"/*/SKILL.md; do
    [[ -f "$skill_file" ]] || continue

    skill_name="$(basename "$(dirname "$skill_file")")"
    dst_dir="$SKILLS_DST/$skill_name"
    dst_file="$dst_dir/SKILL.md"

    # Apply template variable substitution to a temp file
    TMPFILE=$(mktemp)
    sed \
        -e "s|{{WORKSPACE}}|$VAR_WORKSPACE|g" \
        -e "s|{{TOOLKIT}}|$VAR_TOOLKIT|g" \
        -e "s|{{PROJECT_KEY}}|$VAR_PROJECT_KEY|g" \
        -e "s|{{APP_LABEL}}|$VAR_APP_LABEL|g" \
        -e "s|{{NAMESPACE}}|$VAR_NAMESPACE|g" \
        -e "s|{{SERVICE_NAME}}|$VAR_SERVICE_NAME|g" \
        -e "s|{{DISPLAY_NAME}}|$VAR_DISPLAY_NAME|g" \
        -e "s|{{SHORT_LABEL}}|$VAR_SHORT_LABEL|g" \
        "$skill_file" > "$TMPFILE"

    # Check for unresolved variables
    unresolved=$(grep -oE '\{\{[A-Z_]+\}\}' "$TMPFILE" | sort -u || true)
    if [[ -n "$unresolved" ]]; then
        echo "  [WARN] $skill_name — unresolved variables: $unresolved"
    fi

    # Change detection: skip if content is identical
    if [[ -f "$dst_file" ]] && [[ ! -L "$dst_file" ]]; then
        if diff -q "$dst_file" "$TMPFILE" > /dev/null 2>&1; then
            SKIPPED=$((SKIPPED + 1))
            rm "$TMPFILE"
            continue
        fi
    fi

    # Remove existing symlinks (from old install-skills.sh)
    if [[ -L "$dst_file" ]]; then
        rm "$dst_file"
    fi

    # Create target directory
    if ! mkdir -p "$dst_dir" 2>/dev/null; then
        echo "  [FAIL] $skill_name — cannot create $dst_dir"
        ERRORS=$((ERRORS + 1))
        rm "$TMPFILE"
        continue
    fi

    # Write processed file
    if mv "$TMPFILE" "$dst_file"; then
        echo "  [ OK ] $skill_name"
        INSTALLED=$((INSTALLED + 1))
    else
        echo "  [FAIL] $skill_name — write failed"
        ERRORS=$((ERRORS + 1))
        rm -f "$TMPFILE"
    fi
done

echo ""
echo "=== Done: $INSTALLED installed, $SKIPPED unchanged, $ERRORS errors ==="

if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi
