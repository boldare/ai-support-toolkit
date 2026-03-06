---
name: init-log-database
description: >
  Builds the initial log type database from source code analysis. First discovers
  the codebase's language, framework, and logging patterns, then analyzes each
  module to catalog all log-producing code. Works with any language/framework
  that follows DDD or modular monolith architecture. Use on a fresh codebase
  (before any ticket logs exist) or to add new modules to an existing database.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, AskUserQuestion
---

# Init Log Database

You are building the log type database for a service by analyzing its source code.

This skill forms the first stage of a two-skill pipeline:
1. **`/init-log-database`** (this skill) — builds the database from codebase analysis
2. **`/update-log-database`** — enriches it with real ticket log data (frequency, examples)

## Current State

!`echo "=== Database exists? ===" && ([ -f {{WORKSPACE}}/data/log-database/log-types.yaml ] && echo "YES — $(grep 'total_log_types:' {{WORKSPACE}}/data/log-database/log-types.yaml | head -1 | tr -d ' ')" || echo "NO — fresh init needed") && echo "" && echo "=== Codebase profile ===" && ([ -f {{WORKSPACE}}/data/codebase-profile.yaml ] && echo "YES — Phase 1 will be skipped" || echo "NO — Phase 1 discovery needed") && echo "" && echo "=== Toolkit config ===" && ([ -f {{WORKSPACE}}/config.yaml ] && echo "Found" || echo "NOT FOUND — run toolkit setup first") && echo "" && echo "=== Modules in config ===" && (grep '^\s*- name:' {{WORKSPACE}}/config.yaml 2>/dev/null | sed 's/.*name: *"\(.*\)"/  \1/' || echo "  (no config)") && echo "" && echo "=== Modules already in database ===" && ([ -f {{WORKSPACE}}/data/log-database/log-types.yaml ] && grep '# MODULE:' {{WORKSPACE}}/data/log-database/log-types.yaml | sed 's/.*MODULE: */  /' || echo "  (none)")`

---

## Phase 1: Codebase Discovery

Before analyzing any module, you must understand the codebase. This phase produces a **Codebase Profile** that drives all subsequent analysis.

**Skip check**: If `{{WORKSPACE}}/data/codebase-profile.yaml` exists, read it and skip directly to **Phase 2** (Step 7). The persisted profile contains all discovery results from a previous run. Only re-run Phase 1 if the user explicitly asks to rediscover, or if the profile file is missing.

### Step 1: Detect Language and Framework

Examine the project root to identify:

**Language** — Look for telltale files:
- `composer.json` → PHP
- `pom.xml` / `build.gradle` / `build.gradle.kts` → Java/Kotlin
- `Gemfile` → Ruby
- `package.json` → Node.js/TypeScript
- `go.mod` → Go
- `Cargo.toml` → Rust
- `requirements.txt` / `pyproject.toml` / `setup.py` → Python

**Framework** — Read the dependency/build file to identify:
- PHP: Symfony, Laravel, Slim
- Java: Spring Boot, Quarkus, Micronaut, Jakarta EE
- Ruby: Rails, Sinatra, Hanami
- Node.js: Express, NestJS, Fastify
- Go: Gin, Echo, standard library
- Python: Django, FastAPI, Flask

**Logging library** — Identify from dependencies:
- PHP: Monolog, PSR-3 Logger
- Java: SLF4J + Logback, Log4j2, java.util.logging
- Ruby: Ruby Logger, Semantic Logger, Rails.logger
- Node.js: Winston, Pino, Bunyan
- Go: zerolog, zap, slog, logrus
- Python: stdlib logging, structlog, loguru

Record the source file extension(s) for this language (e.g., `.php`, `.java`, `.rb`, `.ts`).

### Step 2: Discover Module Structure

DDD and modular monolith codebases organize code into bounded contexts/modules. Find where they live:

