---
name: init-workspace
description: >
  Analyzes the host repository codebase to auto-detect modules, log channels,
  endpoint prefixes, and external integrations. Populates the auto-detected
  sections of config.yaml and generates data/codebase-profile.yaml. Run after
  filling in the manual fields of config.yaml (bootstrap step).
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, AskUserQuestion
---

# Init Workspace

You are analyzing a codebase to auto-populate the service configuration for the M&S Log Analysis Toolkit.

**No arguments required.** This skill analyzes the codebase and fills in the auto-detected sections of `config.yaml`.

## Current State

!`echo "=== Config exists? ===" && ([ -f {{WORKSPACE}}/config.yaml ] && echo "YES" || echo "NO — run bootstrap.sh first") && echo "" && echo "=== Manual fields filled? ===" && ([ -f {{WORKSPACE}}/config.yaml ] && (grep 'name: ""' {{WORKSPACE}}/config.yaml > /dev/null 2>&1 && echo "NO — fill in [MANUAL] fields first" || echo "YES (or partially)") || echo "N/A") && echo "" && echo "=== Codebase profile exists? ===" && ([ -f {{WORKSPACE}}/data/codebase-profile.yaml ] && echo "YES — will update rather than recreate" || echo "NO — will create from scratch") && echo "" && echo "=== Auto-detected sections ===" && ([ -f {{WORKSPACE}}/config.yaml ] && echo "Modules: $(grep '^\s*- name:' {{WORKSPACE}}/config.yaml 2>/dev/null | wc -l | tr -d ' ')" && echo "Integrations: $(grep -c '^\s*- name:' {{WORKSPACE}}/config.yaml 2>/dev/null || echo 0)" || echo "N/A")`

---

## Prerequisites

Read `{{WORKSPACE}}/config.yaml`.

If it doesn't exist: **"Config not found. Run `bash {{TOOLKIT}}/scripts/setup/bootstrap.sh` first."** and stop.

Check that the manual fields are filled in:
- `service.name` must not be empty
- `service.display_name` must not be empty
- `jira.project_key` must not be empty
- `loki.app_label` must not be empty

If any are empty: **"Fill in the [MANUAL] fields in config.yaml first. These are marked with comments."** List the missing fields and stop.

---

## Phase 1: Codebase Discovery

This phase is identical to Phase 1 of `/init-log-database`, but writes its results to both `codebase-profile.yaml` AND `config.yaml`.

**Skip check**: If `{{WORKSPACE}}/data/codebase-profile.yaml` exists, read it and ask: **"Codebase profile already exists. Reuse it, or rediscover from scratch?"**

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
- Java: SLF4J + Logback, Log4j2
- Ruby: Ruby Logger, Semantic Logger
- Node.js: Winston, Pino, Bunyan
- Go: zerolog, zap, slog, logrus
- Python: stdlib logging, structlog, loguru

Record the source file extension(s) for this language.

### Step 2: Discover Module Structure

Find where bounded contexts/modules live:

1. Scan the source tree for the module root directory:
   - Common patterns: `src/Module/*/`, `src/main/java/**/module/*/`, `app/modules/*/`, `src/bounded-contexts/*/`, `src/domains/*/`, `lib/*/`
   - Each subdirectory is typically a module/bounded context

2. Identify shared/framework modules:
   - Names like `SharedKernel`, `Framework`, `Common`, `Core`, `Infrastructure`, `Shared`

Report the module root path and list all discovered modules.

### Step 3: Identify Logging Infrastructure

**a) Log channels / logger names**
- Look for logging config files (e.g., `monolog.yaml`, `logback.xml`, `logging.conf`)
- Extract declared channels/logger names and which modules use them

**b) Log output format**
- Determine the structured log format used in production (JSON, logfmt, etc.)

**c) Request tracing**
- Look for correlation/request ID middleware
- Note the field name (e.g., `request_id`, `trace_id`)

### Step 4: Discover Endpoint Prefixes

For each module, find its route/endpoint configuration:
- Symfony: `Presentation/Resources/routes.yaml` or annotations/attributes on controllers
- Spring: `@RequestMapping` on controllers
- Rails: `config/routes.rb`
- Express/NestJS: route decorators or router files

Extract the URL prefix for each module.

### Step 5: Discover External Integrations

