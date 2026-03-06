---
name: validate-log-standards
description: >
  Validates the codebase and real log output against the organization's Logging
  Standards (LoggingStandards.pdf). Checks Monolog configuration, scans source
  code for PII exposure, verifies trace ID propagation, audits log levels, and
  cross-references the log database. Produces a prioritized compliance report
  with actionable improvements.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Validate Logging Standards

You are auditing the codebase and log output against the organization's logging standards to produce a compliance report.

**No arguments required.** This skill runs a full audit every time.

## Current State

!`echo "=== Logging Standards Validation ===" && echo "Standards file: $([ -f {{WORKSPACE}}/data/logging-standards.yaml ] && echo 'EXISTS' || echo 'MISSING')" && echo "Last report: $([ -f {{WORKSPACE}}/reports/compliance-report.md ] && stat -f '%Sm' {{WORKSPACE}}/reports/compliance-report.md 2>/dev/null || echo 'none')" && echo "Log database: $([ -f {{WORKSPACE}}/data/log-database/log-types.yaml ] && echo 'EXISTS' || echo 'MISSING')" && echo "Archive logs: $(ls {{WORKSPACE}}/log-archive/*/*.txt 2>/dev/null | wc -l | tr -d ' ') files" && echo "Ticket logs: $(ls {{WORKSPACE}}/tickets/*/logs/*.txt 2>/dev/null | wc -l | tr -d ' ') files"`

---

## Phase 1: Load Standards & Configuration

### Step 1: Load Standards

Read `{{WORKSPACE}}/data/logging-standards.yaml` for the complete rule set. This is the source of truth for all checks.

If it doesn't exist: **"Standards file missing. Create it first from LoggingStandards.pdf."** and stop.

### Step 2: Load Monolog & Service Configuration

Read these configuration files (all are needed for the audit):

1. `api/config/packages/monolog.yaml` — base Monolog config (imports per-module configs)
2. `api/config/packages/prod/monolog.yaml` — production handler config
3. `api/config/packages/staging/monolog.yaml` — staging config
4. `api/config/packages/dev/monolog.yaml` — dev config
5. `{{WORKSPACE}}/config.yaml` — module list, channels, service info

Note which handlers exist, their types, formatters, levels, and channels.

---

## Phase 2: Codebase Compliance Audit

Each step checks a specific rule category. **Use grep for targeted scanning — never read entire source files.**

Initialize a results tracker with these categories and their rules:

```
format:    json_format, required_fields, type_values, audit_action, stacktrace_field
pii:       no_national_id, no_phone, no_email, no_names, no_credentials, no_request_body_pii
levels:    correct_levels, no_debug_prod, level_appropriateness
context:   trace_id_present, sufficient_context, remediation_info
```

Each rule result: **PASS**, **FAIL** (with evidence), or **N/A** (with reason).

### Step 3: JSON Format Configuration

Check if Monolog handlers produce JSON output.

1. In the base `monolog.yaml`: look for `formatter:` entries and handler `type:` values
2. In `prod/monolog.yaml`: check production handlers for `JsonFormatter` or `json` type
3. Check for any custom formatters:

```bash
grep -rn 'JsonFormatter\|LineFormatter\|HtmlFormatter' api/config/packages/ --include='*.yaml'
```

4. Check if a custom Monolog formatter class exists:

```bash
grep -rn 'class.*implements.*FormatterInterface\|extends.*JsonFormatter' api/src/ --include='*.php'
```

**Rule `json_format`**: PASS if all production handlers use JSON formatter. FAIL if any use line/console format.
**Rule `required_fields`**: Check if processors/formatters inject the required fields (timestamp, type, level, context, message, traceId).
**Rule `type_values`**: Check if a `type` field (audit/application/stacktrace) is injected into log entries.

### Step 4: Required JSON Fields

Check if Monolog processors add the required fields from the standards.

1. Find all Monolog processors:

```bash
grep -rn 'class.*implements.*ProcessorInterface\|tags:.*monolog.processor' api/src/ api/config/ --include='*.php' --include='*.yaml' --include='*.yml'
```

2. Read the main processor (likely `api/src/Framework/Infrastructure/Monolog/MonologProcessor.php`) to see which fields it adds to the `extra` or `context` array.

3. Check for each required field: timestamp, type, level, context, message, traceId.

### Step 5: PII in Log Calls

Scan the codebase for PII field names appearing in logging calls.

For each PII rule (`no_national_id`, `no_phone`, `no_email`, `no_names`, `no_credentials`), grep using the patterns from the standards file:

```bash
# National ID patterns in log-related code
grep -rn 'personalNumber\|national_id\|nationalId\|saudiNonSaudiId\|idNumber\|iqamaNumber' \
  api/src/Module/SharedKernel/Infrastructure/ \
  api/src/Module/*/Infrastructure/Adapter/ \
  api/src/Module/*/Presentation/Listener/ \
  api/src/Framework/Presentation/Listener/ \
  --include='*.php' | grep -i 'log\|logger\|info\|warning\|error\|critical\|debug'
```

