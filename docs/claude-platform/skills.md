---
verified: 2026-09-23
sources:
  - https://code.claude.com/docs/en/skills.md
  - https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md
scope: Claude Code skills (SKILL.md locations, frontmatter, invocation control, tool grants, shell injection, forked execution, lifecycle, settings and permission controls, diagnostics) plus the load-bearing authoring guidance from the platform best-practices page; it does not cover plugins, hooks, subagents, or the Skills API beyond what these two pages state.
---

# Skills

A skill is a directory holding a `SKILL.md` file: YAML frontmatter that describes when and how it runs, then Markdown instructions. Claude Code lists each skill's name and description to the model up front and loads the full body only when the user types `/name` or the model invokes it. Custom commands in `.claude/commands/` are the older form of the same thing and keep working.

## What a skill is and how it relates to commands

Source: https://code.claude.com/docs/en/skills.md § "Extend Claude with skills"

- A file at `.claude/commands/deploy.md` and a skill at `.claude/skills/deploy/SKILL.md` both produce `/deploy` and behave the same.
- Skills add a directory for supporting files, frontmatter for invocation control, and model auto-loading.
- Claude Code skills follow the Agent Skills open standard (agentskills.io) and add Claude-Code-only extensions: invocation control, subagent execution, dynamic context injection.
- Rationale given by the source: a skill body loads only when used, so long reference material is nearly free until needed, unlike CLAUDE.md content.

## Bundled skills

Source: https://code.claude.com/docs/en/skills.md § "Bundled skills"

- Claude Code ships prompt-based bundled skills (examples named: `/doctor`, `/code-review`, `/batch`, `/debug`, `/loop`, `/claude-api`). Most built-in commands, by contrast, run fixed logic.
- Some bundled skills the model may auto-invoke; others (for example `/verify`) run only when the user invokes them.
- Some depend on a feature being on (`/workflow-authoring` requires dynamic workflows).
- `disableBundledSkills` setting turns bundled skills off.
- From v2.1.205, `/doctor` is a bundled skill and stays typable even with `disableBundledSkills` on. To hide it: `DISABLE_DOCTOR_COMMAND` env var or `skillOverrides` entry `"doctor": "off"`.

### Run and verify your app

Source: https://code.claude.com/docs/en/skills.md § "Run and verify your app"

| Skill | Role |
| :-- | :-- |
| `/run` | Launch and drive the app to observe a change |
| `/verify` | Build and run the app to confirm a change, without falling back to tests or type checks |
| `/run-skill-generator` | Record a launch recipe as a project skill at `.claude/skills/run-<name>/` |

- `/verify` (v2.1.200+) can write its own recipe to `.claude/skills/verify/SKILL.md` (repo root, or touched package dir in a monorepo). At the repo root that recorded skill replaces the bundled `/verify`.
- Since v2.1.205 Claude edits the recorded file only when it steered a run wrong, so the file is commit-stable.

## Where skills load

Source: https://code.claude.com/docs/en/skills.md § "Choose where skills load"

| Location | Path | Loads in |
| :-- | :-- | :-- |
| Enterprise | `.claude/skills/<skill-name>/SKILL.md` inside the managed settings directory | All users on machines where the org deploys it |
| Personal | `~/.claude/skills/<skill-name>/SKILL.md` | All projects on this machine; not Cowork or cloud sessions |
| Project | `.claude/skills/<skill-name>/SKILL.md` | Sessions in this repo |
| Nested | `<subdir>/.claude/skills/<skill-name>/SKILL.md` | Sessions started in or below `<subdir>`; otherwise once Claude touches files there |
| Additional directory | `.claude/skills/...` in a dir passed with `--add-dir` | That session |
| Plugin | `<plugin>/skills/<skill-name>/SKILL.md` | Wherever the plugin is enabled, as `/plugin-name:skill-name` |
| claude.ai account | Skills enabled on the account | Cowork, cloud, and terminal sessions signed in with that account |

Folder rules:

- A skill folder in enterprise, personal, or project locations may be a symlink; the target's `SKILL.md` is read and deduplicated if several locations point to it.
- `synced` (any case) is a reserved folder name; an authored skill with that name is skipped.
- `.claude/commands/*.md` supports the same frontmatter except `name` and `paths`.
- Adding `.claude-plugin/plugin.json` to a skill folder makes it load as a plugin named `<name>@skills-dir`. In a project's `.claude/skills/` this requires accepting the workspace trust dialog first.

### Monorepos, subdirectories, and added directories

Source: https://code.claude.com/docs/en/skills.md § "Load skills in monorepos and subdirectories"; https://code.claude.com/docs/en/skills.md § "Load skills from a directory outside the project"