1. **Read `config.yaml`** — the `modules` section is the canonical list if it exists
2. **Scan the source tree** — look for the module root directory:
   - Common patterns: `src/Module/*/`, `src/main/java/**/module/*/`, `app/modules/*/`, `src/bounded-contexts/*/`, `src/domains/*/`, `lib/*/`
   - Each subdirectory is typically a module/bounded context
3. **Identify shared/framework modules** — look for cross-cutting code:
   - Names like `SharedKernel`, `Framework`, `Common`, `Core`, `Infrastructure`, `Shared`
   - These often contain logging wrappers used by other modules

Report the module root path and list all discovered modules.

### Step 3: Identify Logging Infrastructure

Examine the logging configuration to understand:

**a) Log channels / logger names**
- Look for logging config files (e.g., `monolog.yaml`, `logback.xml`, `logback-spring.xml`, `log4j2.xml`, `config/logging.rb`, `logging.conf`)
- Extract declared channels/logger names and which modules use them
- Cross-reference with `config.yaml`'s `logging.channels` section if it exists

**b) Log output format**
- Determine the structured log format used in production (JSON, logfmt, key=value, etc.)
- Note the timestamp format, severity field name, channel/logger field name
- This is needed to write realistic `example` fields later

**c) Request tracing**
- Look for correlation/request ID middleware (MDC in Java, Monolog processors in PHP, Rails middleware, etc.)
- Note the field name (e.g., `request_id`, `trace_id`, `correlation_id`)

### Step 4: Catalog Logging Patterns

Scan the codebase to identify the **recurring patterns** through which log entries are produced. Every codebase has a finite set of these. Common DDD/modular monolith patterns:

**a) Global/module exception handlers**
Search for exception handler/listener classes that catch domain exceptions and log them. These are the equivalent of "catch-all" error responses per module.
- In Symfony: `ExceptionListener`, `ExceptionSubscriber` extending `AbstractExceptionListener`
- In Spring: `@ControllerAdvice` / `@ExceptionHandler` classes
- In Rails: `rescue_from` in controllers or `ActionDispatch::ExceptionWrapper`
- In NestJS: `@Catch()` exception filters
- In Go: middleware that recovers panics

For each handler found, note: which module it belongs to, what tag/code it logs, what exceptions it maps.

**b) Logging decorators/wrappers**
Search for the decorator pattern applied to external service clients. These wrap API calls with success/failure logging. Look for:
- Class names containing `Loggable`, `Logging`, `Instrumented`, `Traced`, `Monitored`
- Classes that implement the same interface as another class and add logging around delegated calls
- Base classes that provide `logSuccess()` / `logFailure()` / `logError()` helper methods

For each decorator pattern found, note: the base class, how tags are constructed, which severity levels are used, what context fields are logged.

**c) Direct logger calls**
These are standalone logger invocations outside of decorators and exception handlers. Search for the language's logger call syntax:
- PHP: `$this->logger->`, `$this->log(`
- Java: `logger.info(`, `log.error(`, `LOGGER.warn(`
- Ruby: `logger.info`, `Rails.logger.error`
- Node.js: `this.logger.log(`, `logger.info(`
- Go: `logger.Info(`, `slog.Error(`
- Python: `logger.info(`, `logging.error(`

### Step 5: Present Codebase Profile

Summarize your findings and present them to the user for confirmation before proceeding:

```
=== Codebase Profile ===

Language:      {language} ({version if detectable})
Framework:     {framework} ({version})
Logging:       {library} → {output format}
Tracing:       {correlation_id field} via {mechanism}
Module root:   {path}
Modules:       {count} ({list})

Logging patterns discovered:
  1. Exception handlers — {count} found ({brief description of pattern})
  2. Logging decorators — {count} found across {N} base classes:
     - {BaseClass1}: {tag format}, {count} implementations
     - {BaseClass2}: {tag format}, {count} implementations
  3. Direct logger calls — {estimate} across all modules

Recommended processing order:
  1. {Framework/Core module} — foundation exception handlers
  2. {SharedKernel/Common module} — cross-cutting client wrappers
  3. Remaining modules alphabetically
```