```bash
# Phone/recipient patterns in log-related code
grep -rn 'phoneNumber\|phone_number\|mobile\|mobileNumber\|recipient' \
  api/src/Module/SharedKernel/Infrastructure/ \
  api/src/Module/*/Infrastructure/ \
  --include='*.php' | grep -i 'log\|logger\|info\|warning\|error\|critical\|debug\|sprintf\|format'
```

```bash
# Email patterns in log-related code
grep -rn 'email\|emailAddress' \
  api/src/Module/SharedKernel/Infrastructure/ \
  --include='*.php' | grep -i 'log\|logger\|info\|warning\|error\|critical\|debug'
```

**Important**: For each grep hit, note the exact file path and line number. Determine whether the PII value is actually being logged (passed to a logger method) vs. just being referenced in business logic.

Focus on these known high-risk files:
- `SharedKernel/Infrastructure/Notifications/LoggableNotificationSenderDecorator.php` — notification logs
- `SharedKernel/Infrastructure/Client/LoggableHttpClient.php` — base HTTP client decorator
- All `Loggable*Decorator.php` files — client decorators that log request/response data

### Step 6: Request Body Logging

Check for raw request body logging (a common PII vector):

```bash
grep -rn 'getBody\|getContent\|request_data\|request_body\|requestBody\|requestData' \
  api/src/Module/SharedKernel/Infrastructure/Client/ \
  api/src/Module/*/Infrastructure/Adapter/ \
  --include='*.php' | grep -i 'log\|context\|info\|warning\|error\|critical'
```

Also check the base loggable client decorator:

```bash
grep -rn 'request_data\|getBody\|toArray' \
  api/src/Module/SharedKernel/Infrastructure/Client/LoggableHttpClient.php
```

**Rule `no_request_body_pii`**: FAIL if request bodies are logged without sanitization. Note which decorators pass unsanitized `request_data` to logger context.

### Step 7: Trace ID Inclusion

Verify trace ID propagation through the logging chain.

1. Read the Monolog processor to confirm it extracts `X-Request-Id`:

```bash
grep -rn 'X-Request-Id\|request_id\|traceId\|trace_id' \
  api/src/Framework/Infrastructure/Monolog/ \
  --include='*.php'
```

2. Check exception listeners — do they include request_id in context?

```bash
grep -rn 'request_id\|requestId' \
  api/src/Module/SharedKernel/Presentation/Listener/AbstractExceptionListener.php \
  api/src/Framework/Presentation/Listener/Unhandled.php
```

3. Check if any loggers bypass the Monolog processor (e.g., direct `NullLogger` or standalone logger instances):

```bash
grep -rn 'NullLogger\|new Logger' api/src/ --include='*.php'
```

**Rule `trace_id_present`**: PASS if MonologProcessor injects request_id AND exception listeners propagate it. FAIL if there are code paths that bypass the processor.

### Step 8: Log Level Configuration

Check production log level settings and NullLogger usage.

1. In `prod/monolog.yaml`: what is the minimum level for each handler?

```bash
grep -n 'level:\|type:\|channels:' api/config/packages/prod/monolog.yaml
```

2. Check for NullLogger usage (silences errors entirely):

```bash
grep -rn 'NullLogger' api/src/ api/config/ --include='*.php' --include='*.yaml' --include='*.yml'
```

3. Check for DEBUG-level log calls in non-test code:

```bash
grep -rn '->debug(' api/src/ --include='*.php' | grep -v '/Tests/' | head -30
```

**Rule `no_debug_prod`**: PASS if prod config sets minimum level to INFO or above.
**Rule `level_appropriateness`**: Flag external failures logged as INFO/WARNING instead of ERROR, and routine operations logged as ERROR.

---

## Phase 3: Log Database Cross-Reference

### Step 9: Log Database Audit

Read `{{WORKSPACE}}/data/log-database/log-types.yaml` and check each log type against the standards.

1. **Type field mapping**: Does each log type map to a standard type (audit, application, stacktrace)?
   - Module exception logs (_CASE tags) → application
   - Client success/failure logs → application
   - AdminDashboard event logs → audit
   - Notification logs → application
   - Flag any log types that don't clearly map to one of the three standard types

2. **PII in context_fields**: For each log type, check if its `context_fields` contain PII-adjacent field names:
   - `request_data` — may contain PII from request bodies
   - `personalNumber`, `recipient` — direct PII
   - `response` — may contain PII from external service responses
   - `body` — may contain unsanitized request/response content

3. **Severity appropriateness**: Flag log types where the severity seems wrong:
   - External service failures at WARNING instead of ERROR/CRITICAL
   - Routine operations at ERROR
   - Debug information at INFO in production

Record findings as: `{log_type_id}: {finding}` for the report.

---

## Phase 4: Real Log Sampling

### Step 10: Sample Actual Log Output

Check real log files for standards compliance. **Never read entire log files — sample with head/grep.**

1. **Find available log files**:

```bash
ls -la {{WORKSPACE}}/log-archive/*/  2>/dev/null | head -20
ls -la {{WORKSPACE}}/tickets/*/logs/ 2>/dev/null | head -20
```