- Project skills load from `.claude/skills/` in the start directory and every parent up to the repo root. `/cd` (v2.1.246+) adds the new directory's project skills.
- In a linked git worktree the parent walk stops at the worktree root; on v2.1.277+, if the worktree has no root `.claude/skills`, the main checkout's project skills load instead.
- Skills below the start directory load the first time Claude reads or edits a file in that subdirectory, then stay for the session. `/add-dir <path>` (v2.1.257+) loads them sooner.
- `--add-dir` / `/add-dir` loads that directory's `.claude/skills/`, `.claude/commands/`, and `.claude/agents/`. Agent SDK `additionalDirectories` / `add_dirs` behave the same. `permissions.additionalDirectories` in settings grants file access only and loads none of them.
- Only `.claude/skills/` in an added directory is watched live; changes to its commands or agents need a restart.
- These loads depend on the `project` setting source. `strictPluginOnlyCustomization`, bare mode, and `--safe-mode` restrict them further.

### Live change detection and removal

Source: https://code.claude.com/docs/en/skills.md § "Edit a skill during a session"; https://code.claude.com/docs/en/skills.md § "Remove a skill"

- Skill directories are watched (not in bare mode). Adds, edits, and removals under personal, project, and `--add-dir` skill dirs take effect in the running session. A top-level skills dir created after startup needs a restart.
- Watching covers `SKILL.md` text only. For a skill folder that is also a plugin, changes to `hooks/`, `.mcp.json`, `agents/`, `output-styles/` need `/reload-plugins`.
- Removal by origin: delete the directory (personal/project/enterprise); disable or uninstall the plugin; turn it off on claude.ai (synced); `disableBundledSkills` or `skillOverrides: "off"` (bundled).
- To keep a skill but stop model invocation: `disable-model-invocation: true` in frontmatter, or `"user-invocable-only"` in `skillOverrides` without editing the file.

## Synced skills from claude.ai

Source: https://code.claude.com/docs/en/skills.md § "Skills synced from claude.ai"; https://code.claude.com/docs/en/skills.md § "Where synced skills load"

