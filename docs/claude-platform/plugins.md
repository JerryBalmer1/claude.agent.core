---
verified: 2026-09-23
sources:
  - https://code.claude.com/docs/en/plugins.md
  - https://code.claude.com/docs/en/plugins-reference.md
  - https://code.claude.com/docs/en/plugin-evals.md
scope: What a Claude Code plugin is, what it can carry and where, how it is named, installed, cached, versioned, validated, and behavior-tested with `claude plugin eval`, as stated by the three pinned source pages.
---

# Plugins

A plugin is a self-contained directory that adds components to Claude Code: skills (and legacy
flat commands), agents, hooks, MCP servers, LSP servers, monitors, plus a few extra kinds (output
styles, themes, workflows, channels, `bin/` executables, default settings). Plugins are loaded per
session (`--plugin-dir`, `--plugin-url`), installed from a marketplace, discovered in a skills
directory, or synced from a claude.ai account. `claude plugin validate` checks files and schema;
`claude plugin eval` checks behavior by running scored prompt cases with and without the plugin.

Version-gated facts below carry the version the source names. Anything the three pages do not
state is listed under "Not found in source" at the end.

## Plugins vs standalone configuration

Source: https://code.claude.com/docs/en/plugins.md § "When to use plugins vs standalone configuration"; https://code.claude.com/docs/en/plugins.md § "What changes when migrating"

| Approach | Skill invocation | Suited to |
| --- | --- | --- |
| Standalone `.claude/` | `/hello` | personal or single-project config, experiments |
| Plugin | `/plugin-name:hello` | sharing, marketplaces, versioned releases, reuse |

- Migrating: hooks move from `settings.json` into `hooks/hooks.json` (same format).
- Project and user `.claude/agents/` definitions override same-named plugin agents, so remove the
  originals after migrating. Namespaced plugin skills do not override `/skill-name`; both stay.

## Directory layout

Source: https://code.claude.com/docs/en/plugins-reference.md § "Standard plugin layout"; https://code.claude.com/docs/en/plugins-reference.md § "File locations reference"; https://code.claude.com/docs/en/plugins.md § "Plugin structure overview"

Only `plugin.json` lives in `.claude-plugin/`. Every other component directory sits at the plugin
root. The plugin root is the plugin's own directory, never `~/.claude/`.

| Component | Default location | Notes |
| --- | --- | --- |
| Manifest | `.claude-plugin/plugin.json` | optional |
| Skills | `skills/<name>/SKILL.md` | or a single root `SKILL.md` |
| Commands | `commands/*.md` | flat-file skills; use `skills/` for new plugins |
| Agents | `agents/*.md` | subfolders become part of the agent name |
| Workflows | `workflows/` | workflow script files |
| Output styles | `output-styles/` | |
| Themes | `themes/` | experimental |
| Hooks | `hooks/hooks.json` | |
| MCP servers | `.mcp.json` | |
| LSP servers | `.lsp.json` | |
| Monitors | `monitors/monitors.json` | experimental |
| Executables | `bin/` | added to the Bash tool's `PATH` while enabled; not allowed in plugins distributed via claude.ai organization settings |
| Settings | `settings.json` | only `agent` and `subagentStatusLine` keys supported |

- A `CLAUDE.md` at the plugin root is not loaded as context. Ship instructions as a skill.
- Components misplaced inside `.claude-plugin/` load silently missing; `claude --debug` shows
  "loading plugin" messages to diagnose (§ "Directory structure mistakes").

## Manifest: plugin.json

Source: https://code.claude.com/docs/en/plugins-reference.md § "Plugin manifest schema"; https://code.claude.com/docs/en/plugins-reference.md § "Complete schema"; https://code.claude.com/docs/en/plugins-reference.md § "Required fields"

The manifest is optional. Without it, components are auto-discovered in default locations and the
plugin name comes from the directory name. With it, `name` is the only required field: kebab-case,
no spaces, control characters, or bidi-formatting characters. If a marketplace entry lists the
plugin under a different name, the marketplace entry name is what `enabledPlugins` and `/plugin` use.

### Metadata fields

Source: https://code.claude.com/docs/en/plugins-reference.md § "Metadata fields"; https://code.claude.com/docs/en/plugins-reference.md § "Default enablement"

| Field | Type | Meaning |
| --- | --- | --- |
| `$schema` | string | editor hint; ignored at load |
| `displayName` | string | UI label; marketplace entry's value wins; not used for lookup |
| `version` | string | semver; pins updates to bumps (see Versioning) |
| `description` | string | shown in the plugin manager |
| `author` | object | `name`, `email`, `url` |
| `homepage`, `repository`, `license` | string | informational |
| `keywords` | array | discovery tags |
| `metadata` | object | free-form; never read by Claude Code (key recognized since v2.1.222) |
| `defaultEnabled` | boolean | default `true`; `false` installs disabled |

`defaultEnabled` is only a fallback. A user's `enabledPlugins` entry at any scope, or a `true`
written because an active plugin depends on this one, takes precedence and persists across updates.
A marketplace entry's `defaultEnabled` overrides the manifest's.

### Component path fields

Source: https://code.claude.com/docs/en/plugins-reference.md § "Component path fields"; https://code.claude.com/docs/en/plugins-reference.md § "Path behavior rules"; https://code.claude.com/docs/en/plugins-reference.md § "Experimental components"