2. **Sample format** (up to 5 files, 20 lines each):

```bash
# Pick files and check format
for f in $(ls {{WORKSPACE}}/log-archive/*/*.txt {{WORKSPACE}}/tickets/*/logs/*.txt 2>/dev/null | head -5); do
  echo "=== $f ===" && head -20 "$f"
done
```

Check each sample:
- Is it JSON format (one JSON object per line)? Or line-based Monolog format?
- Does each entry contain `request_id` or `traceId`?
- Are there DEBUG-level entries?

3. **PII in actual output**:

```bash
# National ID pattern (10-digit numbers starting with 1 or 2)
grep -n -E '\b[12][0-9]{9}\b' {{WORKSPACE}}/log-archive/*/*.txt {{WORKSPACE}}/tickets/*/logs/*.txt 2>/dev/null | head -20

# Phone numbers
grep -n -E '\+?966[0-9]{9}|05[0-9]{8}' {{WORKSPACE}}/log-archive/*/*.txt {{WORKSPACE}}/tickets/*/logs/*.txt 2>/dev/null | head -20

# Email addresses
grep -n -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}' {{WORKSPACE}}/log-archive/*/*.txt {{WORKSPACE}}/tickets/*/logs/*.txt 2>/dev/null | head -20
```

4. **DEBUG entries in prod logs**:

```bash
grep -c '\.DEBUG:' {{WORKSPACE}}/log-archive/*/*.txt {{WORKSPACE}}/tickets/*/logs/*.txt 2>/dev/null | grep -v ':0$'
```

If no log files are available, mark all `log_output` rules as **N/A — no log files available for sampling** and note this in the report.

---

## Phase 5: Generate Report

### Step 11: Compile Results

Tally results per category:
- Count PASS, FAIL, N/A for each rule
- Order findings by severity (critical → high → medium → low)
- For each FAIL: include rule ID, what was found, specific file paths with line numbers, and remediation

### Step 12: Write Compliance Report

Write to `{{WORKSPACE}}/reports/compliance-report.md`:

```markdown
# Logging Standards Compliance Report

> Generated: {date} | Standards: logging-standards.yaml v{version}

## Summary

| Category | Rules | Pass | Fail | N/A |
|----------|-------|------|------|-----|
| Format   | 5     | ...  | ...  | ... |
| PII      | 6     | ...  | ...  | ... |
| Levels   | 3     | ...  | ...  | ... |
| Context  | 3     | ...  | ...  | ... |
| **Total** | **17** | ... | ... | ... |

**Overall Compliance**: {pass_count}/{total_applicable} ({percentage}%)

## Critical Findings

{Ordered by severity. Each finding includes:}
### {severity}: {rule_id} — {short description}
- **Rule**: {requirement from standards}
- **Evidence**: {what was found, with file:line references}
- **Impact**: {why this matters}
- **Remediation**: {specific fix}

## Detailed Results by Category

### Format Compliance
{Per-rule PASS/FAIL with evidence}

### PII Exposure
{Per-rule PASS/FAIL with evidence — file paths and line numbers for every finding}

### Log Level Usage
{Per-rule PASS/FAIL with evidence}

### Context & Trace ID
{Per-rule PASS/FAIL with evidence}

## Log Database Gaps

{Log types that don't map to standard categories (audit/application/stacktrace)}
{Log types with PII-adjacent context_fields}
{Log types with inappropriate severity levels}

## Real Log Findings

{Format check results from sampled files}
{PII detected in actual output}
{DEBUG entries found in prod logs}
{Trace ID presence in actual entries}

(If no log files were available, note: "No log files available for sampling. Re-run after fetching logs.")

## Actionable Improvements

### Quick Wins (< 1 day)
{Small configuration changes, single-file fixes}

### Medium Effort (1-3 days)
{Multi-file changes, new processors/formatters}

### Larger Changes (1+ week)
{Architectural changes, new logging infrastructure}
```

### Step 13: Report to User

Present the summary:

```
=== Logging Standards Compliance Report ===

Overall: {pass_count}/{total} ({percentage}%)

Critical findings: {count}
  - {rule_id}: {one-line summary} ({file})
  ...

High findings: {count}
  - ...

Report written to: {{WORKSPACE}}/reports/compliance-report.md
```

Suggest next steps based on findings:
- If critical PII findings: **"Critical PII exposure found. Address these first — they represent data protection risks."**
- If format non-compliance: **"Logs are not JSON formatted. Consider adding a JsonFormatter to Monolog production config."**
- If no log files for sampling: **"No real log files found for output validation. Fetch recent logs to complete the audit."**

## Important Rules

- **Never read entire source files** — use grep for targeted scanning.
- **Never read entire log files** — sample with head/grep.
- **Report file paths and line numbers** for every finding.
- **Don't propose changes that break existing functionality** — flag for review.
- **PII findings are always CRITICAL** regardless of other context.
- **Distinguish between PII field names in business logic vs. in logging calls** — only flag actual logging of PII values.
- **Check both the code AND the config** — a secure formatter doesn't help if the code logs PII in the message string.
