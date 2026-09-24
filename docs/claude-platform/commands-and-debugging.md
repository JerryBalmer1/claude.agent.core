---
verified: 2026-09-23
sources:
  - https://code.claude.com/docs/en/commands.md
  - https://code.claude.com/docs/en/debug-your-config.md
  - https://code.claude.com/docs/en/errors.md
scope: Built-in slash commands, the documented procedure for finding out why a Claude Code configuration surface did not take effect, and the error-reference entries that bear on hooks, permissions, settings, plugins, skills, subagents, and MCP.
---

# Commands and debugging

This file summarizes three Claude Code documentation pages as fetched on the verified date. It is
written for a reader who needs to check, reproducibly, whether an extension configuration (settings,
hooks, permissions, skills, subagents, plugins, MCP servers, CLAUDE.md) is actually live in a
session. Version numbers quoted below (for example v2.1.191) are the thresholds the source states;
they are not a claim about which version is installed anywhere.

Reading order: the command catalogue first, then the debug procedure, then the error reference.
Anything the sources do not say is listed at the end under "Not found in source".

## Command basics

Source: https://code.claude.com/docs/en/commands.md § "Commands"

- A command is recognized only at the start of a message; the rest of the message becomes its
  arguments.
- Exception (v2.1.199+): several skills can be chained at the start, for example
  `/skill-a /skill-b do XYZ`; every named skill loads and each receives the trailing text. The limit
  is six chained skills.
- A command sent while Claude is responding is queued until the turn ends. Some run immediately
  without interrupting: the source names `/status`, `/tasks`, `/usage`. In fullscreen rendering,
  dialog commands such as `/theme` and `/help` also open immediately (queued before v2.1.234).
- Typing `/` shows the commands available to you; typing more letters filters the list.

## How the catalogue is organized

Source: https://code.claude.com/docs/en/commands.md § "All commands"

- The page has one table of all commands. Most rows are built-in commands coded into the CLI.
- Rows tagged **Skill** are bundled skills: prompts handed to Claude, behaving like user-written
  skills. Rows tagged **Workflow** are bundled dynamic workflows that fan out to many subagents in
  the background.
- `/verify` runs only when invoked (before v2.1.215 Claude could run it unprompted).
  `/deep-research` likewise runs only when invoked (before v2.1.218 Claude could start it).
- Availability varies by platform, plan, and environment. Examples given: `/desktop` only on macOS
  and x64 Windows with a Claude subscription; `/upgrade` hidden on Enterprise plans.
- Argument notation: `<arg>` is required, `[arg]` is optional.

## Custom commands and skills

Source: https://code.claude.com/docs/en/commands.md § "All commands"; https://code.claude.com/docs/en/commands.md § "See also"; https://code.claude.com/docs/en/commands.md § "MCP prompts"