| Field | Type | Relation to default dir |
| --- | --- | --- |
| `skills` | string or array | adds to `skills/` (except a marketplace entry whose source is the marketplace root) |
| `commands` | string or array | replaces `commands/` |
| `agents` | string or array | replaces `agents/` |
| `workflows` | string or array | replaces `workflows/` |
| `outputStyles` | string or array | replaces `output-styles/` |
| `experimental.themes` | string or array | replaces `themes/` |
| `experimental.monitors` | string or array (or inline array) | replaces `monitors/monitors.json` |
| `experimental.evals` | string or array | eval dir when not `evals/`; `--eval-dir` overrides |
| `hooks` | string, array, or object | own merge rules |
| `mcpServers` | string, array, or object | own merge rules |
| `lspServers` | string, array, or object | own merge rules |
| `userConfig` | object | enable-time prompts |
| `channels` | array | message-injection channels bound to plugin MCP servers |
| `dependencies` | array | other plugins, optionally with semver constraints |

Path rules:

- Paths are relative to the plugin root and start with `./`; `skills` also accepts `"."`
  (accepted since v2.1.221; use `"./"` for older versions).
- To keep a replaced default and add more, list the default explicitly.
- A plugin with both a default folder and the matching manifest key gets a warning in
  `claude plugin list` and `/plugin`; manifest paths win. No warning if the key points into the
  default folder.
- `themes`/`monitors` at the top level still work, but `validate` warns and a future release will
  require `experimental.*`. Experimental schemas may change between releases.

### Unrecognized and mistyped fields

Source: https://code.claude.com/docs/en/plugins-reference.md § "Unrecognized fields"

- Unknown top-level fields are ignored at load, so one file can double as another ecosystem's
  manifest (VS Code/Cursor extension, npm `package.json`, MCPB/DXT).
- `validate` reports unknown fields as warnings, with a near-miss name suggestion.
- A recognized field with the wrong type is a load failure for most fields (for example a string
  `keywords`). For `experimental` and `metadata`, a non-object is ignored with a warning.

### User configuration

Source: https://code.claude.com/docs/en/plugins-reference.md § "User configuration"; https://code.claude.com/docs/en/plugins-reference.md § "Limit a field to fixed options"

`userConfig` declares values prompted for at enable time. Per key:

| Field | Required | Meaning |
| --- | --- | --- |
| `type` | yes | `string`, `number`, `boolean`, `directory`, `file` |
| `title`, `description` | yes | dialog label and help |
| `sensitive` | no | mask input; store in secure storage, not `settings.json` |
| `required` | no | empty fails validation |
| `default` | no | fallback value |
| `options` | no | fixed picker for `string` (v2.1.271+; older versions cannot load the plugin) |
| `multiple` | no | array of strings |
| `min` / `max` | no | bounds for `number` |

- Substitution: `${user_config.KEY}` in MCP and LSP configs and hook commands; non-sensitive values
  also in skill and agent content. Hook processes get every value as `CLAUDE_PLUGIN_OPTION_<KEY>`.
- Shell-run fields reject `${user_config.*}` (since v2.1.207): shell-form hook commands (use exec
  form with `args`, or the env var), monitor commands, and MCP `headersHelper` (read a config file).
- Non-sensitive values live at `pluginConfigs[<plugin-id>].options` in user `settings.json`.
  Sensitive values go to the macOS Keychain (about 2 KB total shared with OAuth tokens) or
  `~/.claude/.credentials.json`.
- `pluginConfigs` is read only from user settings, `--settings`/SDK inline, and managed settings
  (precedence managed > `--settings` > user). Project `.claude/settings.json` and
  `.claude/settings.local.json` entries are ignored (since v2.1.207) because a cloned repo could
  inject values. `enabledPlugins` still honors project and local settings.
- `channels[]` entries need `server` matching a key in the plugin's `mcpServers`, and may carry
  their own `userConfig` (same schema) (§ "Channels").
- `options` rules: `type: string`; no `multiple`/`sensitive`; `default` must be an option, or set
  `required: true`; 1 to 64 chars each; no leading/trailing space, control, invisible, or
  direction-changing characters; no duplicates ignoring case. Breaking one fails the load.

## Components

Source: https://code.claude.com/docs/en/plugins-reference.md § "Plugin components reference"

### Skills and commands

Source: https://code.claude.com/docs/en/plugins-reference.md § "Skills"; https://code.claude.com/docs/en/plugins.md § "Add Skills to your plugin"

- `skills/<name>/SKILL.md` directories, or flat `.md` files in `commands/`; auto-discovered on install.
- Single-skill plugin: root `SKILL.md`, no `skills/` dir, no `skills` field. Set frontmatter `name`,
  otherwise the name falls back to the install directory, which for a cached copy is a version
  string that changes every update.
- Boolean frontmatter (for example `disable-model-invocation`) accepts `yes/no/on/off/1/0` in any
  case since v2.1.218.
- `SKILL.md` edits in a skills-directory plugin apply immediately; other components need
  `/reload-plugins`.

### Agents

Source: https://code.claude.com/docs/en/plugins-reference.md § "Agents"; https://code.claude.com/docs/en/plugins-reference.md § "Plugin agent frontmatter"