Ask: **"Does this look correct? Any corrections before I proceed?"**

### Step 6: Persist Codebase Profile

After user confirmation, write the profile to `{{WORKSPACE}}/data/codebase-profile.yaml`:

```yaml
# Codebase Profile — persisted by /init-log-database Phase 1
# Re-run Phase 1 to regenerate if codebase structure changes significantly
generated: "{today's date}"

language: "{language}"
language_version: "{version or null}"
framework: "{framework}"
framework_version: "{version}"
source_extensions: ["{ext1}", "{ext2}"]

logging:
  library: "{library_name}"
  output_format: "{format}"
  config_file: "{path to logging config}"
  request_tracing:
    field: "{correlation_id field name}"
    mechanism: "{how it's injected}"

module_root: "{path}"
modules:
  - name: "{ModuleName}"
    path: "{relative path}"
    type: "{core|shared|domain}"  # core = framework, shared = cross-cutting, domain = business

logging_patterns:
  exception_handlers:
    count: {N}
    description: "{how they work in this codebase}"
    search_pattern: "{class name or annotation to grep for}"
  decorators:
    count: {N}
    base_classes:
      - name: "{ClassName}"
        tag_format: "{how tags are constructed}"
        implementations: {count}
    search_pattern: "{class name or interface to grep for}"
  direct_calls:
    estimate: "{rough count}"
    search_pattern: "{logger call syntax to grep for}"

recommended_order:
  - "{CoreModule}"
  - "{SharedModule}"
  # remaining alphabetically
```

This file is read on subsequent `/init-log-database` runs to skip Phase 1 entirely.

---

## Phase 2: Database Construction

### Step 7: Detect Mode

**If `log-types.yaml` does NOT exist** → **Fresh Init Mode** → go to Step 8
**If `log-types.yaml` EXISTS** → **Add-Module Mode** → go to Step 9

### Step 8: Scaffold (Fresh Init Only)

Create `{{WORKSPACE}}/data/log-database/log-types.yaml` with:

```yaml
# =============================================================================
# Log Type Database — {service_name from config.yaml}
# =============================================================================
# Generated: {today's date}
# Source: Codebase analysis (source code, not log files)
# Purpose: Foundation for automated ticket log analysis
# =============================================================================

metadata:
  version: "1.0"
  generated: "{today's date}"
  source_commit: "{get from: git rev-parse --short HEAD}"
  total_log_types: 0
  total_noise_patterns: 0
  mapped_tickets: []
```

Then discover and add **noise patterns** — non-actionable log lines to filter during analysis. Build this list from two sources:

**a) Universal noise** (always applicable):
- Health/readiness/liveness probe endpoints
- CORS preflight OPTIONS requests
- Empty/whitespace-only lines
- Log aggregator wrapper artifacts (Loki `[WARN: Non-Compliant-JSON]`, Fluentd metadata, etc.)

**b) Framework-specific noise** (discovered in Phase 1):
- Framework router/request debug logging
- HTTP client success responses (only failures are interesting)
- Auth/security routine debug messages
- Message queue routine lifecycle (received/handled/sent)
- ORM/database debug queries
- Cache hit/miss debug
- Container lifecycle events (if Kubernetes)
- Language-specific deprecation warnings
- Duplicate log format lines (e.g., console + JSON format in same stream)

For each noise pattern, create an entry:
```yaml
- id: noise_{descriptive_name}
  pattern: '{regex pattern}'
  description: {Why this is noise and can be filtered}
```

Update `total_noise_patterns` in metadata after writing.

Then add an empty `log_types:` section:
```yaml
log_types:
```

### Step 9: Module Selection

