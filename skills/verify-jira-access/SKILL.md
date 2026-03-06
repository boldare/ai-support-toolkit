---
name: verify-jira-access
description: >
  Verifies Jira API credentials and project access for the M&S toolkit.
  Checks prerequisites, .env configuration, API connectivity, project access,
  and search capability. Run this after setting up .env credentials or when
  troubleshooting Jira connectivity issues.
disable-model-invocation: true
allowed-tools: Read, Bash, AskUserQuestion
---

# Verify Jira Access

You are verifying Jira API access for the M&S toolkit.

## Current State

!`echo "=== .env configured? ===" && ([ -f {{TOOLKIT}}/.env ] && echo "YES — $(grep -c '=' {{TOOLKIT}}/.env | tr -d ' ') variables set" || echo "NO — needs setup") && echo "" && echo "=== Last verification ===" && ([ -f {{TOOLKIT}}/.env ] && echo "Run the script below to check" || echo "N/A")`

## What This Does

Runs the verification script that checks:
1. Prerequisites (curl, jq, python3)
2. `.env` file exists with required variables
3. API connectivity to the Jira server
4. Authentication with provided credentials
5. Project access for the configured project key
6. Search capability (JQL query execution)

## Instructions

### Step 1: Check Prerequisites

Verify the script exists:

```bash
ls -la {{TOOLKIT}}/scripts/setup/verify-jira-access.sh
```

If it doesn't exist, inform the user and stop.

### Step 2: Run Verification

Execute the verification script:

```bash
bash {{TOOLKIT}}/scripts/setup/verify-jira-access.sh
```

### Step 3: Handle Results

**If all checks pass**: Report success. The toolkit is ready to fetch tickets.

**If any check fails**: Read the error output and help the user fix it:

| Error | Fix |
|-------|-----|
| "Missing .env file" | Guide user to create `{{TOOLKIT}}/.env` from `.env.example` |
| "Missing JIRA_BASE_URL" | Help set the correct Atlassian URL |
| "Missing JIRA_EMAIL" | Help set the Atlassian account email |
| "Missing JIRA_API_TOKEN" | Direct to https://id.atlassian.net/manage-profile/security/api-tokens |
| "Cannot reach Jira server" | Check URL format, network, VPN |
| "Authentication failed (401)" | Token may be expired or email wrong |
| "Project not found" | Check project key in config.yaml |
| "Search failed" | Check JQL syntax or project permissions |

### Step 4: If .env Doesn't Exist

If `.env` is missing, guide the user through setup:

1. Check if `.env.example` exists and read it:
   ```
   {{TOOLKIT}}/.env.example
   ```

2. Ask the user for their Jira details:
   - Jira base URL (e.g., `https://yourorg.atlassian.net`)
   - Jira email
   - API token (from https://id.atlassian.net/manage-profile/security/api-tokens)

3. Create the `.env` file with their values

4. Re-run verification

## Important Rules

- **Never display the full API token** — only show first/last 4 characters if needed for debugging.
- **`.env` is gitignored** — remind the user it's safe to store credentials there.
- **Don't modify config.yaml** during verification — only check it.
