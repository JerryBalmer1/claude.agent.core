---
verified: 2026-09-23
sources:
  - https://code.claude.com/docs/en/settings.md
  - https://code.claude.com/docs/en/settings-reference.md
scope: Claude Code settings files, their scopes, precedence and merge rules, reload behavior, and every settings key that governs hooks, skills, plugins, marketplaces, and permissions.
---

# Settings

Claude Code behavior is driven by JSON keys read from a small set of settings files plus
organization-deployed managed sources. This file summarizes where those files live, which one wins
when a key appears in several, how lists merge, when edits reach a running session, how to confirm
what loaded, and the keys that control the extension surface (hooks, skills, plugins, marketplaces,
permissions). MCP, model, sandbox-network, UI, and authentication keys exist in the reference but
are only touched here where they bear on the extension surface.

Conventions used below:

- "Any file" means user, project, local, and managed. Other scope labels are copied from the
  reference index: `User, local, or managed`, `User or managed`, `Managed`, `Global config`.
- "unset" is the documented default when the source says the key has no value by default.

## Scopes and files

Source: https://code.claude.com/docs/en/settings.md § "Settings files and who they affect"; https://code.claude.com/docs/en/settings.md § "Compare the scope of each settings file"

| Scope | File | Who it reaches |
| :-- | :-- | :-- |
| User | `~/.claude/settings.json` | You, every project on this machine |
| Shared project | `.claude/settings.json` (in the project) | Everyone who has the folder; commit it to share |
| Project local | `.claude/settings.local.json` (in the project) | You, this project only; kept out of git |
| Managed | `managed-settings.json`, MDM/OS policy, server-managed settings from the claude.ai console, or an embedding host | Everyone the organization deploys to; overrides everything except a few listed exceptions |

- A fifth file, `~/.claude.json`, is written by Claude Code itself. It holds sign-in state, MCP
  server configs, per-project state such as trust decisions, and the `Global config` keys. Global
  config keys are ignored in any other file.
- The shared project file only reaches teammates and cloud sessions once committed.
- Managed settings reach every project on every deployed machine. Only server-managed settings
  reach cloud sessions.

### Per-OS locations

Source: https://code.claude.com/docs/en/settings.md § "Find or create your settings files"; https://code.claude.com/docs/en/settings-reference.md § "`wslInheritsWindowsSettings`"; https://code.claude.com/docs/en/settings-reference.md § "`policyHelper`"