| Frontmatter status | Fields |
| --- | --- |
| Honored | `name`, `description`, `model`, `effort`, `maxTurns`, `tools`, `disallowedTools`, `skills`, `memory`, `background`, `omitClaudeMd`, `isolation` (only `"worktree"`), `color`, `experimental` |
| Ignored for security | `hooks`, `mcpServers`, `permissionMode` |
| Not supported | `initialPrompt` |

- Naming: plugin name, subfolders, and file name joined by colons
  (`agents/review/security.md` in `my-plugin` is `my-plugin:review:security`). Frontmatter `name`
  replaces only the file-name part. A file listed in the manifest `agents` field drops subfolders.
- A plugin agent with no `name` or unparseable frontmatter still loads, named after the file (the
  unparseable case gets a stock description and all fields ignored). Project, user, and managed
  agent files in that state are skipped instead.
- Find unparseable agent files with `claude plugin validate ./my-plugin`, or
  `claude plugin validate ./my-plugin/agents` for a manifest-less plugin (v2.1.233+).

### Hooks

Source: https://code.claude.com/docs/en/plugins-reference.md § "Hooks"; https://code.claude.com/docs/en/plugins-reference.md § "Hook troubleshooting"

- Location: `hooks/hooks.json`, or inline in `plugin.json`. A top-level `$schema` key is ignored.
- Same lifecycle events as user hooks. The source lists: `SessionStart`, `Setup`,
  `UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PermissionRequest`,
  `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Notification`,
  `MessageDisplay`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`,
  `StopFailure`, `TeammateIdle`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`,
  `DirectoryAdded`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`,
  `PostCompact`, `PreModelSwitch`, `PostModelSwitch`, `Elicitation`, `ElicitationResult`,
  `SessionEnd`. Event names are case-sensitive.
- Hook types: `command`, `http`, `mcp_tool`, `prompt`, `agent`.
- Hooks that target the plugin's own MCP server must use scoped names: matchers and `if` take
  `mcp__plugin_<plugin-name>_<server-name>__<tool>`; an `mcp_tool` hook's `server` takes
  `plugin:<plugin-name>:<server-name>`. A bare server key never fires.

### MCP servers

Source: https://code.claude.com/docs/en/plugins-reference.md § "MCP servers"

- Location: `.mcp.json` or inline `mcpServers`. Standard MCP config.
- Start automatically when the plugin is enabled; appear as ordinary MCP tools; configured
  independently of user MCP servers. `/reload-plugins` keeps live connections whose config is
  unchanged.

### LSP servers

Source: https://code.claude.com/docs/en/plugins-reference.md § "LSP servers"

- Location: `.lsp.json` or inline `lspServers`, keyed by server name.
- Required: `command` (on PATH), `extensionToLanguage`. Optional: `args`, `transport`
  (`stdio` default; `socket` accepted but everything runs over stdio), `env`,
  `initializationOptions`, `settings`, `workspaceFolder`, `startupTimeout`, `shutdownTimeout`,
  `restartOnCrash` (default `true`), `maxRestarts`, `diagnostics` (default `true`).
- `restartOnCrash`/`shutdownTimeout` need v2.1.205+; earlier, setting either silently skipped the server.
- Same extension claimed twice: the first registered server wins, others never start. Invalid
  configs are skipped and do not claim extensions.
- Stdout is protocol only (headers up to 64 KiB, body up to 32 MiB); violations disconnect and
  count as a crash. Log to stderr.
- The language server binary is installed separately; official LSP plugins include
  `pyright-lsp`, `typescript-lsp`, `rust-analyzer-lsp`.

### Monitors

Source: https://code.claude.com/docs/en/plugins-reference.md § "Monitors"; https://code.claude.com/docs/en/plugins.md § "Add background monitors to your plugin"

- A monitor runs a shell command for the session's lifetime; each stdout line reaches Claude as a
  notification. Experimental.
- Location: `monitors/monitors.json` (JSON array) or `experimental.monitors` (inline array or path).
- Required: `name` (unique in plugin), `command`, `description`. Optional `when`: `"always"`
  (default) or `"on-skill-invoke:<skill-name>"`.
- Runs only in interactive CLI sessions, unsandboxed, at hook trust level; skipped where the
  Monitor tool is unavailable.
- `command` supports `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`, `${CLAUDE_PROJECT_DIR}`, and
  environment variables; not `${user_config.*}`, and no `CLAUDE_PLUGIN_OPTION_*` env vars.
- Disabling a plugin mid-session does not stop running monitors; they end with the session.

### Themes, output styles, settings, bin

Source: https://code.claude.com/docs/en/plugins-reference.md § "Themes"; https://code.claude.com/docs/en/plugins.md § "Ship default settings with your plugin"

- Theme: JSON in `themes/` with `name`, `base` preset, sparse `overrides` of color tokens. Saved in
  user config as `custom:<plugin-name>:<slug>`; read-only (Ctrl+E in `/theme` copies it to
  `~/.claude/themes/`).
- Output styles: files in `output-styles/`; `plugin init --with output-style` scaffolds one that
  applies automatically while the plugin is enabled (§ "plugin init").
- `settings.json`: only `agent` (makes a plugin agent the main thread) and `subagentStatusLine`.
  It takes priority over `settings` declared in `plugin.json`; unknown keys are silently ignored.

## Path variables and the data directory

Source: https://code.claude.com/docs/en/plugins-reference.md § "Environment variables"; https://code.claude.com/docs/en/plugins-reference.md § "Persistent data directory"

| Variable | Resolves to | Use for |
| --- | --- | --- |
| `${CLAUDE_PLUGIN_ROOT}` | plugin install directory | bundled scripts, binaries, config |
| `${CLAUDE_PLUGIN_DATA}` | `~/.claude/plugins/data/{id}/`, created on first reference | deps, generated code, caches |
| `${CLAUDE_PROJECT_DIR}` | project root | project-local scripts |

- Exported to hook processes and MCP/LSP subprocesses. Not present in the Bash tool environment
  (main session or subagent); in plugin content write the placeholder and it is substituted inline.
- Inline substitution: anywhere in skill/agent content and hook/monitor commands; MCP stdio
  `command`/`args`/`env`; MCP http/sse/ws `url`/`headers`/`headersHelper`; LSP
  `command`/`args`/`env`/`workspaceFolder`.
- Shell form: wrap in double quotes. Exec form with `args` avoids quoting.
- `{id}` replaces chars outside `[A-Za-z0-9_-]` with `-` (`formatter@my-marketplace` becomes
  `formatter-my-marketplace`).
- For a copied plugin, `CLAUDE_PLUGIN_ROOT` changes on update; do not write state there. After a
  mid-session update, `/reload-plugins` moves hooks, MCP, and LSP to the new path; monitors need a
  restart; non-interactive sessions keep MCP on the old path until next session.
- The data dir survives updates; compare the bundled dependency manifest to a copy in the data dir
  to know when to reinstall. It is deleted when uninstalled from the last scope (CLI default;
  `--keep-data` preserves it; `/plugin` prompts first).

## Namespacing

Source: https://code.claude.com/docs/en/plugins.md § "Create your first plugin"; https://code.claude.com/docs/en/plugins-reference.md § "Required fields"

- Plugin skills are always namespaced `/<plugin-name>:<skill>`; the prefix is the manifest `name`.
- Agents appear as `<plugin>:<name>` (with subfolder segments) in @-mention typeahead.
- Plugin MCP tools are `mcp__plugin_<plugin>_<server>__<tool>`.
- Plugin identities by source: `name@marketplace`, `name@skills-dir`, `name@synced`; `--plugin-dir`
  plugins use `@inline` (§ "Plugins synced from claude.ai").

## Ways a plugin gets loaded

Source: https://code.claude.com/docs/en/plugins-reference.md § "Plugin caching and file resolution"; https://code.claude.com/docs/en/plugins.md § "Test your plugins locally"

- `claude --plugin-dir <dir|.zip>` for one session; repeatable. A folder with no top-level
  manifest/components is treated as a folder of plugins (v2.1.265+): each subfolder with
  `.claude-plugin/plugin.json` loads; others are skipped silently. Interactive sessions watch it.
- A `--plugin-dir` plugin overrides a same-named installed plugin for the session, except plugins
  managed settings force-enable or force-disable.
- `CLAUDE_CODE_PLUGIN_DIRS` env var (absolute paths, v2.1.280+) loads like `--plugin-dir`; project
  and local settings cannot set it.
- `claude --plugin-url <zip-url>` fetches at startup for that session; failures become a load error
  in the `/plugin` Errors tab.
- `/reload-plugins` reloads plugins, skills, agents, hooks, plugin MCP and LSP servers.

### Skills-directory plugins

Source: https://code.claude.com/docs/en/plugins-reference.md § "Skills-directory plugins"; https://code.claude.com/docs/en/plugins-reference.md § "Choose where the plugin loads from"; https://code.claude.com/docs/en/plugins-reference.md § "Edit, reload, and disable a skills-directory plugin"

- Any folder under a skills directory containing `.claude-plugin/plugin.json` loads as
  `<name>@skills-dir`, in place, no install.
- `~/.claude/skills/` is personal scope, unrestricted. `<cwd>/.claude/skills/` is project scope and
  loads only after the workspace trust dialog (trusting a parent or `-p` is not enough); its MCP
  servers need per-server approval, LSP starts only after trust, and monitors do not load.
- Project-scope ones load only from the primary working directory; they do not walk up to the repo root.
- Remove by deleting the folder or `claude plugin disable <name>@skills-dir`; no uninstall step.

### Plugins synced from claude.ai

Source: https://code.claude.com/docs/en/plugins-reference.md § "Plugins synced from claude.ai"

- Account- and org-enabled plugins download to `~/.claude/plugins/synced/` and load as
  `<name>@synced`, with marketplace-level trust. Terminal sync needs v2.1.273+.
- Disable per user with `claude plugin disable <name>@synced` (saved as `false` in user
  `enabledPlugins`), or per project via committed `.claude/settings.json`. `install`/`update`/
  `uninstall` do not apply. `syncClaudeAiPlugins: false` stops syncing.
- Org-required synced plugins cannot be disabled; `disable` refuses.
- Any same-named plugin from another source wins over the synced copy (since v2.1.239).

## Installation scopes and enablement

Source: https://code.claude.com/docs/en/plugins-reference.md § "Plugin installation scopes"

| Scope | Settings file | Use |
| --- | --- | --- |
| `user` (default) | `~/.claude/settings.json` | personal, all projects |
| `project` | `.claude/settings.json` | team, via version control |
| `local` | `.claude/settings.local.json` | project-specific, gitignored |
| `managed` | managed settings | read-only, update only |

Installing writes to `enabledPlugins` in the chosen scope's file.

## Marketplaces

Source: https://code.claude.com/docs/en/plugins.md § "Share your plugins"; https://code.claude.com/docs/en/plugins.md § "Submit your plugin to the community marketplace"; https://code.claude.com/docs/en/plugins-reference.md § "Example error messages"

These pages cover marketplaces only in passing (details live in a separate marketplaces page not in
this reference's sources). What they do state:

- A marketplace entry lives in `marketplace.json`; its `source` locates the plugin. Source kinds
  named: `github`, `url`, `git-subdir`, relative path, `archive` (zip, optional `sha256` pin),
  `npm`, and `command` (copy mode or link mode).
- Conflicting component definitions in both `plugin.json` and a marketplace entry is an error;
  resolve by removing duplicates or removing `strict: false` from the entry.
- `claude-plugins-official`: Anthropic-curated, auto-registered on first interactive start;
  otherwise `claude plugin marketplace add anthropics/claude-plugins-official`. No application process.
- `claude-community`: add with `/plugin marketplace add anthropics/claude-plugins-community`;
  install as `@claude-community`. Submissions via claude.ai (Team/Enterprise with directory access)
  or Console forms; review runs `validate` plus automated safety screening. Approved plugins are
  pinned to a commit SHA; CI bumps the pin; catalog syncs nightly.
- Admins can block the skills-dir source with `strictKnownMarketplaces` or
  `{"source": "skills-dir"}` in `blockedMarketplaces` (§ "plugin init").

## CLI commands

Source: https://code.claude.com/docs/en/plugins-reference.md § "CLI commands reference"

| Command | Purpose | Key flags |
| --- | --- | --- |
| `plugin init <name>` (alias `new`) | scaffold `~/.claude/skills/<name>/` | `--description`, `--author`, `--author-email`, `--with skills agents hooks mcp lsp output-style channel`, `-f/--force` |
| `plugin install <plugin>` | install from marketplace | `-s/--scope user\|project\|local`, `--config key=value`, `-y/--yes`, `--accept-command <sha256>`, `--json` |
| `plugin uninstall` (aliases `remove`, `rm`) | remove | `-s`, `--keep-data`, `--prune`, `-y`, `--json` (not with `--prune`) |
| `plugin prune` (alias `autoremove`) | drop orphaned auto-installed deps | `-s`, `--dry-run`, `-y` |
| `plugin enable <plugin>` | enable; enables deps transitively | `-s` (auto-detect), `--json` |
| `plugin disable [plugin]` | disable; fails if an enabled plugin depends on it | `-a/--all`, `-s`, `--json` |
| `plugin update <plugin>` | update to latest | `-s user\|project\|local\|managed`, `-y`, `--accept-command`, `--json` |
| `plugin list` | installed plugins | `--json` (with `errors`/`notes`, and `errorDetails`/`noteDetails` v2.1.268+), `--available` (needs `--json`) |
| `plugin details <name>` | component inventory and token cost | |
| `plugin validate <path>` | schema check | `--strict`, `--json` |
| `plugin eval [target]` | behavior evals | see below |
| `plugin eval init [name]` | create eval suite | `--bare`, `-i`, `--eval-dir` |
| `plugin tag [path]` | release git tag | `--push`, `--dry-run`, `-f`, `-m`, `--remote` (default `origin`) |

- `--json` on install/uninstall/enable/disable/update (v2.1.268+): last stdout line is one object
  with `command`, `outcome` (`ok`/`failed`), `message`, plus `pluginId`, `scope`, `failureCode`
  when relevant. A usage error prints no result line and exits 1.
- Marketplace-declared commands (`command` sources, archive `headersHelper`) require `-y` or
  `--accept-command <sha256>` when not on a TTY; the sha256 comes from `shownCommand` in a prior
  `--json` result and binds to that exact command, plugin, and catalog. Neither works inside a
  Claude Code session.
- `plugin details`: always-on tokens (listing text) and per-component on-invoke tokens, via the
  `count_tokens` API, falling back to a character estimate.

### plugin validate

Source: https://code.claude.com/docs/en/plugins-reference.md § "plugin validate"; https://code.claude.com/docs/en/plugins-reference.md § "Common issues"

- Checks a plugin or marketplace directory: `plugin.json`, `hooks/hooks.json`, and frontmatter of
  skills, agents, and commands in default directories.
- Exit codes: `0` pass, `1` fail, `2` the run itself failed (for example unreadable path; nothing
  on stdout, message on stderr).
- `--strict` turns warnings into errors (exit 1). `--json` (v2.1.259+) emits `success`, `strict`,
  `target`, `manifest` (or `null` without a manifest), `contents[]` with `file`, `errors`,
  `warnings`, `notes`.
- Human output: `✔ Validation passed` or `✔ Validation passed with warnings`
  (§ "Submit your plugin to the community marketplace"). `/plugin validate <path>` runs inline.

## Caching, dependencies, and updates

Source: https://code.claude.com/docs/en/plugins-reference.md § "Plugin caching and file resolution"; https://code.claude.com/docs/en/plugins-reference.md § "Node.js package dependencies"

- Marketplace plugins are copied to `~/.claude/plugins/cache` for security and verification,
  except `command` sources in link mode and relative-path sources in a local-directory marketplace,
  which load in place (edits apply at next session or `/reload-plugins`, no version bump).
- Each copied version is its own cache directory. On update or uninstall the old one is marked
  orphaned and swept about 14 days later (only while some plugin is installed). Glob and Grep skip
  orphaned dirs. Symlinked checkouts in the cache are never removed.
- Node deps: when a copy is made and root has `package.json` plus a lockfile, Claude Code runs
  `bun install --frozen-lockfile --ignore-scripts` (for `bun.lock`/`bun.lockb`) or
  `npm ci --ignore-scripts` (for `npm-shrinkwrap.json`/`package-lock.json`), first match in that
  order, 60-second timeout. Yarn/pnpm-only or `bunfig.toml` present means skipped. Failures never
  block the plugin; they log a debug warning. Cannot be disabled.

### Versioning

Source: https://code.claude.com/docs/en/plugins-reference.md § "Version management"

The resolved version is the cache key; an update is skipped when it equals the installed version.
Resolution order (all sources except `command`):

1. `version` in `plugin.json`
2. `version` in the marketplace entry
3. git commit SHA (`github`, `url`, `git-subdir`, relative path in a git-hosted marketplace)
4. first 12 chars of SHA-256 (`archive`: the `sha256` pin, else the downloaded file's digest)
5. `unknown` (`npm`, or local dirs with no git repo; an enclosing repo is not used)

`command` sources always use a 12-char content hash, or `<version>-<hash>`; the marketplace
`version` is ignored. Strategies: explicit version (updates only on bump; "already at the latest
version" otherwise), commit-SHA (omit `version` everywhere), digest (archive source). Semver and a
`CHANGELOG.md` are recommended.

## Security and trust notes

Source: https://code.claude.com/docs/en/plugins-reference.md § "Path traversal limitations"; https://code.claude.com/docs/en/plugins-reference.md § "Share files within a marketplace with symlinks"; https://code.claude.com/docs/en/plugins-reference.md § "Plugin agent frontmatter"

- Component paths resolving outside the plugin root are rejected (`path escapes plugin directory`)
  and that component is dropped. Backslash paths are rejected on macOS/Linux.
- Files outside the plugin are not copied into the cache. Symlinks: inside plugin kept; elsewhere
  in the same marketplace dereferenced; outside the marketplace skipped. For `--plugin-dir`, local
  path, or `command` copy mode, only in-plugin symlinks survive.
- Plugin agents cannot set `hooks`, `mcpServers`, or `permissionMode`.
- Project-scope skills-dir plugins are trust-gated; `pluginConfigs` from project files is ignored;
  `${user_config.*}` is rejected in shell-run fields (see above).
- Monitors and hooks run unsandboxed at the same trust level.
- `--plugin-url`: only point at archives you control or trust.

## Plugin evals: claude plugin eval

Source: https://code.claude.com/docs/en/plugin-evals.md § "How an eval run works"; https://code.claude.com/docs/en/plugin-evals.md § "Requirements"

An eval suite is a directory (default `evals/` in the plugin) of cases. Each case is a realistic
prompt plus graders (pass/fail checks). Each run of a case is a fresh isolated non-interactive
session with only the plugin loaded. Requirements: v2.1.269+, a plugin with a manifest (or a
skills-dir plugin), and normal credentials. This format is distinct from skill-creator's
`evals/evals.json`. `validate` checks files; `eval` checks behavior.

### Scoring and the with/without comparison

Source: https://code.claude.com/docs/en/plugin-evals.md § "How a case is scored"; https://code.claude.com/docs/en/plugin-evals.md § "Score against the no-plugin baseline"

- Run score = fraction of graders passed (weighted). Case score = mean over runs (default 3 per arm).
  A case passes when its with-arm score meets `--threshold` (default `1.0`).
- By default each case also runs without the plugin. Summary columns `WITH`, `W/OUT`, `Δ`
  (with minus without). `--ablation none` runs one arm (columns become `SCORE`, `PASS%`) and halves cost.
- In two-arm runs, `tool_used` graders with `tool: Skill` and graders marked `arm: with-only` are
  excluded from both arms' scores (`scored: false`) and shown as indicators, unless every grader in
  the case is such a grader. `arm: both` forces scoring. `--ablation none` excludes nothing, so
  absolute scores differ between modes.

### Case files

Source: https://code.claude.com/docs/en/plugin-evals.md § "Eval suite reference"; https://code.claude.com/docs/en/plugin-evals.md § "prompt.md frontmatter"; https://code.claude.com/docs/en/plugin-evals.md § "case.yaml fields"

A case is a directory with `prompt.md`, `case.yaml`, or both. Nest cases under a non-case dir to
group them. `graders/<name>.md` holds one grader each. `results/` is written per run (gitignore it).

`prompt.md` frontmatter (unknown keys are errors): `schema_version` (`"1.1"`, auto), `name`
(default dir name), `description`, `tags`, `plugins` (default nearest enclosing plugin; e.g.
`["../.."]`), `runs` (3; 1 to 50), `expected_outcome`, `model`, `max_turns` (10; max 200),
`timeout_seconds` (300; max 3600), `allowed_tools` (`[]`), `append_system_prompt`, `env` (keys
must match `EVAL_[A-Z0-9_]*`). The body is the prompt verbatim; `@path` is not expanded.

`case.yaml` requires `schema_version: "1.1"` and `name`; execution fields go under `execution:`.
Only in `case.yaml`: `context.scaffold_script` (Bash, runs as you outside the sandbox, only with
`--scaffold`), `context.history_file` (`.jsonl` to resume), `context.add_dirs` (read-only),
`execution.prompt`, `graders` list. `prompt.md` frontmatter overrides matching `case.yaml` fields.

### Graders

Source: https://code.claude.com/docs/en/plugin-evals.md § "Grader frontmatter"; https://code.claude.com/docs/en/plugin-evals.md § "Grader types"; https://code.claude.com/docs/en/plugin-evals.md § "What a grader can look at"; https://code.claude.com/docs/en/plugin-evals.md § "Choose and weight graders"

Common keys: `type` (required), `weight` (default 1), `arm` (`with-only` or `both`). There are no
custom-code graders.

| Type | Options | Passes when | Cost |
| --- | --- | --- | --- |
| `regex` | `pattern`, `flags`, `match` (`not_contains`, `count:N`), `target` | JS regex found | free |
| `tool_used` | `tool`, `input_match`, `min` (1), `max` | matching call count in range; `min: 0, max: 0` means never called | free |
| `tool_order` | `before`, `after` | both called; first `before` precedes first `after` | free |
| `file_exists` | `path` glob, `exists` | a file created during the run matches | free |
| `llm` | `criteria` (file body), `focus` | judge votes PASS in 2 of 3 | judge calls |
| `baseline` | `baseline_file`, `criteria` | judge rates run at least as good as a reference `.jsonl` | judge calls |

`target`/`focus` values: `last_message` (default), `trace` (JSON per line; `llm` sees first 12 and
last 12 messages; quotes appear as `\"`), `files` (created paths only), `{ source: file, path }`
(file contents; images shown to judges, other binaries refused), `mock_calls`.