- Terminal sessions signed in with a claude.ai account (v2.1.273+) download account skills into `~/.claude/skills/synced/` in the background and re-check about every 10 minutes; changes apply without restart.
- Sync never delays startup. `CLAUDE_CODE_SYNC_SKILLS=1` makes a non-interactive run wait for the list.
- No sync when: credential is an API key, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, or `apiKeyHelper`; feature flags are not fetched (for example Bedrock, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`); bare mode or `--safe-mode`; managed settings lock skills to plugin sources; `--setting-sources` omits `user`.
- Download only, never upload. Local edits under `synced/` are not saved back and may be overwritten.
- `syncClaudeAiSkills: false` in user settings stops syncing and moves already-synced skills to `~/.claude/skills/.trash/` at next start. Managed settings can set the same key org-wide.
- Cowork and cloud sessions (including routines) never read the local `~/.claude/skills/`. Cloud sessions also load committed project skills. Desktop scheduled tasks run locally and do read `~/.claude/skills/`.

### Synced skill frontmatter and body handling

Source: https://code.claude.com/docs/en/skills.md § "How Claude Code handles the frontmatter of a synced skill"; https://code.claude.com/docs/en/skills.md § "How Claude Code handles the body of a synced skill"

- Frontmatter is honored everywhere; an `allowed-tools` grant goes through the normal permission flow.
- Display text is sanitized (v2.1.228+): control characters removed; angle brackets escaped in text that reaches Claude.
- Body handling by session:

| Session | `!` commands | `@` file refs and `${CLAUDE_PROJECT_DIR}` / `${CLAUDE_SESSION_ID}` |
| :-- | :-- | :-- |
| Cloud | Run as for a local skill | Processed as for a local skill |
| Cowork on desktop | Replaced by the `disableSkillShellExecution` placeholder | Processed as for a local skill |
| Any other local session | Not run; reach Claude as literal text (or the placeholder if that setting is on) | Not processed; reach Claude as literal text |

## Name resolution
Source: https://code.claude.com/docs/en/skills.md § "Resolve skills that share a name"; https://code.claude.com/docs/en/skills.md § "How a skill gets its command name"

Two tables govern names: which skill wins a collision, and where the typed command name comes from.

### When two skills share a name

Source: https://code.claude.com/docs/en/skills.md § "Resolve skills that share a name"

| Same name in | What `/name` runs |
| :-- | :-- |
| Two of enterprise, personal, project | Enterprise beats personal; personal beats project |
| One of those and a bundled skill | Your skill replaces the bundled command but not its aliases (a project `code-review` replaces `/code-review`; `/review` still runs the bundled one) |
| A skill and a `.claude/commands/` file | The skill |
| Project-root skill and nested skill | Both load; `/deploy` runs the root one, `/apps/web:deploy` runs the nested one, and the model is told to pick the one whose directory holds the files in play |
| Plugin skill and any of the above | Both load (plugin skills are namespaced `/plugin-name:skill-name`) |
| Any of the above and a claude.ai synced skill | The other one; the synced skill stays reachable as `/anthropic-skills:<name>` |

### How a skill gets its command name

Source: https://code.claude.com/docs/en/skills.md § "How a skill gets its command name"

| Layout | Command name comes from | Example |
| :-- | :-- | :-- |
| `~/.claude/skills/<dir>/` or `.claude/skills/<dir>/` | Directory name (`name` is display label only) | `.claude/skills/deploy-staging/SKILL.md` -> `/deploy-staging` |
| Nested `.claude/skills/`, on a name clash | Subdir path relative to working dir, then skill dir name | `apps/web/.claude/skills/deploy/` -> `/apps/web:deploy` |
| `.claude/commands/<file>.md` | File name without extension | `deploy.md` -> `/deploy` |
| Subdir of `.claude/commands/` | Path under `commands/` with `/` -> `:`, then file name | `frontend/component.md` -> `/frontend:component` |
| Plugin `skills/<dir>/` | Frontmatter `name` or dir name, prefixed by plugin | `/my-plugin:review`, or `/my-plugin:fancy` with `name: fancy` |
| Plugin root `SKILL.md` | Frontmatter `name`, else plugin dir name | `/my-plugin:review` |
| Synced from claude.ai | Account skill name prefixed `anthropic-skills:` | `/anthropic-skills:deploy`, or `/deploy` if unclaimed |

- A plugin skill's bare `/fancy` also works unless another command owns that name.
- v2.1.246+: a `name` already carrying the plugin prefix is not double-prefixed (v2.1.216 to v2.1.245 doubled it).
- In non-interactive sessions only `help` and `feedback` are freed for plugin skills; other terminal-only built-in names such as `/login` stay reserved.

### Synced-name collisions

Source: https://code.claude.com/docs/en/skills.md § "When a synced skill name matches another command"

- A synced skill loses its short name to any built-in command, bundled skill (even one disabled in this session), local skill, commands file, plugin skill, or MCP prompt.
- Name comparison ignores case, spacing, and invisible characters and folds compatibility forms (fullwidth letters, dash variants). A look-alike letter from another alphabet counts as a different name; the `claude.ai sync` label distinguishes them (v2.1.228+).

## Frontmatter
Source: https://code.claude.com/docs/en/skills.md § "Frontmatter reference"

YAML between `---` markers at the top of `SKILL.md`; instructions follow as Markdown.

### Parsing rules

Source: https://code.claude.com/docs/en/skills.md § "Frontmatter reference"

- Frontmatter is read only if the opening `---` is line 1; otherwise the whole file is skill content.
- Unparseable YAML: the skill still loads with no fields set.
- Unknown field names are ignored silently; names must match exactly, hyphens included. All names are lowercase-hyphenated except `when_to_use`.
- Every field is optional; only `description` is recommended.
- Booleans accept `true`/`false`, `yes`/`no`, `on`/`off`, `1`/`0`, any case (v2.1.218+; earlier only `true`/`false`).

### Field table

Source: https://code.claude.com/docs/en/skills.md § "Frontmatter reference"

"Type" and "Default" are filled only where the source states them.

| Field | Type / accepted form | Default | Meaning |
| :-- | :-- | :-- | :-- |
| `name` | not stated | Directory name | Display name in listings. Command name rules above |
| `description` | not stated | First non-empty Markdown line | What it does and when to use it; drives auto-invocation. Combined with `when_to_use`, truncated at 1,536 chars in the listing |
| `when_to_use` | not stated | not stated | Extra trigger context appended to `description`; counts toward the 1,536 cap |
| `argument-hint` | not stated | not stated | Autocomplete hint, e.g. `[issue-number]` |
| `arguments` | space-separated string or YAML list | not stated | Named positional args for `$name` substitution, mapped by order |
| `disable-model-invocation` | boolean | `false` | `true` stops the model from loading it; also blocks preloading into subagents and (v2.1.196+) running as a scheduled task's prompt |
| `user-invocable` | boolean | `true` | `false` hides from `/` menu and refuses user `/name` |
| `allowed-tools` | space- or comma-separated string, or YAML list | not stated | Tools usable without a prompt during the invoking turn only |
| `disallowed-tools` | space- or comma-separated string, or YAML list | not stated | Tools removed from the pool while the skill is active; clears on next user message |
| `model` | `/model` values or `inherit` | not stated | Model for the rest of the current turn; not persisted. With `context: fork`, sets the forked subagent's model |
| `effort` | `low`, `medium`, `high`, `xhigh`, `max` (model-dependent) | Inherits session | Effort level while active |
| `context` | `fork` | not stated | Run in a forked subagent |
| `agent` | subagent type name | `general-purpose` (per "Run skills in a subagent") | Subagent type under `context: fork` |
| `background` | boolean | `true` | Only with `context: fork`; `false` waits for the result in the invoking turn (v2.1.218+) |
| `hooks` | see hooks docs | not stated | Registered on invocation and kept for the rest of the session |
| `paths` | comma-separated string or YAML list of globs | not stated | Model auto-loads the skill only when working on matching files; same format as path-specific rules |
| `shell` | `bash` or `powershell` | `bash` | Shell for `` !`cmd` `` and ` ```! ` blocks |
| `metadata` | YAML map | not stated | Free-form data for your tooling; Claude Code ignores it and drops a non-map value. Do not reuse field names like `paths` as keys |
| `license` | not stated | not stated | Agent Skills spec field; accepted, not acted on |
| `compatibility` | string, max 500 chars | not stated | Agent Skills spec field for environment requirements; accepted, not acted on |

`model` caveats: a value outside the org `availableModels` allowlist is not used; in auto mode (and plan mode with the classifier) a model auto mode does not support is not used; the session keeps its current model in both cases.

### Open spec fields vs Claude Code extensions

Source: https://code.claude.com/docs/en/skills.md § "Using skill frontmatter outside Claude Code"

- The six Agent Skills spec fields: `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`.
- Everything else in the table is Claude-Code-only: `when_to_use`, `argument-hint`, `arguments`, `disable-model-invocation`, `user-invocable`, `disallowed-tools`, `model`, `effort`, `context`, `agent`, `background`, `hooks`, `paths`, `shell`.
- claude.ai uploads, the Skills API, and `package_skill.py` accept only the six; any other key is a hard error (`Unexpected key(s) in SKILL.md frontmatter: ...`), not a silent ignore. Enabling a personal skill on a claude.ai account is an upload, so the same rule applies.
- Claude-Code-only body features such as dynamic context injection do not work in claude.ai chat or the API.

## Invocation control
Source: https://code.claude.com/docs/en/skills.md § "Control who invokes a skill"

Two frontmatter fields split who may trigger a skill: the user by `/name`, or the model through the Skill tool.

### Who can invoke

Source: https://code.claude.com/docs/en/skills.md § "Control who invokes a skill"

| Frontmatter | User `/name` | Model invocation | Context loading |
| :-- | :-- | :-- | :-- |
| default | Yes | Yes | Description always listed; body loads on invoke |
| `disable-model-invocation: true` | Yes | No | Description not listed; body loads when the user invokes |
| `user-invocable: false` | No | Yes | Description always listed; body loads on invoke |

- Intended use: `disable-model-invocation` for side-effecting or timing-sensitive workflows (`/commit`, `/deploy`, `/send-slack-message`); `user-invocable: false` for background knowledge that is not a meaningful user action.
- If the model tries to invoke a `disable-model-invocation` skill anyway, Claude Code blocks the call and tells the model not to reproduce the skill's steps some other way; the expected outcome is the model suggesting the user run the command.
- Preloaded skills in subagents differ: their full content is injected at subagent startup.

### Visibility and access interplay

Source: https://code.claude.com/docs/en/skills.md § "Restrict Claude's skill access"

- `user-invocable: false` does not stop the model. Only `disable-model-invocation: true` keeps the model from invoking via the Skill tool, and it removes the skill from the model's context entirely.
- Some built-in commands are reachable through the Skill tool (`/init`, `/security-review`); others such as `/compact` are not.

## Tool grants and restrictions
Source: https://code.claude.com/docs/en/skills.md § "Pre-approve tools for a skill"; https://code.claude.com/docs/en/skills.md § "Restrict Claude's skill access"

Three mechanisms: a per-turn grant, a per-turn removal, and `Skill(...)` permission rules.

### allowed-tools

Source: https://code.claude.com/docs/en/skills.md § "Pre-approve tools for a skill"

- Grants listed tools without a permission prompt for the turn that invokes the skill. The grant ends when the user sends the next message, even though skill content stays in context. Re-invoking re-applies it for that turn.
- It is a grant, not a restriction: all tools remain callable and normal permission settings govern unlisted tools.
- For session-wide pre-approval, use allow rules in permission settings instead.
- Trust: workspace trust does not gate `allowed-tools`. A project skill's grant applies whenever the skill is invoked, including a `-p` run in a never-trusted folder. The source's advice is to review checked-in skills' `allowed-tools` before running Claude Code in a repo.
- Deny and ask rules still override `allowed-tools` (stated under injected-command permission checks).
- Example pattern from the source: a `commit` skill with `disable-model-invocation: true` and `allowed-tools: Bash(git add *) Bash(git commit *) Bash(git status *)`.

### disallowed-tools

Source: https://code.claude.com/docs/en/skills.md § "Pre-approve tools for a skill"; https://code.claude.com/docs/en/skills.md § "Frontmatter reference"

- Removes tools from the available pool while the skill is active; clears on the next user message.
- Suggested use: autonomous skills that must never call a tool, such as `AskUserQuestion` in a background loop.
- Like deny rules, cannot remove `EndConversation` while any other tool remains.
- For a block across all skills and prompts, use deny rules in permission settings.

### Skill(name) permission rules

Source: https://code.claude.com/docs/en/skills.md § "Restrict Claude's skill access"

| Rule | Effect |
| :-- | :-- |
| `Skill` in deny | Disables all skills for the model |
| `Skill(name)` | Exact match |
| `Skill(name *)` | Prefix match with any arguments |

- A deny rule naming an alias or unqualified name still blocks: `Skill(review)` blocks bundled `/code-review` via its `/review` alias; `Skill(deploy)` blocks a nested `apps/web:deploy` (the nested case fixed in v2.1.260).
- An allow rule matches only the skill's own name and the name in the model's invocation.

## Settings controls
Source: https://code.claude.com/docs/en/skills.md § "Override skill visibility from settings"

Settings can change skill visibility without editing `SKILL.md`.

### skillOverrides

Source: https://code.claude.com/docs/en/skills.md § "Override skill visibility from settings"

Settings key mapping skill name to state; absent means `"on"`.

| Value | Listed to the model | In `/` menu |
| :-- | :-- | :-- |
| `"on"` | Name and description | Yes |
| `"name-only"` | Name only | Yes |
| `"user-invocable-only"` (shown as `user-only` in `/skills`) | Hidden | Yes |
| `"off"` | Hidden | Hidden |

- `/skills` menu edits it: `Space` cycles, `Esc` saves to `.claude/settings.local.json`.
- v2.1.199+: `"off"` also hides the skill from Remote Control and Agent SDK command lists; invoking it by full name returns the `skillOverrides` error.
- Aliases (e.g. `checkup` for `/doctor`) are honored only in managed settings or a `--settings` file, can only restrict further, and a managed entry under the real name wins. In user, project, and local settings, entries match skill names only.
- Plugin skills are not affected; manage them through `/plugin`.

### Other skill-related settings and env vars named by the source

Source: https://code.claude.com/docs/en/skills.md § "Skill descriptions are cut short"; https://code.claude.com/docs/en/skills.md § "Inject dynamic context"; https://code.claude.com/docs/en/skills.md § "Bundled skills"

| Name | Kind | Effect |
| :-- | :-- | :-- |
| `disableBundledSkills` | setting | Turns bundled skills off |
| `disableSkillShellExecution` | setting | Replaces injected commands with `[shell command execution disabled by policy]` |
| `syncClaudeAiSkills` | setting | `false` stops claude.ai sync |
| `skillListingBudgetFraction` | setting | Listing budget as a fraction of context window (default 1%) |
| `skillListingMaxDescChars` | setting | Per-entry description cap (default 1,536) |
| `SLASH_COMMAND_TOOL_CHAR_BUDGET` | env var | Fixed character budget for the listing |
| `CLAUDE_CODE_SYNC_SKILLS` | env var | `1` makes non-interactive runs wait for synced skills |
| `DISABLE_DOCTOR_COMMAND` | env var | Hides `/doctor` |

## Arguments and substitutions
Source: https://code.claude.com/docs/en/skills.md § "Available string substitutions"; https://code.claude.com/docs/en/skills.md § "Pass arguments to skills"

Placeholders in the body (and some in `allowed-tools`) are replaced at render time.

### Available string substitutions

Source: https://code.claude.com/docs/en/skills.md § "Available string substitutions"

| Token | Expands to |
| :-- | :-- |
| `$ARGUMENTS` | Full argument string as typed |
| `$ARGUMENTS[N]` / `$N` | 0-based positional argument, shell-style quoting |
| `$name` | Named argument from `arguments` frontmatter |
| `${CLAUDE_SESSION_ID}` | Current session ID |
| `${CLAUDE_EFFORT}` | Current effort level (ultracode reports as `xhigh`) |
| `${CLAUDE_SKILL_DIR}` | Directory holding this `SKILL.md`; for plugin skills, the skill's subdirectory, not the plugin root |
| `${CLAUDE_PROJECT_DIR}` | Project root, same value hooks and MCP servers get (v2.1.196+) |
| `${CLAUDE_PLUGIN_ROOT}` | Plugin install dir; plugin skills only |
| `${CLAUDE_PLUGIN_DATA}` | Plugin persistent data dir that survives updates; plugin skills only |

- `${CLAUDE_SKILL_DIR}` and `${CLAUDE_PROJECT_DIR}` (and, in plugins, `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}`) are substituted both in the body and in Bash rules inside `allowed-tools`. Using the same variable in both lets a bundled script run with no prompt, e.g. `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/render.sh *)`.
- Missing indexed argument: placeholder stays literal. Missing named argument: expands to empty string.
- Argument values containing `$1` or `$ARGUMENTS` are inserted literally, not re-expanded; `${CLAUDE_*}` variables are still replaced afterward.
- Escape: `\$1.00` keeps a literal `$` before a digit, `ARGUMENTS`, or a declared name. `\\$1` still expands. Backslash never suppresses `${CLAUDE_*}`.

### Passing arguments and stacking

Source: https://code.claude.com/docs/en/skills.md § "Pass arguments to skills"

- If no placeholder receives an argument, Claude Code appends `ARGUMENTS: <input>` to the content. A named placeholder counts as receiving one even when empty; an unfilled indexed one does not.
- Stacking (v2.1.199+): `/write-tests /fix-issue 123` loads both and passes `123` to each. Up to the first skill plus five more expand. Expansion stops at the first token that is not an inline user-invocable skill; forked skills (for example `/code-review` from v2.1.218) and `/loop` end the run, and the rest becomes argument text.

## Dynamic context injection
Source: https://code.claude.com/docs/en/skills.md § "Inject dynamic context"

Shell commands embedded in the body run at render time and their output is inlined.

### Inline and fenced forms

Source: https://code.claude.com/docs/en/skills.md § "Inject dynamic context"

- `` !`command` `` runs before the content reaches the model; output replaces the placeholder.
- Recognized only at line start or after whitespace. `` KEY=!`cmd` `` stays literal and does not run.
- Multi-line: a fenced block opened with ` ```! `.
- Substitution is a single pass over the original file; command output is not re-scanned for more placeholders.
- `disableSkillShellExecution: true` disables this for user, project, plugin, and additional-directory skills and commands; bundled and managed skills are unaffected. Most useful in managed settings.
- Never runs locally for claude.ai synced skills (v2.1.228+), regardless of settings.
- Putting `ultrathink` anywhere in skill content requests deeper reasoning.

### How injected commands run (shell)

Source: https://code.claude.com/docs/en/skills.md § "How injected commands run"

| `shell` and environment | Runs through |
| :-- | :-- |
| `shell: powershell`, PowerShell tool enabled | PowerShell tool |
| `shell: bash`, bash unavailable (Windows without Git Bash) | Invocation fails before any command runs: ``Skill <name> requires bash (`shell: bash` in frontmatter) but Git Bash was not found`` |
| Anything else | Bash tool if bash exists, else PowerShell tool |

- PowerShell tool availability (from the `shell` field row): on by default on Windows without Git Bash and with Git Bash for claude.ai and Console accounts; needs `CLAUDE_CODE_USE_POWERSHELL_TOOL=1` on Bedrock, Google Cloud Agent Platform, Microsoft Foundry, and on macOS, Linux, WSL; `0` turns it off.
- Working directory is the session shell's current directory, which moves with Claude's `cd`. Use `${CLAUDE_SKILL_DIR}` or `${CLAUDE_PROJECT_DIR}` for stable paths.
- Default bash merges stderr into stdout, so stderr appears in the injected text.
- Timeout is the Bash tool default of 2 minutes. If the tool backgrounds a timed-out command, the skill still renders with a note naming the task and output file; if the command is never auto-backgrounded, it is killed and the invocation aborts.
- Large output arrives as a file path plus preview.
- The PowerShell tool applies the same timeout, backgrounding, and output ceiling.

### Failure aborts the invocation

Source: https://code.claude.com/docs/en/skills.md § "When an injected command fails"

- Any failing injected command aborts the whole invocation; the model never sees the skill content. Message: `Shell command failed for pattern "..."`, with output under `[stderr]`.
- Bash: any non-zero exit fails, except exit 1 from designated search/comparison commands. Exit 2+ always fails.
- `shell: powershell`: a different carve-out set that includes `grep` and `git diff` but not `find` or `diff`.
- For a check script that exits 1 on findings under bash, append `|| true`.

### Permission checks on injected commands

Source: https://code.claude.com/docs/en/skills.md § "Permission checks on injected commands"

- Injected commands never prompt. Each is checked against permission rules first.
- A deny match aborts with `Shell command permission check failed for pattern "..."`.
- Outside auto mode, any result other than allow (including an ask rule) aborts the same way. Pre-approve with `allowed-tools` to avoid this; deny and ask rules still override `allowed-tools`.
- In auto mode, a command needing approval does not abort; the skill loads with an instruction for the model to run the command itself, which then goes through auto mode's checks. It still aborts in a forked skill that sets `agent`, and in sessions lacking the relevant shell tool.

## Running a skill in a subagent

Source: https://code.claude.com/docs/en/skills.md § "Run skills in a subagent"

- `context: fork` starts a new subagent of the `agent` type (default `general-purpose`; options include `Explore`, `Plan`, or any `.claude/agents/` type) with the skill content as its prompt.
- The subagent does not see conversation history. It is not a conversation fork; if history matters, fork the conversation instead.
- What it does get:

| Approach | System prompt | Task | Also loads |
| :-- | :-- | :-- | :-- |
| Skill with `context: fork` | From the agent type | SKILL.md content | CLAUDE.md per the agent's startup context |
| Subagent with `skills` field | Subagent's Markdown body | Delegation message | Preloaded skills plus CLAUDE.md per startup context |

- Built-in `Explore` and `Plan` skip CLAUDE.md and git status, so `agent: Explore` sees only SKILL.md content and the agent's system prompt.
- The `agent` type sets model, tools, and permissions; the result is summarized back into the main conversation.
- Runs in the background by default; `background: false` waits in the invoking turn. It also waits under `-p` / Agent SDK, `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`, a re-invocation while the same skill is still running, and scheduled-task firing.
- A backgrounded fork gets the narrower background-subagent tool set; use `background: false` for the full set.
- Background fork edits are outside checkpoints; `/rewind` does not undo them.
- Only useful for skills with an explicit task; pure guidelines yield no meaningful output.

## Content lifecycle and compaction

Source: https://code.claude.com/docs/en/skills.md § "Skill content lifecycle"; https://code.claude.com/docs/en/skills.md § "Skill descriptions are cut short"

- Before invocation, only names and descriptions are in context (subject to the listing budget).
- On invocation, the rendered `SKILL.md` enters the conversation as one message and stays across later turns. The file is not re-read on later turns, so write standing instructions, not one-shot steps.
- Instructions persist; the `allowed-tools` grant does not (it clears on the next user message).
- Re-invocation with identical rendered content adds a short "already loaded" note; different content (new args or new `!` output) appends the full content again.
- Auto-compaction re-attaches the most recent invocation of each skill after the summary, first 5,000 tokens each, 25,000 tokens combined, filled from most recently invoked. Older skills can be dropped entirely.
- If a skill seems to stop working, the content is usually still present; strengthen the description and instructions, use hooks for deterministic enforcement, or re-invoke after compaction.
- Listing budget: 1% of the context window by default. On overflow, descriptions are shortened starting with the least-invoked skills; every name stays listed. `/context` shows post-budget size (v2.1.196+). `/doctor` estimates listing cost; `--debug` shows an overflow warning.

## Diagnostics
Source: https://code.claude.com/docs/en/skills.md § "Find unused skills"; https://code.claude.com/docs/en/skills.md § "Troubleshooting"

Tools for finding dead weight, broken frontmatter, and triggering problems.

### /skill-doctor

Source: https://code.claude.com/docs/en/skills.md § "Find unused skills"

- Reports each skill's context cost and usage; flags listed skills never invoked and where to turn them off; lists plugins not used recently.
- Excludes bundled and enterprise skills.
- Interactive: opens the `/plugin` manager's Stats tab. With `-p`: prints text.
- Requires v2.1.252+ and feature-flag fetching. Over Remote Control it replies `Skill usage reports are not available on this connection.`

### Troubleshooting and claude plugin validate

Source: https://code.claude.com/docs/en/skills.md § "Skill not triggering"; https://code.claude.com/docs/en/skills.md § "Skill triggers too often"; https://code.claude.com/docs/en/skills.md § "Personal skills disappeared"

- Not triggering: check description keywords, ask `What skills are available?`, rephrase, or invoke `/skill-name`.
- Malformed YAML: body loads with empty metadata, so `/name` works but description matching does not. `--debug` shows the parse error.
- `claude plugin validate <dir>` finds `SKILL.md` files whose frontmatter does not parse, e.g. `claude plugin validate .claude/skills` or `claude plugin validate ~/.claude/skills` (v2.1.233+).
- Plugin skills: measure trigger rate with a `tool_used: Skill` grader under `claude plugin eval`.
- Triggers too often: narrow the description or add `disable-model-invocation: true`.
- Vanished personal skills: look in `~/.claude/skills/.trash/` (retention default 30 days). Before v2.1.280 a `manifest.json` in `~/.claude/skills/` caused listed folders to be moved there.

### Evaluating a skill

Source: https://code.claude.com/docs/en/skills.md § "Evaluate and iterate on a skill"; https://code.claude.com/docs/en/skills.md § "Run evals with skill-creator"

- Measure two things separately: whether the model invokes the skill on the right prompts, and whether the output is right when it does.
- Method: run realistic prompts in fresh sessions with the skill enabled and disabled, and compare.
- `claude plugin eval` does this for plugin skills, with graders and a non-zero exit below threshold for CI gating.
- The `skill-creator` plugin (`/plugin install skill-creator@claude-plugins-official`) runs the loop in-session using `evals/evals.json`; its format is not interchangeable with `claude plugin eval`.

## Authoring guidance
Source: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Core principles"; https://code.claude.com/docs/en/skills.md § "Types of skill content"

Condensed from the platform best-practices page, with Claude Code specifics where they differ.

### Conciseness

Source: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Concise is key"; https://code.claude.com/docs/en/skills.md § "Types of skill content"

- Context is shared with the system prompt, history, other skills' metadata, and the request. Only metadata preloads, but once loaded every body token competes.
- Assume the model is already capable; include only what it lacks and question whether each paragraph earns its tokens.
- Claude Code adds: a loaded body stays in context across turns, so each line is a recurring cost. State what to do, not why.
- Content types: reference content (conventions, runs inline alongside work) vs task content (step-by-step actions, often user-invoked with `disable-model-invocation: true`).

### Degrees of freedom

Source: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Set appropriate degrees of freedom"

| Freedom | Form | Use when |
| :-- | :-- | :-- |
| High | Prose instructions | Many valid approaches; context-dependent decisions |
| Medium | Pseudocode or parameterized script | A preferred pattern exists; some variation OK |
| Low | Exact script, few or no parameters | Fragile operations, consistency critical, fixed sequence |

The source's analogy: a narrow bridge between cliffs needs exact guardrails; an open field needs only a direction.

### Naming

Source: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Naming conventions"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "YAML frontmatter requirements"

- Platform validation: `name` at most 64 chars, lowercase letters, digits, hyphens; no XML tags; no reserved words `anthropic` or `claude`.
- Prefer gerund form (`processing-pdfs`); noun phrases or action forms are acceptable. Avoid vague (`helper`, `utils`), generic (`data`, `files`), or inconsistent names.
- Note: the platform page calls `name` and `description` required; Claude Code treats all frontmatter as optional.

### Descriptions

Source: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Writing effective descriptions"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "YAML frontmatter requirements"

- Platform validation: non-empty, at most 1,024 chars, no XML tags. (Claude Code's listing cap is 1,536 chars for `description` plus `when_to_use`.)
- Write in third person; the description is injected into the system prompt.
- State both what it does and when to use it, with concrete trigger terms. The model picks among possibly 100+ skills using this text.
- Avoid vague descriptions such as "Helps with documents".

### Progressive disclosure

Source: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Progressive disclosure patterns"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Avoid deeply nested references"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Structure longer reference files with table of contents"; https://code.claude.com/docs/en/skills.md § "Add supporting files"

- `SKILL.md` is an overview that points to detail files. Keep its body under 500 lines; split when approaching that.
- Patterns: high-level guide with links; domain-split reference files; basic content with conditional links to advanced material.
- Keep references one level deep from `SKILL.md`; nested references may be only partially read (e.g. previewed with `head`).
- Reference files over 100 lines should open with a table of contents.
- Link each supporting file from `SKILL.md` and say what it contains and when to load it. Scripts are executed, not loaded.

### Workflows, feedback loops, content

Source: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Use workflows for complex tasks"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Implement feedback loops"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Avoid time-sensitive information"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Use consistent terminology"

- Break complex tasks into numbered steps; for long ones, give a copyable checklist.
- Validate, fix, repeat: loops with a validator (script or reference doc) markedly improve output.
- No date-conditional instructions; move legacy material to an "old patterns" section.
- Pick one term per concept and use it throughout.
- Other patterns: strict or flexible output templates; input/output example pairs; conditional workflow branches.

### Evaluation first

Source: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Build evaluations first"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Develop Skills iteratively with Claude"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Test with all models you plan to use"

- Write evaluations before extensive documentation: find gaps without a skill, build three scenarios, measure a baseline, write the minimum to pass, iterate.
- The platform page says there is no built-in runner for its example eval JSON (fields `skills`, `query`, `files`, `expected_behavior`). Claude Code's `claude plugin eval` and skill-creator are separate tools described above.
- Iterate with two instances: one refines the skill, a fresh one uses it on real tasks; feed observed failures back.
- Test with every model you intend to use; Haiku may need more detail than Opus.
- Watch how the model navigates files: unexpected order, missed links, over-read sections, never-read files.

### Scripts vs instructions

Source: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Solve, don't defer"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Provide utility scripts"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Create verifiable intermediate outputs"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Runtime environment"

- Bundled scripts beat generated code: more reliable, save tokens and time, consistent. Only their output costs context.
- Say explicitly whether to execute a script or read it as reference; execution is usually preferred.
- Scripts should handle errors themselves rather than defer to the model, and justify every constant (no "voodoo constants").
- Plan-validate-execute: have the model write a structured plan file, validate it with a script, then apply. Use for batch, destructive, or high-stakes changes; make validator errors specific.
- Prefer scripts for deterministic operations.

### Anti-patterns and environment notes

Source: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Avoid Windows-style paths"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Avoid offering too many options"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "MCP tool references"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Avoid assuming tools are installed"; https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md § "Package dependencies"

- Use forward slashes in paths, even on Windows.
- Give one default approach with an escape hatch, not a menu of options.
- Refer to MCP tools by fully qualified `ServerName:tool_name`.
- State required packages and how to install them; do not assume availability. The platform page notes claude.ai can install from npm/PyPI while the Claude API has no network or runtime installs.

## Not found in source
Source: https://code.claude.com/docs/en/skills.md § "Control who invokes a skill"; https://code.claude.com/docs/en/skills.md § "Frontmatter reference"


- The exact text Claude Code sends the model when a `disable-model-invocation` skill is invoked by the model: the pinned source only says the call is blocked and the model is instructed not to reproduce the steps another way; it gives no verbatim message.
- Explicit types and defaults for every frontmatter field: the pinned source states defaults only for `name`, `description`, `disable-model-invocation`, `user-invocable`, `effort`, `agent`, `background`, and `shell`; entries marked "not stated" above are not given in the source.