Present all modules to the user. Read the list from `config.yaml` (canonical) and cross-reference with the source tree.

Display format:
```
Modules available for analysis:

  {CoreModule} ........... [recommended first — foundation handlers]
  {SharedModule} ......... [recommended second — cross-cutting wrappers]
  ---
  {Module1}                {complexity indicator}
  {Module2}                {complexity indicator}
  ...
```

Mark already-mapped modules with `[done]` in add-module mode.

**Complexity indicators** — quickly scan each unmapped module:
- Count files matching the decorator/wrapper patterns discovered in Phase 1
- Count files containing the exception handler pattern
- Count files with direct logger calls
- Display: (blank) = minimal logging, one exclamation mark = has decorators/wrappers, two exclamation marks = multiple patterns

Ask: **"Which module to analyze? (or 'all remaining')"**

### Step 10: Analyze Module

For each selected module, perform **4 analysis passes** using the patterns discovered in Phase 1. Read each relevant file fully — don't grep and guess.

#### Pass 1: Logging Channels

Find the module's logging channel configuration:
- Check framework-specific config files (per-module or central)
- Cross-reference with `config.yaml`'s `logging.channels` section
- If no dedicated config exists, the module uses the default/root channel

Record which channel names this module logs to.

#### Pass 2: Exception Handlers

Find the module's exception handler(s) using the pattern cataloged in Phase 1, Step 4a.

Read each handler to extract:
- The tag/error code it logs (e.g., `[MODULE_CASE]`, error code enum, etc.)
- The channel it logs to
- The severity level
- The list of domain exceptions it handles and their HTTP status codes
- Context fields included in the log entry

Create an entry for each handler. **Every module with an exception handler gets an entry**, even if it has no other log types.

#### Pass 3: Logging Decorators/Wrappers

Find decorator/wrapper classes in this module using the patterns cataloged in Phase 1, Step 4b.

Read each decorator to extract:
- Which base class/pattern it follows
- The tag(s) it produces and how they're constructed
- Severity levels for success vs failure paths
- Context fields logged
- What triggers each log call (which external service, which operation)

Create entries for each distinct log output. Group related entries (e.g., SUCCESS/FAILED pairs).

#### Pass 4: Direct Logger Calls

Search for logger invocations in the module's source code that are NOT inside files already covered by Pass 2 and Pass 3.

For each unique log pattern found:
- Read the surrounding code to understand tag, message, severity, and trigger
- Create an entry

### Step 11: Generate and Write Entries

For each log type discovered, create a YAML entry:

```yaml
- id: {unique_snake_case_id}
  tag: {TAG_NAME}           # or "null" if no bracket tag, or "dynamic" if tag varies
  severity: {CRITICAL|ERROR|WARNING|INFO|DEBUG}
  channel: {logger_channel_name}
  module: {ModuleName}
  source: {fully.qualified.ClassName}
  message_template: "{template with {placeholders}}"
  trigger: >
    {1-3 sentences explaining what causes this log entry to be emitted}
  indicates: {category}
  context_fields:
    - {field_name}
  common_in_tickets: false   # Always false at init time — no ticket data yet
  example: "{realistic log line as it would appear in production}"
```

**`indicates` classification:**
- `external_integration_issue` — external service call failed
- `expected_behavior` — normal operation, success logs, auth checks, info messages
- `business_rule_rejection` — domain validation failures, business rule errors (400/404/422)
- `data_quality_issue` — invalid/missing data from external sources
- `internal_error` — unhandled exceptions, bugs, programmer errors

**Write to log-types.yaml:**

1. Add a module section header:
   ```yaml
   # ---------------------------------------------------------------------------
   # MODULE: {ModuleName}
   # ---------------------------------------------------------------------------
   ```

2. Place entries under the header. Group related entries together.

3. Update `metadata.total_log_types` count.

4. Update `metadata.generated` to today's date.