| Item | Windows | macOS | Linux / WSL |
| :-- | :-- | :-- | :-- |
| User home dir `~/.claude` | `%USERPROFILE%\.claude` | `~/.claude` | `~/.claude` |
| Override of home-dir location | `CLAUDE_CONFIG_DIR` env var (settings, session history, plugins move there) | same | same |
| Project files | `<project>\.claude\settings.json`, `settings.local.json` | `<project>/.claude/...` | `<project>/.claude/...` |
| Managed settings file / drop-ins | under `C:\Program Files\ClaudeCode\` (admin-write) | not stated in source | `/etc/claude-code` (named for WSL) |
| OS policy store | HKLM registry (admin); HKCU registry (user-writable, weaker) | plist (MDM) | not stated in source |
| Server-managed | fetched from claude.ai admin console or a self-hosted Claude apps gateway | same | same |

Notes drawn from the sources:

- Settings files are not created on install. Claude Code creates `~/.claude/settings.json` when you
  change a `/config` option stored at user scope, and `.claude/settings.local.json` the first time
  you give a standing permission approval ("Yes, and don't ask again").
- On WSL, `wslInheritsWindowsSettings: true` (set only in HKLM or a managed file/drop-in under
  `C:\Program Files\ClaudeCode\`) makes WSL read the Windows policy chain, with HKLM and the Windows
  managed file above `/etc/claude-code` and HKCU. Default `false`: WSL reads only `/etc/claude-code`.
- Several managed-only keys (for example `policyHelper`, `forceLoginGatewayUrl`) are read only from
  "the macOS plist, the Windows HKLM registry, or the managed settings file" and are ignored in HKCU
  and server-managed settings. HKCU is described as the user-writable registry.

### Where the local file lives in a git repository

Source: https://code.claude.com/docs/en/settings.md § "Where Claude Code keeps the local file in a git repository"; https://code.claude.com/docs/en/settings.md § "Keep personal settings out of a repository"

- Started in a subdirectory of a git repo, Claude Code reads and writes `.claude/settings.local.json`
  at the repository root; in a worktree, at the main checkout's root.
- The file stays beside `.claude/settings.json` instead when: outside git, the repo root is the home
  directory, **on Windows**, or the repo root / its `.git` / `.claude` entry isn't owned by the user.
- Before v2.1.211 the file lived in the starting directory; a leftover file there is still read.
  Where both set a key the root file wins; permission rules from both apply.
- The shared `.claude/settings.json` is read from the session's primary working directory. After
  `/cd`, both project files are read from the new directory (v2.1.246+).
- On first write in a git repo that doesn't ignore it, Claude Code adds
  `**/.claude/settings.local.json` to the global git excludes file (`core.excludesFile`, else
  `$XDG_CONFIG_HOME/git/ignore`, else `~/.config/git/ignore`). A hand-created file must be ignored by
  hand.
- Allow rules in an untracked local file apply without workspace trust; if the file is tracked by
  git, the trust step applies to it too.

## Precedence

Source: https://code.claude.com/docs/en/settings.md § "Settings precedence"

Highest first; a higher level overrides the same key lower down:

| # | Level | Source |
| :-- | :-- | :-- |
| 1 | Managed settings | `managed-settings.json`, MDM policy, server-managed (claude.ai console) |
| 2 | Command line | `claude --settings <file-or-json>` and per-key flags, one session only |
| 3 | Project local | `.claude/settings.local.json` |
| 4 | Shared project | `.claude/settings.json` |
| 5 | User | `~/.claude/settings.json` |

- `--settings` cannot override a managed key; a flag like `--model` can only pick within what managed
  settings allow. `--settings` JSON merges with files by the same rules: its keys win over local,
  project, and user; omitted keys fall through.
- `--settings` can set any key the user file can set, but not `Managed` or `Global config` keys.
- Environment variables are not a level. Each variable/key pair decides its own winner (for example
  a shell `ANTHROPIC_MODEL` beats the `model` key from any file). An `env` block inside a settings
  file is an ordinary key and follows the stack.
- Multiple managed sources: by default the highest-priority source carrying a policy key wins
  (`managedSourcesBehavior: "first-wins"`); see the managed keys section below.

### How lists and objects merge

Source: https://code.claude.com/docs/en/settings.md § "Lists merge instead of overriding"; https://code.claude.com/docs/en/settings-reference.md § "`hooks`"; https://code.claude.com/docs/en/settings-reference.md § "`extraKnownMarketplaces`"; https://code.claude.com/docs/en/settings-reference.md § "`sandbox`"

- Array keys (for example `permissions.allow`) set in several files are concatenated; no file removes
  another file's entries.
- `hooks` merge across files; hooks from managed settings cannot be removed from other files.
- `allowedHttpHookUrls`, `httpHookAllowedEnvVars`, and sandbox filesystem lists merge across files.
- `autoMode` arrays set in several files are concatenated.
- `extraKnownMarketplaces`: a same-name entry is taken whole from the highest-precedence file; no
  field-by-field merge (since v2.1.228).
- Sandbox Boolean keys take the highest-precedence value; sandbox arrays merge.
- Exceptions with their own rules: `fallbackModel` (whole value from highest file), `modelPicker`
  (whole value; ignored in project/local), `availableModels` (managed list applies as-is),
  `modelSettings` (resolved per model).

### Exceptions to managed precedence

Source: https://code.claude.com/docs/en/settings.md § "Exceptions to managed settings precedence"

For a few restrictive keys, a stricter value from a lower scope beats a managed value:

| Key | Stricter value honored |
| :-- | :-- |
| `disableClaudeAiConnectors` | `true` from any scope |
| `enableArtifact` / `disableArtifact` | `false` / `true` from any scope (v2.1.242+) |
| `isolatePeerMachines` | `true` from any scope |
| `remoteControlAtStartup` | `false` from project or local |
| `crossSessionInbound` | stricter on `accept` < `hold` < `refuse`, from project or local |
| `useAutoModeDuringPlan` | `false` from managed, `--settings`, user, or local (not shared project) |
| `syncClaudeAiSkills` | `false` from managed, `--settings`, user, or local (not shared project) |
| `syncClaudeAiPlugins` | `false` from managed, `--settings`, user, or local (not shared project) |
| `maxEffortLevel` | the lowest cap from any scope (v2.1.267+) |

An embedding app that sets `CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST` also overrides managed model keys.

## Changing, reloading, and verifying

Source: https://code.claude.com/docs/en/settings.md § "Change a setting"

### Ways to change a setting

Source: https://code.claude.com/docs/en/settings.md § "Use the /config menu"; https://code.claude.com/docs/en/settings.md § "Edit a settings file"; https://code.claude.com/docs/en/settings.md § "Change a setting for one session"

- `/config` (terminal only) edits a short list of options: most go to `~/.claude/settings.json`, a
  few (such as Show tips) to `.claude/settings.local.json`, global config options to `~/.claude.json`.
  `/config key=value` sets one directly.
- Direct edit: files are strict JSON. `//` comments or trailing commas are errors.
- One session only: `--settings`, a key-specific flag (`--model`, `--effort`), or a paired env var.
- `/model` saves a default; pressing `s` in the picker switches without saving.