### Mocks and fixtures

Source: https://code.claude.com/docs/en/plugin-evals.md § "Mock MCP servers"; https://code.claude.com/docs/en/plugin-evals.md § "Mock files"; https://code.claude.com/docs/en/plugin-evals.md § "Replay agent mock answers"

- Real plugin MCP servers never start by default. `mocks/<server>/<tool>.md` (suite-wide or
  per case) answers a tool; unmocked tools are unavailable.
- Mock keys: `type` (`fixed` or `agent`), `expect` (input guard; violation aborts the run with
  score 0), `error`, `abort_when`. Also `_server.md` and `_tools.json`. Substitutions
  `{{input.<field>}}`, `{{file:fixtures/...}}`.
- Agent-mock answers from clean runs are saved in `mock-recordings/` with `ADOPT.txt`; copy into
  `mocks/.replay/<server>/` and commit for repeatable CI.
- `--allow-real-servers` starts real servers for unmocked ones; `--mocks off` starts all.

### Sandbox, isolation, and trust

Source: https://code.claude.com/docs/en/plugin-evals.md § "Grant tools"; https://code.claude.com/docs/en/plugin-evals.md § "How runs are isolated"; https://code.claude.com/docs/en/plugin-evals.md § "Trust the plugin directory"; https://code.claude.com/docs/en/plugin-evals.md § "What a run can access"