5. **Validate**:
   ```bash
   python3 -c "import yaml; yaml.safe_load(open('{{WORKSPACE}}/data/log-database/log-types.yaml'))"
   ```

6. **Check for duplicate IDs**:
   ```bash
   grep '^\s*- id:' {{WORKSPACE}}/data/log-database/log-types.yaml | sort | uniq -d
   ```

7. **Verify file structure against template**:

   Read `{{TOOLKIT}}/templates/log-types.yaml` and verify the generated file conforms to the schema:

   a) **Metadata section** — must contain all required fields:
      - `version`, `generated`, `source_commit`, `total_log_types`, `total_noise_patterns`, `mapped_tickets`

   b) **Noise patterns** — each entry must have:
      - `id`, `pattern`, `description`

   c) **Log type entries** — each entry must have all required fields:
      - `id`, `tag`, `severity`, `channel`, `module`, `source`, `message_template`, `trigger`, `indicates`, `context_fields`, `common_in_tickets`, `example`

   d) **Field values** — validate:
      - `severity` is one of: `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`
      - `indicates` is one of: `external_integration_issue`, `expected_behavior`, `business_rule_rejection`, `data_quality_issue`, `internal_error`
      - `tag` is a string, `"null"`, or `"dynamic"`
      - `context_fields` is a list (can be empty `[]`)
      - `common_in_tickets` is a boolean

   Report any missing fields or invalid values before proceeding.

### Step 12: Regenerate LOG_DATABASE.md

Rewrite `{{WORKSPACE}}/data/log-database/LOG_DATABASE.md` from the updated YAML:

```markdown
# Log Type Database

> Generated: {date} | Source: `log-types.yaml` | {N} log types, {M} noise patterns | {P} tickets mapped

This is the human-readable view of the log type database.
The machine-readable source is [`log-types.yaml`](./log-types.yaml).

## Quick Reference
{Table counting entries by `indicates` category}

## Noise Patterns (Filter These)
{Table of all noise patterns}

## Log Types by Module
### {ModuleName} ({count} types)
{Table: Tag | Severity | Indicates | Common?}
{Key insight paragraph summarizing the module's logging}

## Actionability Guide
{Priority order for investigation}

## Architecture Notes
{Log format, logging mechanisms, request tracing — from Codebase Profile}
```

For databases with no `mapped_tickets`, the "Common?" column shows `0/0`.

### Step 13: Continue or Finish

After processing a module, ask: **"Next module? (name, 'all remaining', or 'done')"**

- Another module → go to Step 10
- "all remaining" → process each unmapped module (framework/shared first, then alphabetical)
- "done" → print summary

### Summary Report

```
=== Init Log Database Complete ===

Mode: {Fresh Init | Add Module}
Codebase: {language} / {framework}
Modules processed: {list}
Log types added: {count}
Total log types: {count}
Noise patterns: {count}

Files updated:
  - {{WORKSPACE}}/data/log-database/log-types.yaml
  - {{WORKSPACE}}/data/log-database/LOG_DATABASE.md

Next steps:
  - Run /update-log-database after collecting ticket logs to add frequency data
  - Remaining unmapped modules: {list or "none"}
```

---

## Important Rules

- **Phase 1 before Phase 2** — always run codebase discovery before analyzing modules. The discovered patterns drive everything.
- **Read source files fully** — module files are typically small. Don't grep and guess; read and understand the actual logging logic.
- **`common_in_tickets: false` for all entries** — no ticket data exists at init time. Frequency comes from `/update-log-database`.
- **Every module with an exception handler gets an entry** — even if it has no other log types.
- **Preserve existing entries** in add-module mode — never remove or modify entries for already-mapped modules.
- **Validate YAML** after every write.
- **No duplicate IDs** — check before writing.
- **Recommended processing order**: framework/core module → shared/kernel module → remaining alphabetically.
- **Use config.yaml as the module manifest** — it lists all modules, their channels, and descriptions.