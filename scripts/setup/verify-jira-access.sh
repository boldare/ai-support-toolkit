#!/usr/bin/env bash
# verify-jira-access.sh — Verify Jira API access is configured correctly.
#
# Checks:
#   1. Prerequisites (curl, jq)
#   2. .env exists with required variables
#   3. Jira API connectivity (/rest/api/3/myself)
#   4. Configured project accessible (/rest/api/3/project/{PROJECT_KEY})
#   5. Search works (/rest/api/3/search)
#
# Usage: ./scripts/setup/verify-jira-access.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

PASS=0
FAIL=0

check_pass() {
    echo "  [PASS] $1"
    PASS=$((PASS + 1))
}

check_fail() {
    echo "  [FAIL] $1"
    [[ -n "${2:-}" ]] && echo "         $2"
    FAIL=$((FAIL + 1))
}

echo "=== Jira Access Verification ==="
echo ""

# 1. Check prerequisites
echo "1. Prerequisites"
if require_tools curl jq 2>/dev/null; then
    check_pass "curl and jq are available"
else
    check_fail "Missing required tools" "Install curl and jq, then re-run this script."
    echo ""
    echo "=== RESULT: $FAIL check(s) failed. Fix the issues above and re-run. ==="
    exit 1
fi
echo ""

# 2. Check .env
echo "2. Environment (.env)"
ROOT="$(toolkit_root)"

if [[ -f "$ROOT/.env" ]]; then
    check_pass ".env file exists"
else
    check_fail ".env file not found at $ROOT/.env" "Copy .env.example to .env and fill in your credentials."
    echo ""
    echo "=== RESULT: $FAIL check(s) failed. Fix the issues above and re-run. ==="
    exit 1
fi

if load_env 2>/dev/null; then
    check_pass "All required variables present (JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN)"
else
    check_fail "Missing required variables in .env" "Ensure JIRA_BASE_URL, JIRA_EMAIL, and JIRA_API_TOKEN are set."
    echo ""
    echo "=== RESULT: $FAIL check(s) failed. Fix the issues above and re-run. ==="
    exit 1
fi
echo ""

# Build auth header
AUTH=$(printf '%s:%s' "$JIRA_EMAIL" "$JIRA_API_TOKEN" | base64)

# 3. Check API connectivity
echo "3. Jira API Connectivity"
MYSELF_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Basic $AUTH" \
    -H "Content-Type: application/json" \
    "$JIRA_BASE_URL/rest/api/3/myself" 2>&1)

HTTP_CODE=$(echo "$MYSELF_RESPONSE" | tail -1)
BODY=$(echo "$MYSELF_RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" == "200" ]]; then
    DISPLAY_NAME=$(echo "$BODY" | jq -r '.displayName // "Unknown"')
    check_pass "API connected successfully (authenticated as: $DISPLAY_NAME)"
elif [[ "$HTTP_CODE" == "401" ]]; then
    check_fail "Authentication failed (HTTP 401)" "Check your JIRA_EMAIL and JIRA_API_TOKEN in .env."
    echo ""
    echo "=== RESULT: $FAIL check(s) failed. Fix the issues above and re-run. ==="
    exit 1
elif [[ "$HTTP_CODE" == "000" ]]; then
    check_fail "Cannot reach Jira server" "Check JIRA_BASE_URL ($JIRA_BASE_URL). Are you connected to the network?"
    echo ""
    echo "=== RESULT: $FAIL check(s) failed. Fix the issues above and re-run. ==="
    exit 1
else
    check_fail "Unexpected response (HTTP $HTTP_CODE)" "Response: $(echo "$BODY" | head -3)"
fi
echo ""

# 4. Check project access
echo "4. Project Access"
PROJECT_KEY=$(get_config "jira.project_key")
if [[ -z "$PROJECT_KEY" ]]; then
    check_fail "jira.project_key not set in config.yaml" "Set jira.project_key in config.yaml to your Jira project key."
    echo ""
    echo "=== RESULT: $FAIL check(s) failed. Fix the issues above and re-run. ==="
    exit 1
fi

PROJECT_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Basic $AUTH" \
    -H "Content-Type: application/json" \
    "$JIRA_BASE_URL/rest/api/3/project/$PROJECT_KEY" 2>&1)

HTTP_CODE=$(echo "$PROJECT_RESPONSE" | tail -1)
BODY=$(echo "$PROJECT_RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" == "200" ]]; then
    PROJECT_NAME=$(echo "$BODY" | jq -r '.name // "Unknown"')
    check_pass "Project $PROJECT_KEY accessible ($PROJECT_NAME)"
elif [[ "$HTTP_CODE" == "404" ]]; then
    check_fail "Project $PROJECT_KEY not found" "Verify the project key in config.yaml."
else
    check_fail "Cannot access project $PROJECT_KEY (HTTP $HTTP_CODE)" "$(echo "$BODY" | jq -r '.errorMessages[0] // "Unknown error"' 2>/dev/null)"
fi
echo ""

# 5. Check search
echo "5. JQL Search"
SEARCH_JQL="project = $PROJECT_KEY ORDER BY created DESC"
ENCODED_JQL=$(printf '%s' "$SEARCH_JQL" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null || echo "project%20%3D%20${PROJECT_KEY}%20ORDER%20BY%20created%20DESC")

SEARCH_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Basic $AUTH" \
    -H "Content-Type: application/json" \
    "$JIRA_BASE_URL/rest/api/3/search/jql?jql=$ENCODED_JQL&maxResults=1" 2>&1)

HTTP_CODE=$(echo "$SEARCH_RESPONSE" | tail -1)
BODY=$(echo "$SEARCH_RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" == "200" ]]; then
    ISSUE_COUNT=$(echo "$BODY" | jq -r '.issues | length')
    IS_LAST=$(echo "$BODY" | jq -r '.isLast // true')
    if [[ "$IS_LAST" == "true" ]]; then
        check_pass "Search works ($ISSUE_COUNT ticket(s) returned for $PROJECT_KEY)"
    else
        check_pass "Search works ($ISSUE_COUNT+ tickets in $PROJECT_KEY)"
    fi
else
    check_fail "Search failed (HTTP $HTTP_CODE)" "$(echo "$BODY" | jq -r '.errorMessages[0] // "Unknown error"' 2>/dev/null)"
fi
echo ""

# Summary
echo "=== RESULT ==="
if [[ $FAIL -eq 0 ]]; then
    echo "All $PASS checks passed. Jira access is configured correctly."
    exit 0
else
    echo "$FAIL check(s) failed, $PASS passed. Fix the issues above and re-run."
    exit 1
fi