- Runs never prompt. Default allowlist: read-only tools listed in `allowed_tools` from `Read`,
  `Glob`, `Grep`, `NotebookRead`, `Skill`, `Agent`, `TodoWrite`, `TaskCreate`, `TaskGet`,
  `TaskList`, `TaskUpdate`, `TaskStop`. Ungranted `Bash`, `Write`, `Edit`, `WebFetch`,
  `WebSearch` are removed entirely. `--allow-tools` applies to every case; ungranted requests are
  listed on stderr as `not granted`.
- Granting Bash runs commands under the OS sandbox: writes confined to the workspace, home and
  config unreadable, network only to `WebFetch(domain:...)` grants. No sandbox backend means each
  run is refused. Native Windows has none (use WSL2); Linux needs `bubblewrap` and `socat`.
- Each run: throwaway home, cwd, and config; `claude -p` child with only the plugin. No user
  settings, hooks, `CLAUDE.md`, MCP servers, other plugins, memory, skills, or project `.claude/`
  or `.mcp.json`. Env is an allowlist plus `EVAL_*`. Managed settings still apply. Artifact tool is
  off. The eval directory is hidden from the agent.
- Trust: first run on a directory asks `Trust this plugin directory?`; in git, yes trusts the whole
  repo. Non-TTY or `--json` without `--trust-plugin` exits 1. Named targets skip the prompt.