### JSON schema

Source: https://code.claude.com/docs/en/settings.md § "Edit a settings file"

- Add `"$schema": "https://json.schemastore.org/claude-code-settings.json"` for editor autocomplete
  and validation.
- The schema can lag new CLI releases; a warning on a newly documented key is not proof of an
  invalid config.

### When edits take effect

Source: https://code.claude.com/docs/en/settings.md § "When edits take effect"

- Claude Code watches settings files and reloads on change. Most edits apply to the running
  session without restart, explicitly including `permissions`, `hooks`, and credential helpers such
  as `apiKeyHelper`.
- A settings file created mid-session loads if its folder existed at session start. The project
  `.claude/` folder is loaded even if created during the session.
- Reload covers user, project, local, and managed files.
- The `ConfigChange` hook runs for each settings-file change Claude Code detects. It does not run
  for managed settings arriving from MDM or the claude.ai console; those arrive on a schedule.
- Read-once-at-start keys include `model`, `effortLevel`, `modelSettings`; admin keys such as
  `requiredMinimumVersion` also wait for restart.
- Sandbox filesystem list edits apply to the running session.
- `policyHelper.refreshIntervalMs` lets a helper's new output replace managed settings mid-session.

### Confirm what loaded

Source: https://code.claude.com/docs/en/settings.md § "Confirm what loaded"; https://code.claude.com/docs/en/settings.md § "Check what your organization enforces"

- `/status` > Status tab > `Setting sources` line lists each file loaded (for example
  `User settings`, `Project local settings`). A managed entry shows in parentheses how it arrived.
- The line shows which files loaded, not which file supplied each key.
- `claude doctor` lists entries Claude Code rejected.
- `/status` and `/config` are the same dialog on different tabs; the Config tab is not a view of
  `settings.json`.

### Broken files

Source: https://code.claude.com/docs/en/settings.md § "Fix a broken settings file"

| Condition | Behavior |
| :-- | :-- |
| Settings Error (invalid JSON or schema-rejected value in user/project/local) | Interactive start shows a dialog: fix with Claude, exit, or continue without the broken settings |
| Settings Warning (individual bad entries, such as a malformed permission rule or unknown hook event) | Bad entries skipped, rest of file applies |
| Bad managed entries | Rest of managed file still enforced; some keys fall back to stricter values |
| `~/.claude.json` unparsable | Copied to `~/.claude/backups/.claude.json.corrupted.<timestamp>`; prompt to exit or reset |
| `-p` (non-interactive) run | No dialog; broken file or values skipped silently; check `claude doctor` |

### Trust-gated and repository-ignored keys

Source: https://code.claude.com/docs/en/settings.md § "A committed key doesn't reach teammates"; https://code.claude.com/docs/en/settings.md § "A value you set is ignored"

- Keys scoped `User, local, or managed`, `User or managed`, `Managed`, or `Global config` never apply
  from the shared project file (a few can still be switched off from it; each says so).
- `permissions.allow`, `permissions.additionalDirectories`, `extraKnownMarketplaces`, and most `env`
  values from the shared project file wait until the user trusts the folder. `deny` and `ask` rules
  apply immediately.
- `permissions.defaultMode` values `auto` and `bypassPermissions` do not take effect from project or
  local settings (before v2.1.257 `bypassPermissions` worked from any file).