- The page sends readers who want their own commands to the skills page ("To add your own commands,
  see skills"; the See also list describes Skills as "create your own commands").
- `/reload-skills` re-scans "skill and command directories", so the source still speaks of command
  directories alongside skill directories.
- `/import` can bring "commands" from OpenAI Codex, Gemini CLI, or Cursor, alongside skills and
  subagents.
- MCP servers can expose prompts that appear as commands.
- The source does not state the mechanics of a merger between custom commands and skills (see
  "Not found in source").

## Command catalogue

Source: https://code.claude.com/docs/en/commands.md § "All commands"; https://code.claude.com/docs/en/commands.md § "Commands across a typical workflow"

Grouping below is ours; the source table is alphabetical. The marker **[inspect]** flags commands
that reveal or change the extension surface. **[Skill]** and **[Workflow]** mirror the source tags.

### Extension surface: inspect and reload

Source: https://code.claude.com/docs/en/commands.md § "All commands"

| Command | Purpose (paraphrased) | Notes |
| :-- | :-- | :-- |
| `/hooks` [inspect] | View hook configurations for tool events | The debug page says it lists every hook registered for the session, grouped by event |
| `/permissions` [inspect] | Manage allow, ask, deny rules; view rules by scope; manage working directories; review recent auto mode denials; edit auto mode classifier rules | Alias `/allowed-tools`. Mid-turn changes apply from Claude's next tool call (v2.1.234+) |
| `/skills` [inspect] | List available skills; filter; `t` sorts by token count; `Space`/`Enter` cycles a skill's visibility | Cannot cycle plugin skills, skills with `disable-model-invocation: true`, or skills with a `skillOverrides` entry in managed settings or `--settings` |
| `/reload-skills` [inspect] | Re-scan skill and command directories without restart | Reports how many skills are available, added, removed |
| `/skill-doctor` [inspect] | Show each skill's context cost and usage frequency | Needs v2.1.252+ and feature-flag fetching |
| `/agents` [inspect] | Since v2.1.198 only prints a reminder to ask Claude or edit `.claude/agents/` or `~/.claude/agents/` | v2.1.197 and earlier opened an interactive manager |
| `/list-agents` | List subagents, agent-team teammates, and sessions Claude can message | Alias `/peers`. v2.1.224+; only where cross-session messaging is enabled |
| `/plugin` [inspect] | Plugin menu, or subcommands such as `list`, `install`, `enable`, `disable` | Install summary says whether the plugin activated or `/reload-plugins` is needed |
| `/reload-plugins` [inspect] | Reload active plugins without restart; reports per-component counts and load errors | Skips with a warning if MCP tool set would change and invalidate prompt cache, unless `--force`. Non-interactive/SDK/desktop use needs v2.1.260+ and does not apply plugin MCP changes |
| `/mcp` [inspect] | Manage MCP connections and OAuth; `reconnect <server>`; `enable`/`disable <server>` or `all` | In `-p` with no argument prints a text status summary (v2.1.205+) |
| `/memory` [inspect] | Edit CLAUDE.md files, toggle auto memory, view auto memory entries | |
| `/context` [inspect] | Colored-grid view of context usage with optimization suggestions | `all` expands the per-item breakdown in fullscreen mode |
| `/status` [inspect] | Settings interface on the Status tab: version, model, account, connectivity; a `Session kind` row (v2.1.221+) | Runs mid-turn. The debug page adds that it shows active settings sources and whether managed settings apply |
| `/config` [inspect] | Settings interface; or `key=value` pairs set a setting directly | Alias `/settings`. `/config --help` lists accepted keys. `key=value` works in `-p`. It cannot turn on a setting that needs panel confirmation |
| `/workflows` | Progress view for dynamic workflows | |
| `/workflow-authoring` | [Skill] Reference for writing dynamic workflow scripts | |

### Diagnostics and reporting

Source: https://code.claude.com/docs/en/commands.md § "All commands"

| Command | Purpose (paraphrased) | Notes |
| :-- | :-- | :-- |
| `/doctor` [inspect] | [Skill] Setup checkup: install health (duplicate installs, `PATH`, unparseable settings files), unused skills/MCP/plugins vs context cost, slow hooks, newer version; CLAUDE.md dedupe and trimming | Alias `/checkup`. Reports first and asks before changing anything. Before v2.1.205 it was a read-only screen |
| `claude doctor` (shell) [inspect] | Read-only install and settings diagnostics without starting a session | Stated in the `/doctor` row and on the debug page |
| `/debug [description]` [inspect] | [Skill] Enable debug logging for the session and troubleshoot from the session debug log | Logging is off unless started with `claude --debug`; `/debug` captures only from that point on |
| `/heapdump` | Write a heap snapshot and memory breakdown to `~/Desktop` (or home dir) | Hidden from the menu; type in full. Share only the `-diagnostics.json`; the `.heapsnapshot` holds conversation and credentials |
| `/release-notes` | Changelog in a version picker | Output does not enter the conversation Claude sees |
| `/usage` | Session cost, plan limits, activity stats | Aliases `/cost`, `/stats` |
| `/insights` | HTML report analyzing recent local sessions | Not in cloud sessions |
| `/bug [report]` | Report a bug or share the conversation after a consent screen | |
| `/feedback [report]` | Product feedback; same dialog as `/bug` | |
| `/help` | Show help and available commands | |

### Settings, permissions, and environment

Source: https://code.claude.com/docs/en/commands.md § "All commands"

| Command | Purpose (paraphrased) |
| :-- | :-- |
| `/update-config [request]` | [Skill] Describe a settings change (allow a command, set an env var, add a hook) and Claude edits the matching `settings.json` |
| `/fewer-permission-prompts` | [Skill] Scan transcripts for read-only Bash/MCP calls and add an allowlist to project `.claude/settings.json` |
| `/auto-mode-setup` | Draft `autoMode.environment` entries and save to user settings (Pro/Max/Team; v2.1.228+, native Windows v2.1.233+) |
| `/sandbox` | Toggle sandbox mode on supported platforms |
| `/privacy-settings` | View and update privacy settings (Pro and Max) |
| `/remote-env` | Choose default cloud environment for CLI-started cloud sessions |
| `/setup-bedrock`, `/setup-vertex` | Provider wizards; hidden until `CLAUDE_CODE_USE_BEDROCK=1` / `CLAUDE_CODE_USE_VERTEX=1` |
| `/add-dir <path>` | Add a working directory. Most `.claude/` configuration is not discovered from the added directory. Network paths refused. Fires `DirectoryAdded` hooks |
| `/cd <path>` | Move the session to another working directory, keeping the conversation |

### Context and memory

Source: https://code.claude.com/docs/en/commands.md § "All commands"

| Command | Purpose (paraphrased) |
| :-- | :-- |
| `/init` | Create a starter `CLAUDE.md`. `CLAUDE_CODE_NEW_INIT=1` gives an interactive flow covering skills, hooks, personal memory. Offers `/import` if Codex/Gemini config is found |
| `/import [codex\|gemini\|cursor] [--dry-run] [--yes]` | Import instruction files, MCP servers, commands, subagents, skills from other tools. v2.1.213+ (Cursor v2.1.265+). Not on Bedrock/Vertex/Foundry/Claude Platform on AWS, gateways, or with flag fetching off |
| `/compact [instructions]` | Summarize conversation to free context |
| `/autocompact [auto\|<tokens>]` | Set the auto-compact window; saved to user settings |
| `/clear [name]` | New conversation with empty context; project memory kept |

### Session and conversation control

Source: https://code.claude.com/docs/en/commands.md § "All commands"

| Command | Purpose (paraphrased) |
| :-- | :-- |
| `/resume [session]` | Resume by ID/name or open a picker. Alias `/continue` |
| `/branch [name]` | Branch the conversation here and switch into the branch |
| `/fork [prompt]` | Copy the conversation into a new background session |
| `/subtask <task>` | Spawn a forked background subagent that inherits the conversation (v2.1.212+) |
| `/background [prompt]` | Detach the session as a background agent. Alias `/bg` |
| `/stop` | Stop the attached background session |
| `/tasks` | View and manage background work. Alias `/bashes` |
| `/rewind` | Roll back conversation and/or code to a checkpoint. Aliases `/checkpoint`, `/undo` |
| `/rename [name]`, `/recap`, `/btw [question]`, `/goal [condition\|clear]`, `/plan [description]` | Rename session; one-line summary; side question outside history; keep working toward a condition; enter plan mode |
| `/export [filename]`, `/copy [N]`, `/diff` | Export conversation text; copy a response; review working-tree changes |
| `/exit` | Exit (detaches in a background session). Alias `/quit` |
| `/teleport`, `/remote-control`, `/desktop`, `/mobile` | Pull a cloud session here (`/tp`); expose session to Remote Control (`/rc`); continue in desktop app (`/app`); mobile QR (`/ios`, `/android`) |

### Model, output, and interface

Source: https://code.claude.com/docs/en/commands.md § "All commands"

| Command | Purpose (paraphrased) |
| :-- | :-- |
| `/model [model]` | Switch model and save as default; `s` in the picker switches for this session only |
| `/effort [level\|auto\|status]` | Set effort level; `max` and `ultracode` are session-only |
| `/fast [on\|off]`, `/advisor [model\|off]` | Toggle fast mode; enable/disable the advisor tool |
| `/output-style [style]` | List or switch output styles (v2.1.269+) |
| `/theme`, `/color`, `/tui`, `/focus`, `/scroll-speed`, `/statusline`, `/keybindings`, `/terminal-setup`, `/voice` | Terminal UI, renderer, status line, key bindings, dictation |

### Review, build, and other bundled skills

Source: https://code.claude.com/docs/en/commands.md § "All commands"

| Command | Purpose (paraphrased) |
| :-- | :-- |
| `/code-review [...]` | [Skill] Review diff, PR, branch or path for correctness bugs; `--fix`, `--comment`; `ultra` runs in the cloud. `/review` is an alias |
| `/ultrareview`, `/security-review` | Cloud multi-agent review (alias of `/code-review ultra`); security review of branch vs origin default branch |
| `/simplify [target]` | [Skill] Cleanup review with four parallel agents; not a bug hunt |
| `/batch <instruction>` | [Skill] Decompose a large change into 5 to 30 units, one background subagent per worktree |
| `/verify`, `/run`, `/run-skill-generator` | [Skill] Build, launch and observe the app; teach `/run` and `/verify` via a per-project skill |
| `/loop [interval] [prompt]` | [Skill] Repeat a prompt while the session is open |
| `/claude-api`, `/dataviz`, `/design`, `/design-sync` | [Skill] API reference material; chart design; UI mockups; design-system sync |
| `/deep-research <question>` | [Workflow] Fan-out web research with a cited report |
| `/schedule`, `/autofix-pr` | Cloud routines (alias `/routines`); cloud session that fixes a PR on CI failure or review |

### Account and integrations

Source: https://code.claude.com/docs/en/commands.md § "All commands"

`/login`, `/logout`, `/upgrade`, `/usage-credits`, `/rate-limit-options`, `/passes`,
`/install-github-app`, `/install-slack-app`, `/web-setup`, `/chrome`, `/ide`, `/artifacts`,
`/team-onboarding`, `/design-login`, `/powerup`, `/stickers`, `/radio`. None of these inspects the
extension surface.

### Removed commands

Source: https://code.claude.com/docs/en/commands.md § "All commands"

| Command | Status |
| :-- | :-- |
| `/pr-comments` | Removed in v2.1.91 |
| `/vim` | Removed in v2.1.92; use `/config` editor mode |
| `/ultraplan` | Removed; use plan mode |

### Menu matching and hidden commands

Source: https://code.claude.com/docs/en/commands.md § "How the command menu matches what you type"

- Top suggestion is highlighted only when typed letters match a name or alias from its start or a
  word start, ignoring `:`, `_`, `-` (v2.1.236+).
- After a typo nothing is highlighted; `Enter` submits the text as typed and yields `Unknown command`.
- Unavailable commands are omitted from the menu; most return `Unknown command` if submitted. Some
  answer with their own availability or policy message instead.
- Hidden commands (example `/heapdump`) never appear for a partial name; they appear and run only
  when the full name is typed.

## Debug procedure: why did my configuration not take effect

Source: https://code.claude.com/docs/en/debug-your-config.md § "Debug your configuration"

The page names three usual causes: the file did not load, it loaded from an unexpected location, or
another file overrode it. Installation, login and connectivity problems belong to a different page.
The steps below follow the page's order.

### Step 1: see what loaded into context

Source: https://code.claude.com/docs/en/debug-your-config.md § "See what loaded into context"

Run `/context` first. It breaks the window into: system prompt, system tools, MCP tools, custom
subagents (with the source each loaded from), memory files, skills, and conversation messages. Its
skills section includes bundled skills, which `/skills` does not list.

Follow-up commands per surface:

| Command | What it shows |
| :-- | :-- |
| `/memory` | Memory file locations in user and project scopes, editor access, auto memory folder and toggle |
| `/skills` | Available skills from project, user, and plugin sources |
| `/hooks` | Active hook configurations |
| `/mcp` | Connected MCP servers and status |
| `/permissions` | Resolved allow and deny rules currently in effect |
| `/doctor` | Install health, invalid settings files, unused extensions, duplicate subagent names in one directory, derivable CLAUDE.md content, with proposed fixes |
| `/debug [issue]` | Turns on debug logging and asks Claude to diagnose from the log and settings paths |
| `/status` | Active settings sources, including whether managed settings are in effect |

Interpretation rules from the source:

- A memory file missing from `/context`: check its location. Subdirectory `CLAUDE.md` files load on
  demand when Claude reads a file in that directory with the Read tool, not at session start.
- A file that loaded but is not followed: the problem is the wording (vague, conflicting, or too
  long), not loading.
- CLAUDE.md is guidance. Permissions and hooks are enforcement. Hard boundaries belong in
  permissions or hooks.

### Step 2: check resolved settings

Source: https://code.claude.com/docs/en/debug-your-config.md § "Check resolved settings"

- Scopes: managed, user, project, local. Managed applies first when present. Among the others the
  closer scope wins: local over project over user.
- Command-line flags and environment variables form a further override layer for some settings.
- An ignored value is usually overridden by another scope or an env var.
- `claude doctor` (shell) finds invalid settings files, read-only, no session.
- `/doctor` (in session) runs the full checkup and asks before applying fixes.
- `/status` shows active settings sources and whether managed settings are in effect.

### Step 3: check MCP servers

Source: https://code.claude.com/docs/en/debug-your-config.md § "Check MCP servers"

`/mcp` shows each configured server, connection status, and project approval state.

| Symptom in `/mcp` | Cause per source | Next step |
| :-- | :-- | :-- |
| Server disabled | Project `.mcp.json` server needs one-time approval; prompt was dismissed | Approve from `/mcp` |
| Failed | Often relative paths in `command`/`args`, which resolve against the launch directory, not `.mcp.json` | Use absolute paths |
| Connected, zero tools | Started but returns no tool list | **Reconnect**; then `claude --debug=mcp` and read server stderr in `~/.claude/debug/<session-id>.txt` |

### Step 4: check hooks

Source: https://code.claude.com/docs/en/debug-your-config.md § "Check hooks"

1. Run `/hooks`. It lists every hook registered for the session, grouped by event.
2. Hook absent: it is not being read. Hooks must sit under the `"hooks"` key of a settings file; a
   standalone file is not read (plugins are the exception, see common causes).
3. Hook present but not firing: inspect the `matcher`.
   - Must be one string. `|` separates tool names (`"Edit|Write"`). `,` is equivalent from v2.1.191;
     earlier versions treated a comma as regex and never matched.
   - A misspelled tool name matches nothing and fails silently.
   - An array value is a schema error. For user, project, or local settings, Claude Code shows a
     settings error notice and rejects the whole file; `claude doctor` reports it; no hook from that
     file appears in `/hooks`. In managed settings, only the `hooks` key of that file is dropped; the
     file's other settings still apply and `claude doctor` lists the dropped key.
4. Live reload: edits to `settings.json` take effect in the running session after a short
   file-stability delay, no restart, including a `.claude/` folder created after session start
   (v2.1.257+; before that such folders were not detected). If `/hooks` still shows the old
   definition a few seconds after saving, run `/hooks` again.
5. Still not firing: start with `claude --debug` and trigger the tool call. The debug log records
   each event, the matchers checked, and the hook's exit code and output.

### Step 5: test against a clean configuration

Source: https://code.claude.com/docs/en/debug-your-config.md § "Test against a clean configuration"

- `claude --safe-mode` disables CLAUDE.md, skills, plugins, hooks, MCP servers, custom commands and
  agents. Auth, model selection, built-in tools, and permissions work normally.
- Safe mode still applies managed hooks and managed settings policy. Managed plugins, skills,
  CLAUDE.md and MCP servers are turned off.
- Problem gone in safe mode: one of the disabled surfaces is the cause; bisect with the steps above.
- For a fully clean run: set `CLAUDE_CONFIG_DIR` to an empty directory and launch from a directory
  with no `.claude`, `.mcp.json`, or `CLAUDE.md`. First launch shows first-run screens (theme
  selection), which confirms the clean directory is in use; onboarding state is saved there.
- Even then, managed settings still apply (MDM profiles, registry policy, `managed-settings.json` are
  read from outside the config dir; server-managed settings are fetched again once logged in). A
  fresh login is required.
- Problem gone in the clean run: reintroduce real `~/.claude` or project `.claude` files one at a time.
  Problem persists: check `/status` for managed settings and look for relevant environment variables.

### Common causes table

Source: https://code.claude.com/docs/en/debug-your-config.md § "Check common causes"

| Symptom | Cause | Fix |
| :-- | :-- | :-- |
| Hook never fires | `matcher` is a JSON array | Single string with `\|` |
| Hook never fires | `,` separator before v2.1.191 | Use `\|` or upgrade |
| Hook never fires | Lowercase tool name (`"bash"`) | Matching is case-sensitive: `Bash`, `Edit`, `Write`, `Read` |
| Hook never fires | Hooks in a standalone file | No standalone hooks file for user/project; use `"hooks"` in `settings.json`. Only plugins load `hooks/hooks.json` |
| Global permissions, hooks, env ignored | Put in `~/.claude.json` | That file is app state and UI toggles; use `~/.claude/settings.json` |
| `settings.json` value ignored | Same key in `settings.local.json` | Local overrides project; both override `~/.claude/settings.json` |
| Skill missing from `/skills` | File at `.claude/skills/name.md` | Use `.claude/skills/name/SKILL.md` |
| Skill listed but never auto-invoked | `disable-model-invocation: true` or description mismatch | A "user-only" badge in `/skills` means Claude will not trigger it |
| Subdirectory CLAUDE.md ignored | Loads on demand | Loads when Claude Reads a file there, not on write/create or at launch |
| Subagent ignores CLAUDE.md | Built-in Explore and Plan skip it; custom agents skip it if `omitClaudeMd` is set | Restate in the prompt, remove `omitClaudeMd`, or put rules in the agent body |
| No cleanup at session end | No `SessionEnd` hook | Add one in `settings.json` |
| `.mcp.json` servers never load | File under `.claude/`, or top-level `servers` key | `.mcp.json` at repo root with `mcpServers` key |
| `mcpServers` in `settings.json` ignored | `settings.json` does not read that key | Use `.mcp.json` or `claude mcp add --scope user` |
| Project MCP server not shown | Approval prompt dismissed | Approve in `/mcp` |
| MCP server fails from some directories | Relative path in `command`/`args` | Absolute paths; `PATH` executables like `npx`, `uvx` are fine |
| MCP server lacks env vars | Not set in its entry; some vars stripped for subprocesses | Per-server `env` in `.mcp.json` |
| `Bash(rm *)` deny misses `/bin/rm`, `find -delete` | Bash rules match the literal command string | PreToolUse hook or sandbox for a hard guarantee |

## Error reference: how the page is organized

Source: https://code.claude.com/docs/en/errors.md § "Find your error"

- The page covers runtime messages; install-time errors live on the install troubleshooting page.
- Errors apply across CLI, Desktop app, and cloud sessions, except "Wrapper and IDE errors", which the
  launching program prints.
- Start with the "Find your error" table: it maps the literal message text to a section. Then read
  that section's **What to do** list. Many entries end with a "Before v2.1.x" note describing older
  behavior.
- Top-level categories, in page order: Automatic retries; Server errors; Usage limits;
  Authentication errors; Network and connection errors; Request errors; Installation errors;
  Command-line errors; Plugin errors; Tool errors; Background session errors; Wrapper and IDE errors;
  Rewind warnings and errors; Session saving warnings; Configuration warnings; Responses seem lower
  quality than usual; Report an error.
- Configuration warnings are mostly written to stderr at startup, not into the conversation; an
  entry says when it appears elsewhere (debug log, startup notice, request time).

### Where hook and other failures are not covered

Source: https://code.claude.com/docs/en/errors.md § "Report an error"

The page defers some components to other guides: MCP connect/auth failures to the MCP page, hook
script failures or hook blocks to "Debug hooks" on the hooks page, install permission errors to the
install page. Otherwise: `/feedback`, `claude doctor` or `/doctor`, the status page, GitHub issues.

### Settings and permission-rule errors

Source: https://code.claude.com/docs/en/errors.md § "Configuration warnings"; https://code.claude.com/docs/en/errors.md § "Command-line errors"

| Message (short) | Cause | Fix |
| :-- | :-- | :-- |
| Workspace has not been trusted | Project `permissions.allow` or `permissions.additionalDirectories` in `.claude/settings.json` or `settings.local.json` ignored without workspace trust; `deny`/`ask` unaffected | Accept trust dialog once interactively, or set `projects[...].hasTrustDialogAccepted` in `~/.claude.json` (under `-p` no dialog is shown, so this is the setting to use) |
| Malformed Tool(content) rule | Rule not shaped `Tool` or `Tool(content)` | Rule is skipped and listed in the invalid-settings dialog and `claude doctor`; rewrite it. Inner parentheses are literal |
| Is not matched by file permission checks | `Write`/`NotebookEdit`/`MultiEdit`/`Glob` path rules are never consulted | Use `Edit(path)` or `Read(path)`; bare tool names are fine |
| Has a wildcard before the rest of the command | Bash allow rule with `*` before the subcommand, broader than intended | Rule kept as-is; narrow it or move `*` after the subcommand |
| crossSessionInbound must be one of accept, hold, refuse | Unrecognized value | Ignored (held) in user/project/local/`--settings`; treated as `refuse` in managed settings |
| Managed settings document could not be parsed | A managed document is not a JSON object | Exit 1 at startup, fail closed, even under `claude doctor`; an empty file counts as `{}` |
| Remote managed settings failed to load | Server-managed fetch failed | Uses cached policy or none; check `/status`, `claude doctor` |
| Managed settings were not approved | Security approval dialog declined | Exits; dialog reappears next start |
| Settings file exceeds the 2MiB limit | `--settings` file over 2 MiB or not a regular file | Exit 1; point at a normal JSON file |
| Could not read Claude Code config | `~/.claude.json` unparseable during `claude import` | Run `claude` to reset, or fix JSON by hand |

Two output-routing facts from these entries: the rule warnings go to the debug log instead of stderr
in background sessions or with `--output-format json`/`stream-json`; run with `--debug` to capture
them at `~/.claude/debug/<session-id>.txt`. A `claude-settings-<hash>.json` path in a warning that
does not exist on disk means an inline `--settings` value.

### Hook-related errors

Source: https://code.claude.com/docs/en/errors.md § "Model switch was blocked by a PreModelSwitch hook"; https://code.claude.com/docs/en/errors.md § "Plugin errors"

| Message (short) | Cause | Fix |
| :-- | :-- | :-- |
| Model switch was blocked by a PreModelSwitch hook | Hook denied, asked without a way to prompt, timed out, failed, or managed-plugin hooks could not be checked | Address the hook reason, raise `timeout`, or use `claude --debug` and retry. A hook run without a verdict is not treated as approval |
| Plugin command references `user_config` in a shell command | A plugin hook, monitor, or MCP `headersHelper` substitutes `${user_config.KEY}` into a shell string | Component refused. Use exec form (`args` array) or read `$CLAUDE_PLUGIN_OPTION_<KEY>` |

### Plugin errors

Source: https://code.claude.com/docs/en/errors.md § "Plugin errors"

| Message (short) | Cause | Fix |
| :-- | :-- | :-- |
| Marketplace is registered from an untrusted source | Reserved official name not sourced from `github.com/anthropics`; re-checked on every load | Remove and re-add from the official source |
| Marketplace is already added from a different source | Name collision with an existing marketplace | Install by `<plugin>@<name>` or remove the old one |
| Plugin archive integrity check failed | `archive` source `sha256` pin does not match download | Nothing installed; verify the pin |
| Path escapes plugin directory | A component path (e.g. `commands`, `hooks`) resolves outside the plugin, via `..`, symlink, or a backslash on macOS/Linux | That path dropped, rest of plugin loads |
| Path could not be checked | OS error other than not-found (`ELOOP`, `EIO`, `ESTALE`, `EACCES`) | Default component skipped, or whole plugin if its own dir; fix then `/reload-plugins` |
| Marketplace entry path does not stay inside the marketplace directory | Absolute, climbing, network-shaped, backslash, or escaping symlink entry | Plugin does not install or load; `claude plugin list` shows `failed to load` |
| Failed to load marketplace configuration | `~/.claude/plugins/known_marketplaces.json` invalid, unreadable, or empty (missing is fine) | Repair or reset to `{}` and re-add |
| Plugin is required by your organization | Disabling a required synced plugin | Nothing saved; admin must change it |

The section also points to plugin troubleshooting for installs that succeed but do not appear.

### Tool, subagent, memory, and skill errors

Source: https://code.claude.com/docs/en/errors.md § "Tool errors"; https://code.claude.com/docs/en/errors.md § "Skill usage reports are not available on this connection"; https://code.claude.com/docs/en/errors.md § "Configuration warnings"; https://code.claude.com/docs/en/errors.md § "Command-line errors"

| Message (short) | Cause | Fix |
| :-- | :-- | :-- |
| Agent would be spawned with zero tools | Every `tools` entry unrecognized, unavailable to subagents, or unmatched in this session | Fix entries, or delete `tools` to inherit all subagent tools |
| File is covered by a Read deny rule | Edit/Write on a path matched by a `Read` deny rule | Narrow the rule; add an `Edit` deny to also block NotebookEdit |
| subagent\_type is required | No general-purpose agent available | Add it to the `Agent(...)` allowlist or unset the SDK env var |
| Memory index is over its read limit | Auto memory `MEMORY.md` over 200 lines or 25KB; tail dropped at load | Rewrite the index shorter |
| Agent descriptions are over the 15.0k-token limit | Combined custom subagent descriptions too long | Warning only; all agents still load |
| Invalid --agents configuration | `--agents` JSON invalid or fails schema | Exit 1 (not checked under `--safe-mode`, `--resume`, `--continue`) |
| Skill usage reports are not available on this connection | `/skill-doctor` over Remote Control | Run it locally or via `claude -p "/skill-doctor"` |
| Unknown command | Typo, unmet requirement, or plugin/MCP command not loaded | In non-interactive surfaces the text goes to Claude as a message instead |

### MCP configuration errors

Source: https://code.claude.com/docs/en/errors.md § "Command-line errors"; https://code.claude.com/docs/en/errors.md § "Configuration warnings"; https://code.claude.com/docs/en/errors.md § "Tool input schema is invalid"

| Message (short) | Cause | Fix |
| :-- | :-- | :-- |
| Can't read .mcp.json | Not a regular file, or over 2 MiB, during `claude mcp` commands | Replace with a normal JSON file |
| MCP server is blocked by enterprise managed policy | `deniedMcpServers`, `allowedMcpServers`, `strictPluginOnlyCustomization`, or `disableClaudeAiConnectors` | Check own settings first, then the admin |
| headersHelper not run | Folder has no persisted trust; helper skipped (stderr in `-p`, debug log interactively) | Accept trust once or set `hasTrustDialogAccepted` |
| Tool input schema is invalid | An MCP tool schema fails JSON Schema validation | Disable the server or fix the schema |

## Not found in source

Source: https://code.claude.com/docs/en/commands.md § "Commands"; https://code.claude.com/docs/en/debug-your-config.md § "Debug your configuration"; https://code.claude.com/docs/en/errors.md § "Error reference"

Items below were expected for this topic but are absent from all three pages.

- An explicit statement that custom slash commands (`.claude/commands/`) were merged into skills, or
  how a same-named command and skill resolve. The source only points custom commands to skills and
  mentions "command directories" in `/reload-skills`.
- The output format of `/hooks`, `/permissions`, `/status`, or `/context` (fields, machine-readable
  form, or a non-interactive variant), except that `/mcp` prints a text summary under `-p`.
- Exit codes or machine-readable output for `claude doctor`.
- A list of `--debug` categories other than `--debug=mcp`, and the debug log line format (deferred to
  the hooks page).
- Any log location other than `~/.claude/debug/<session-id>.txt`.
- Error entries for hook script failures, hook exit codes, or hook timeouts other than
  PreModelSwitch (deferred to "Debug hooks").
- Error entries for invalid `SKILL.md` frontmatter or skills that fail to load.
- The literal text of the settings-validation error notice for a rejected user/project/local file.
- A command to reload hooks explicitly; the source relies on settings live reload.
- A command that dumps the fully merged effective settings as JSON.
- A single consistent description of `/status`: commands.md lists version, model, account,
  connectivity; debug-your-config.md says it shows active settings sources and managed-settings
  state.