- Isolation limits the agent, not the plugin's own code; a passing suite says nothing about plugin
  safety. With third-party hooks or real MCP servers, treat scores as advisory unless run in a
  container or CI runner.

### Command options and targets

Source: https://code.claude.com/docs/en/plugin-evals.md § "Command options"; https://code.claude.com/docs/en/plugin-evals.md § "Choose what to evaluate"; https://code.claude.com/docs/en/plugins-reference.md § "plugin eval"

Target: plugin dir (default `.`), a single `prompt.md`/`case.yaml`, installed `name` or
`name@marketplace`, or `name@skills-dir`. Put the target before `--tag`, `--allow-tools`, `--json`.

| Option | Default | Effect |
| --- | --- | --- |
| `--runs <n>` | case `runs`, else 3 | runs per case per arm |
| `-j, --concurrency <n>` | 1 | 1 to 8, shared rate limit |
| `--model` | case `model`, else `ANTHROPIC_MODEL`, else default | agent under test |
| `--judge-model` | small fast model | `llm`/`baseline` judge |
| `--ablation none\|with-without` | with-without if a plugin resolves | baseline arm |
| `--threshold <0..1>` | 1.0 | with-arm score floor per case |
| `--max-cost-usd` | none | list-price ceiling checked before each run; exit 2 if runs left unstarted |
| `--allow-tools <tools...>` | none | extra tool grants |
| `--scaffold` / `--no-scaffold` | off | run `scaffold_script` |
| `--trust-plugin` | off | skip trust prompt |
| `--mocks record\|off` | record | mock handling |
| `--allow-real-servers` | off | start unmocked real servers |
| `--json [path]` | off | result doc to stdout or a `.json` path; quiet |
| `--output-dir` | `<eval dir>/results/<timestamp>/` | report location |
| `--no-publish` / `--publish-report` | | keep local / force publish |
| `--eval-dir`, `--case <glob>`, `--tag`, `--keep-temp`, `--report`, `--verbose` | | filters, debugging |