### Cloud sessions

Source: https://code.claude.com/docs/en/settings.md § "Settings in cloud sessions"

- Single-repo cloud session reads the committed `.claude/settings.json`. Multi-repo sessions read only
  `enabledPlugins` and `extraKnownMarketplaces` from each repo (not permissions, hooks, `env`).
- User and local files are not read. Only server-managed settings apply (plus a self-hosted
  runner image's managed file).

## Hook keys

Source: https://code.claude.com/docs/en/settings-reference.md § "Hooks and automation"

| Key | Type | Default | Scope | Meaning |
| :-- | :-- | :-- | :-- | :-- |
| `hooks` | object keyed by hook event; each value an array of `{matcher, hooks}` groups; handler `type` is `command`, `prompt`, `agent`, `http`, or `mcp_tool` | unset (no hooks) | Any file | Registers lifecycle hooks; merges across files; managed hooks can't be removed elsewhere |
| `disableAllHooks` | Boolean | unset (hooks run) | Any file | Turns off hooks, custom status line, custom file suggestion; only managed can disable managed hooks |
| `allowManagedHooksOnly` | Boolean | unset | Managed | Only managed, SDK, and managed-force-enabled plugin hooks run |
| `allowedHttpHookUrls` | array of URL patterns (`*` wildcard) | unset (any URL) | Any file | HTTP hooks run only if URL matches; `[]` blocks all; applies to all sources incl. managed |
| `httpHookAllowedEnvVars` | array of env var names | unset (each hook's own `allowedEnvVars`) | Any file | Outer limit on env vars HTTP hooks may put in headers; arrays merge |
| `disableWorkflows` | Boolean | `false` | Any file | Turns off dynamic workflows for everyone the file reaches |
| `enableWorkflows` | Boolean | unset (on except Pro plan) | Any file | Personal workflows toggle; cannot override any source turning them off |
| `workflowKeywordTriggerEnabled` | Boolean | `true` | Any file | Whether the word `ultracode` in a prompt starts a workflow |
| `workflowSizeGuideline` | `"unrestricted"`/`"small"`/`"medium"`/`"large"` | `"medium"` (`"small"` on Pro, v2.1.271+) | Any file | Advisory agent-count target for workflows |

### `disableAllHooks` reach

Source: https://code.claude.com/docs/en/settings-reference.md § "`disableAllHooks`"; https://code.claude.com/docs/en/settings-reference.md § "Status line and file suggestion gates"

- In managed settings: disables every configured hook including managed ones; Agent SDK in-process
  hooks keep running (v2.1.242+).
- In any other file: disables user, project, local, and plugin hooks; managed hooks, SDK hooks, and
  plugins force-enabled by managed `enabledPlugins` keep running.
- While hooks are disabled, `/goal` cannot run and `/hooks` shows a notice.
- `statusLine`, `fileSuggestion`, `subagentStatusLine` are off entirely when managed sets
  `disableAllHooks` or the folder is untrusted; they narrow to managed-only values under
  `allowManagedHooksOnly`, a non-managed `disableAllHooks: true`, or `--safe-mode`.

### What runs under `allowManagedHooksOnly`

Source: https://code.claude.com/docs/en/settings-reference.md § "What runs under `allowManagedHooksOnly`"

- Runs: managed-settings hooks; Agent SDK in-process hooks; hooks from plugins force-enabled in
  managed `enabledPlugins`, matched on full `plugin@marketplace` ID.
- Blocked: user, project, local hooks; other plugins' hooks; hooks in agent frontmatter.
- Also disables `command`-source plugins (even force-enabled) and marketplace `headersHelper`
  commands, unless `disableCommandPluginSources` is explicitly `false`.
- `/goal` cannot run while set.

## Skill keys

Source: https://code.claude.com/docs/en/settings-reference.md § "Plugins and skills"; https://code.claude.com/docs/en/settings-reference.md § "Memory and context"

| Key | Type | Default | Scope | Meaning |
| :-- | :-- | :-- | :-- | :-- |
| `skillOverrides` | object: skill name to `"on"`/`"name-only"`/`"user-invocable-only"`/`"off"` | unset (all `"on"`) | Any file | Hide or collapse a skill without editing `SKILL.md`; `/skills` menu writes it to `.claude/settings.local.json`; does not apply to plugin skills |
| `disableBundledSkills` | Boolean | unset (bundled load) | Any file | Removes bundled skills and workflows; built-ins like `/init` hidden from model; env `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1` also works, either one wins for off |
| `disableSkillShellExecution` | Boolean | unset (inline shell runs) | Any file | Replaces `` !`...` `` and ` ```! ` blocks in user/project/plugin/add-dir skills and commands with `[shell command execution disabled by policy]`; managed `true` can't be overridden |
| `syncClaudeAiSkills` | Boolean (only `false` honored) | unset (sync on) | User, local, or managed, plus `--settings` | Stops downloading/loading skills in `~/.claude/skills/synced/`; in user/managed moves them to `~/.claude/skills/.trash/` |
| `skillListingBudgetFraction` | number, >0 and <=1 | `0.01` | Any file | Context share for the per-turn skill listing |
| `skillListingMaxDescChars` | positive integer | `1536` | Any file | Per-skill description character cap in the listing |
| `strictPluginOnlyCustomization` (`"skills"`) | string in array | not locked | Managed | See plugin section |

## Plugin and marketplace keys

Source: https://code.claude.com/docs/en/settings-reference.md § "Plugins and skills"

| Key | Type | Default | Scope | Meaning |
| :-- | :-- | :-- | :-- | :-- |
| `enabledPlugins` | object: `plugin@marketplace` to Boolean | unset (plugin `defaultEnabled`) | Any file | Per-plugin on/off; `/plugin` writes it; managed `false` blocks install at every scope |
| `extraKnownMarketplaces` (alias `additionalMarketplaces`, v2.1.232+) | object: name to `{source, autoUpdate?}` | unset | Any file; repo entries need trust | Registers marketplaces; same-name entry taken whole from highest file |
| `strictKnownMarketplaces` (alias `allowedMarketplaces`, v2.1.232+) | array of source objects | unset (any marketplace) | Managed | Allowlist of marketplace sources; `[]` blocks all incl. official; any allowlist also stops `@skills-dir` plugins unless `{ "source": "skills-dir" }` listed |
| `blockedMarketplaces` | array of source objects | unset | Managed | Blocklist checked on add/install/update/refresh/auto-update before download |
| `strictPluginOnlyCustomization` | `true` or array of `"skills"`/`"agents"`/`"hooks"`/`"mcp"` | unset | Managed | Only plugins and managed settings may supply the named surfaces; unknown names ignored |
| `disableCommandPluginSources` | Boolean | unset (follows `allowManagedHooksOnly`) | Managed | `true` blocks `command`-source plugins and marketplace `headersHelper` (v2.1.229+/v2.1.238+) |
| `pluginConfigs` | object: plugin ID to `{options, mcpServers?}` | unset | User or managed | Stored `userConfig` answers; ignored in project/local since v2.1.207 |
| `syncClaudeAiPlugins` | Boolean (only `false` honored) | unset | User, local, or managed, plus `--settings` | Stops syncing `~/.claude/plugins/synced/` (v2.1.273+) |
| `pluginTrustMessage` | string | unset | Managed | Extra text in the plugin trust warning |
| `pluginSuggestionMarketplaces` | array of names | unset | Managed | Which marketplaces may surface install suggestions |
| `channelsEnabled` | Boolean | unset (plan-dependent) | Managed | Allows channels for the org |
| `allowedChannelPlugins` | array of `{marketplace, plugin}` or `"plugin@marketplace"` | unset (Anthropic allowlist) | Managed | Which channel plugins may push messages; `[]` blocks all |
| `disableSideloadFlags` | Boolean | `false` | Managed | Rejects `--plugin-dir`, `--plugin-url`, `--agents`, `--mcp-config` at startup (v2.1.193+) |
| `agent` | string (agent name) | unset | Any file | Runs main thread as a named subagent; `--agent` overrides; a plugin's own `settings.json` can supply it |

### `strictPluginOnlyCustomization` surfaces

Source: https://code.claude.com/docs/en/settings-reference.md § "`strictPluginOnlyCustomization.skills`"; https://code.claude.com/docs/en/settings-reference.md § "`strictPluginOnlyCustomization.agents`"; https://code.claude.com/docs/en/settings-reference.md § "`strictPluginOnlyCustomization.hooks`"; https://code.claude.com/docs/en/settings-reference.md § "`strictPluginOnlyCustomization.mcp`"

| Surface | Stops loading | Still loads |
| :-- | :-- | :-- |
| `skills` | `~/.claude/skills/`, `.claude/skills/`, `~/.claude/commands/`, `.claude/commands/`, `--add-dir` skills, claude.ai-synced skills | plugin, bundled, managed-policy-directory skills |
| `agents` | `~/.claude/agents/`, `.claude/agents/` | plugin, built-in, managed-policy-directory agents |
| `hooks` | hooks from user, project, local `settings.json` | plugin hooks, managed hooks |
| `mcp` | `~/.claude.json` and `.mcp.json` servers | plugin, `managed-mcp.json`, `managedMcpServers` servers |

### Plugin scope behavior

Source: https://code.claude.com/docs/en/settings-reference.md § "`enabledPlugins`"; https://code.claude.com/docs/en/settings-reference.md § "Combine with `extraKnownMarketplaces`"

- Project `enabledPlugins` beats user: disabling in the user file does not disable a
  project-enabled plugin; use the local file instead. Managed force-enabled plugins cannot be
  disabled locally.
- Enabling an external-source plugin in a project file does not install it for others; each user
  installs it.
- `strictKnownMarketplaces` is a gate that registers nothing; `extraKnownMarketplaces` registers.
  Put both in managed settings to restrict and pre-register.
- Marketplace source types: `github`, `git`, `url` (optional `headers`, `headersHelper`), `file`,
  `directory`, `settings` (inline). Allowlist entries add `hostPattern`, `pathPattern`, `skills-dir`.
- Allowlist matching is exact (including `ref`/`path`) except owner-wildcard `"owner/*"`
  (v2.1.223+) and the regex patterns.
- `headersHelper` in a project or local file runs only after folder trust; ignored entirely in an
  `--add-dir` directory's settings.

## Permission keys

Source: https://code.claude.com/docs/en/settings-reference.md § "Permission settings"

| Key | Type | Default | Scope | Meaning |
| :-- | :-- | :-- | :-- | :-- |
| `permissions` | object (`allow`, `ask`, `deny`, `additionalDirectories`, `blockReadsOutsideWorkingDirectories`, `defaultMode`, `disableBypassPermissionsMode`, `disableAutoMode`) | unset | Any file | Container for permission rules and starting mode |
| `permissions.allow` | array of rule strings | unset | Any file; project entries need trust | Approve without prompt; `--allowedTools` adds per session |
| `permissions.ask` | array of rule strings | unset | Any file | Always prompt, even in `acceptEdits`/`bypassPermissions`; denied in `dontAsk` |
| `permissions.deny` | array of rule strings | unset | Any file | Block; hides matching files from discovery; blocks Edit/Write on matching paths; `--disallowedTools` adds per session |
| `permissions.additionalDirectories` | array of paths | unset | Any file; project entries need trust | Extra working directories; most `.claude/` config is not discovered from them; `--add-dir`, `/add-dir` add per session |
| `permissions.blockReadsOutsideWorkingDirectories` | Boolean | unset | Any file; any `true` wins | File tools refuse reads outside working dirs in every mode (v2.1.257+) |
| `permissions.defaultMode` | `default`/`acceptEdits`/`plan`/`auto`/`dontAsk`/`bypassPermissions`/`manual` | unset (built-in default) | Any file, but `auto` and `bypassPermissions` ignored from project/local | Starting permission mode; `--permission-mode` / `--dangerously-skip-permissions` override |
| `permissions.disableBypassPermissionsMode` | `"disable"` | unset | Any file (typically managed) | Blocks `bypassPermissions`; rejects `--dangerously-skip-permissions`; ignores agent `permissionMode: bypassPermissions` |
| `disableAutoMode` (also `permissions.disableAutoMode`) | `"disable"` | unset | Any file | Removes auto mode from the cycle; sessions start in `default` |
| `allowManagedPermissionRulesOnly` | Boolean | unset | Managed | Managed becomes the only source of allow/ask/deny rules |
| `autoMode` | object with `environment`, `allow`, `soft_deny`, `hard_deny` prose arrays and `classifyAllShell` | unset (built-in rules) | User or managed | Extend or replace auto-mode classifier rules; `"$defaults"` keeps built-ins |
| `autoMode.classifyAllShell` | Boolean | `false` | User or managed | Every shell command goes through the classifier in auto mode (v2.1.193+) |
| `useAutoModeDuringPlan` | Boolean | `true` | User, local, or managed | Classifier reviews shell commands in plan mode; `false` prompts instead |
| `skipAutoPermissionPrompt` | Boolean | unset | User or managed | Skip one-time auto-mode notice |
| `skipDangerousModePermissionPrompt` | Boolean | unset | User, local, or managed | Skip bypass-mode confirmation; written to user settings after first accept |

### Rule evaluation

Source: https://code.claude.com/docs/en/settings-reference.md § "Permission rule syntax"; https://code.claude.com/docs/en/settings-reference.md § "`permissions.deny`"; https://code.claude.com/docs/en/settings-reference.md § "`permissions.defaultMode`"

- Rule format: `Tool` or `Tool(specifier)`, for example `Bash(npm run *)`, `Read(./.env)`,
  `WebFetch(domain:example.com)`. Tool names in deny accept globs (`"*"`, `"mcp__*"`).
- Order: `deny`, then `ask`, then `allow`; first match decides regardless of specificity.
- `deny` rules block in every mode, including `bypassPermissions`.
- Read/Edit deny rules cover built-in file tools, recognized Bash file commands (`cat`, `head`,
  `tail`, `sed`, `tee`) and redirection targets. They do not cover commands that read without naming
  files or arbitrary subprocesses; the source points to the sandbox for OS-level enforcement.
- A Bash deny matches the command text as written, so `Bash(curl *)` misses `/usr/bin/curl` or
  `sh -c 'curl ...'`.
- `deny` replaces the deprecated `ignorePatterns`.
- In cloud sessions only `acceptEdits`, `plan`, `default`, `auto` are honored from `defaultMode`.

### `allowManagedPermissionRulesOnly` details

Source: https://code.claude.com/docs/en/settings-reference.md § "`allowManagedPermissionRulesOnly`"; https://code.claude.com/docs/en/settings.md § "Permission rules combine differently than you expected"

- Ignores allow/ask/deny from user, project, local, and `--settings`; ignores `--allowedTools`;
  hides always-allow choices in prompts; stops saving new rules.
- `--disallowedTools` and the current session's deny/ask rules still apply, including after a
  mid-session reload (since v2.1.257).
- Embedding-host parent settings: their allow rules and `additionalDirectories` are dropped; their
  deny/ask kept except `Read`/`Edit` rules whose pattern starts with `!`.
- Does not lock the MCP allowlist (`allowManagedMcpServersOnly` does).
- Without this key, `permissions.allow` merges across all scopes. A local-file allow rule (what
  "Yes, and don't ask again" writes in the CLI) does not outrank a project or managed `ask` rule.

### Sandbox write lists (related enforcement)

Source: https://code.claude.com/docs/en/settings-reference.md § "`sandbox.filesystem`"; https://code.claude.com/docs/en/settings-reference.md § "`sandbox.filesystem.allowWrite`"; https://code.claude.com/docs/en/settings-reference.md § "`sandbox.filesystem.denyWrite`"; https://code.claude.com/docs/en/settings-reference.md § "`sandbox.enabled`"

| Key | Type | Default | Scope | Meaning |
| :-- | :-- | :-- | :-- | :-- |
| `sandbox.enabled` | Boolean | `false` | Any file | Sandbox Bash commands (macOS, Linux, WSL2); `/sandbox` writes it to local file |
| `sandbox.filesystem.allowWrite` | array of paths | unset | Any file | Extra writable paths; merges; cannot lift a protected path |
| `sandbox.filesystem.denyWrite` | array of paths | unset | Any file | Block writes at OS level; merges; `Edit(...)` deny rules are added to it |

`Edit` allow/deny rules feed `allowWrite`/`denyWrite`, and `Read` deny rules feed `denyRead`.

## `env` key

Source: https://code.claude.com/docs/en/settings-reference.md § "`env`"; https://code.claude.com/docs/en/settings-reference.md § "When Claude Code applies `env` values"; https://code.claude.com/docs/en/settings-reference.md § "Variables Claude Code ignores in `env`"

| Key | Type | Default | Scope |
| :-- | :-- | :-- | :-- |
| `env` | object: variable name to string | unset | Any file |

- Overwrites a shell export of the same name; highest-precedence file wins per variable. `""`
  cancels a shell export.
- Applied from user, `--settings`, managed: at startup and on any saved change that alters the
  merged `env`. From project/local: after workspace trust (or at startup under `-p`), and on change.
- Project/local cannot set `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_TMPDIR`, `HOME`, `TMPDIR`, `TMP`,
  `TEMP`, `XDG_*`, `OTEL_LOG_RAW_API_BODIES`, beta tracing pair, `CLAUDE_CODE_PROCESS_WRAPPER`,
  `CLAUDE_CODE_SYNC_SKILLS`, `CLAUDE_CODE_SYNC_PLUGINS`, `CLAUDE_CODE_PLUGIN_CACHE_DIR`,
  `CLAUDE_CODE_PLUGIN_SEED_DIR` (dropped with a `--debug` warning).
- Ignored from every file: `CLAUDE_CODE_REMOTE`, `CLAUDE_CODE_ACCOUNT_UUID`,
  `CLAUDE_CODE_MESSAGING_SOCKET`, `CLAUDE_CODE_MESSAGING_TOKEN`, `CLAUDE_CODE_PROJECT_DIR_NAME`,
  `CLAUDE_CODE_RESTRICTED`.
- Under multiple managed sources, `env` merges per variable across admin sources in both modes.

## Managed-source control keys

Source: https://code.claude.com/docs/en/settings-reference.md § "Enterprise and managed settings"

| Key | Type | Default | Scope | Meaning |
| :-- | :-- | :-- | :-- | :-- |
| `managedSourcesBehavior` | `"first-wins"` / `"merge"` | `"first-wins"` | Managed | Use only the top managed source, or combine all admin sources (v2.1.242+) |
| `parentSettingsBehavior` | `"first-wins"` / `"merge"` | `"first-wins"` | Managed | Drop, or apply restrictive-only, settings passed by an embedding host |
| `policyHelper` | object `{path, timeoutMs, refreshIntervalMs}` | unset | Managed (plist, HKLM, or managed file only) | Executable that emits `{"managedSettings": {...}}` at startup; its output becomes the only managed source; failure refuses startup |
| `policyHelper.timeoutMs` | integer ms, min `1000` | `10000` | Managed | Helper timeout |
| `policyHelper.refreshIntervalMs` | integer ms, `0` or >= `60000` | unset (run once) | Managed | Background re-run; success replaces managed settings live |
| `forceRemoteSettingsRefresh` | Boolean | `false` | Managed | Block startup until server-managed settings are freshly fetched; exit on failure |
| `wslInheritsWindowsSettings` | Boolean | `false` | Managed (HKLM or `C:\Program Files\ClaudeCode\`) | WSL reads Windows policy chain |

Under `"merge"`: lists combine; locks such as `allowManagedPermissionRulesOnly` and
`permissions.disableBypassPermissionsMode` take the strictest value; restriction allowlists such as
`strictKnownMarketplaces` and `allowedChannelPlugins` are taken whole from the highest source that
sets them; `permissions.defaultMode` and `policyHelper` are read from the highest-priority source only.

## Not found in source

Source: https://code.claude.com/docs/en/settings.md § "Settings files and precedence"; https://code.claude.com/docs/en/settings-reference.md § "All settings"

- Full path of the managed settings file on macOS and on native Linux (only `/etc/claude-code` is
  named, in the WSL context, and only "macOS plist" for MDM).
- Exact Windows registry key paths under HKLM/HKCU and the macOS plist domain name.
- The file name and layout of managed drop-in files (only "drop-in under `C:\Program Files\ClaudeCode\`").
- Managed-source priority order between server-managed, MDM/HKLM, file, and HKCU (deferred to the
  managed-settings page).
- Server-managed settings polling interval ("on a schedule", per a delivery table on another page).
- `ConfigChange` hook payload, matcher values, and whether it can block a change (only its existence
  and firing rule are stated).
- The complete list of hook event names and handler fields (deferred to the hooks page).
- Sandbox "protected paths" contents, including whether `.claude/settings.json` or `.claude/hooks/`
  are protected (only linked, not listed).
- Any key that makes a settings file or `.claude/hooks/` read-only or tamper-evident; no such key is
  documented.
- The `--setting-sources` flag's syntax (mentioned only in passing under `sandbox.filesystem`).