Search for external service client classes:
- Look for HTTP client wrappers, API clients, adapters
- Common patterns: `*Client.php`, `*Adapter.php`, `*Gateway.php`, `*Service.php` in Infrastructure layers
- Identify which external service each client talks to
- Note which log channels they use

---

## Phase 2: Present and Confirm

### Step 6: Present Findings

Show the user what was discovered:

```
=== Codebase Analysis Results ===

Language:      {language} ({version})
Framework:     {framework} ({version})
Logging:       {library} → {output format}
Tracing:       {correlation_id field} via {mechanism}
Module root:   {path}

Modules discovered ({count}):
  {ModuleName} — {brief description from directory/namespace analysis}
    Channels: [{channel_list}]
    Endpoints: [{prefix_list}]
  ...

External integrations ({count}):
  {IntegrationName} — {description}
    Clients: [{client_list}]
    Channels: [{channel_list}]
  ...

Logging channels ({count}):
  Module exceptions: [{list}]
  Framework exceptions: [{list}]
  Info/audit: [{list}]
  Integration clients: [{list}]
  Infrastructure: [{list}]
```

Ask: **"Does this look correct? Any corrections before I write it to config?"**

---

## Phase 3: Write Output

### Step 7: Write Codebase Profile

Write (or update) `{{WORKSPACE}}/data/codebase-profile.yaml`:

```yaml
# Codebase Profile — generated by /init-workspace
# Re-run /init-workspace to regenerate if codebase structure changes
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
    type: "{core|shared|domain}"

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

### Step 8: Update config.yaml

Update the auto-detected sections of `{{WORKSPACE}}/config.yaml`:

**a) `logging.channels`** — Populate all channel groups:
```yaml
logging:
  channels:
    module_exceptions:
      - {channel_name}
    framework_exceptions:
      - {channel_name}
    info:
      - {channel_name}
    integration_clients:
      - {channel_name}
    infrastructure:
      - {channel_name}
```

**b) `modules`** — Add an entry for each discovered module:
```yaml
modules:
  - name: "{ModuleName}"
    description: "{auto-generated description}"
    log_channels:
      - {channel_name}
    endpoint_prefixes:
      - "/{prefix}"
```

**c) `integrations`** — Add an entry for each external integration:
```yaml
integrations:
  - name: "{IntegrationName}"
    description: "{auto-generated description}"
    log_channels:
      - {channel_name}
    contact: "{team_placeholder}"
    clients:
      - "{ClientClassName} ({what it does})"
```

**Re-run handling**: If config.yaml already has populated modules/integrations (from a previous run), compare with newly discovered entries:
- New modules/integrations not in config → offer to append
- Existing entries in config but not found in codebase → warn but don't remove (user may have manually added them)
- Never overwrite manually edited entries

### Step 9: Run install-skills.sh

Now that config.yaml has all values, run install-skills.sh to compile skill templates:

```bash
bash {{TOOLKIT}}/scripts/setup/install-skills.sh
```

Verify no unresolved variables:
```bash
grep -r '{{' .claude/skills/*/SKILL.md
```

If any remain, report them and help the user fill in the missing config values.

---

## Phase 4: Report

### Step 10: Summary

```
=== Workspace Initialization Complete ===

Codebase: {language} / {framework}
Modules:  {count} detected
Channels: {count} detected
Integrations: {count} detected

Files written:
  - {{WORKSPACE}}/data/codebase-profile.yaml
  - {{WORKSPACE}}/config.yaml (auto-detected sections populated)
  - .claude/skills/ (skills compiled from templates)

Next steps:
  1. Review config.yaml — verify auto-detected modules and integrations
  2. Run /init-log-database to build the log type database
  3. Run /init-knowledge-center to build the issue knowledge center
```

---

## Important Rules

- **Never overwrite manual config fields** — only update the [AUTO] sections.
- **Never remove existing entries** from config.yaml — only add new ones.
- **Read source files to understand module purpose** — don't just list directory names.
- **Ask for confirmation** before writing to config.yaml.
- **Cross-reference logging configs** with actual source code — configs may declare channels that code doesn't use.
- **Framework detection matters** — the logging patterns, route discovery, and module structure all depend on the framework.
- **`codebase-profile.yaml` is shared** with `/init-log-database` — use the same format so that skill can skip its Phase 1.