### Exit codes and CI

Source: https://code.claude.com/docs/en/plugin-evals.md § "Run evals in CI"; https://code.claude.com/docs/en/plugin-evals.md § "The run exits 1 but the results look fine"

| Exit | Meaning |
| --- | --- |
| 0 | every case at or above threshold, every case file loaded |
| 1 | a case below threshold, load failure, no cases, run could not start, untrusted dir without `--trust-plugin`, or invalid option |
| 2 | partial: cost ceiling hit, or credential rejected at or before first run (`partial: true` still written) |
| 130 | interrupted (partial results written) |
| 143 | terminated, e.g. CI timeout |

- Recommended CI shape: `--trust-plugin --json results.json --threshold <x> --model <pinned>
  --judge-model <pinned> --no-publish --max-cost-usd <n>`.
- Report write/publish problems never change the exit code.
- CI needs Claude Code and credentials such as `ANTHROPIC_API_KEY`. `eval init` needs a TTY; use
  `--bare <name>` in CI.

### Results: JSON and HTML

Source: https://code.claude.com/docs/en/plugin-evals.md § "JSON result"; https://code.claude.com/docs/en/plugin-evals.md § "HTML report"; https://code.claude.com/docs/en/plugin-evals.md § "Read the results"

- `results/<timestamp>/aggregate-result.json` and `report.html` per run. JSON is `schemaVersion: 1`,
  camelCase, additive; ignore unknown fields.
- Key fields: `partial`/`partialReason` (`cost_ceiling`, `interrupted`, `auth_failed`),
  `aggregates.overallScore`, `aggregates.casesPassed`/`casesTotal`, `aggregates.meanDelta`,
  `cases[].name`, `cases[].aggregates.score`/`delta`, `cases[].arms.with[].error`/`aborted`/
  `skippedPaidGraders`, `costUsd`, `durationSeconds`, `claudeVersion`.
- A non-null `error` does not imply score 0; an `aborted` run scores 0 with `error: null`.
- HTML is self-contained, no external requests. Published as a private artifact when signed in with
  a claude.ai subscription and artifacts are available; runs started from a Claude Code session stay local.

### Cost

Source: https://code.claude.com/docs/en/plugin-evals.md § "How a case is scored"; https://code.claude.com/docs/en/plugin-evals.md § "Runs fail with a usage-limit or rate-limit error partway through"

- Every run and judge call is a real model call on your plan or API bill; reported cost is a
  list-price estimate.
- Roughly cases x runs agent runs per arm, plus three judge calls per `llm`/`baseline` grader per run.
- Cheap suites: judge-free graders, `--ablation none`, excluding `partial` and `skippedPaidGraders`
  results from trends.
- Hitting a usage or rate limit mid-suite does not mark it `partial`; later runs usually score 0
  and look like regressions. Check `NOTES` or `error` first.

## Not found in source

Source: https://code.claude.com/docs/en/plugins.md § "Create plugins"; https://code.claude.com/docs/en/plugins-reference.md § "Plugins reference"; https://code.claude.com/docs/en/plugin-evals.md § "Test plugins with evals"

Expected for this topic but not stated in the three pinned pages:

- The `marketplace.json` schema itself (top-level fields, owner, plugin entry fields, `strict`
  semantics beyond the one error message).
- The full `claude plugin marketplace` subcommand set (`add` is mentioned once; `list`, `remove`,
  `update` are not documented here).
- Auto-update configuration and how often auto-update fires.
- Plugin signing, checksums for non-archive sources, or any publisher verification mechanism.
- Hook merge rules across `hooks/hooks.json` and inline manifest hooks (deferred to other sections/pages).
- Details of `dependencies` resolution and `plugin tag` naming (deferred to a dependencies page).
- The full `claude plugin eval --help` text; `--report` and `--verbose` are named but not described.
- Any custom-code grader or programmatic grader hook for evals (source says none exist).
- Whether `plugin eval` can load project `CLAUDE.md` or `.claude/settings.json` rules into a run
  (source says project-level config does not load).
