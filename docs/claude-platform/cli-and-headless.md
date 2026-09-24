---
verified: 2026-09-23
sources:
  - https://code.claude.com/docs/en/headless.md
  - https://code.claude.com/docs/en/cli-reference.md
  - https://code.claude.com/docs/en/tools-reference.md
  - https://code.claude.com/docs/en/env-vars.md
scope: Claude Code's command-line surface, non-interactive (-p) mode, built-in tool names and permission needs, Bash and PowerShell tool behaviour, and the environment variables that govern hooks, skills, plugins, permissions, shells, CI runs, telemetry, and config directories.
---

# CLI and headless

This is a condensed, source-pinned summary of four Claude Code documentation pages. It covers how to
run `claude` without a human (`-p`), which flags and subcommands matter for scripted and CI use, the
exact built-in tool names used in permission rules and hook matchers, how the Bash and PowerShell
tools behave, and the environment variables that change any of that. Version numbers (`v2.1.x`)
are the minimum versions the source names. Anything the source does not state is listed at the end
under "Not found in source" instead of being guessed.

## Print mode (`-p`) basics

Source: https://code.claude.com/docs/en/headless.md § "Basic usage"; https://code.claude.com/docs/en/cli-reference.md § "CLI flags"

- `-p` / `--print` runs any `claude` invocation non-interactively and exits. The docs frame this as
  using the Agent SDK through the CLI.
- Without `--bare`, a `-p` run loads the same context an interactive session would, including
  configuration in the working directory and in `~/.claude`.
- Not every flag combines with `-p`. `--bg` is rejected. `--cloud` with a task description is
  rejected; `--cloud` with a session ID plus `-p` queues a message into that cloud session and exits.
- Slash commands in `-p`: user-invoked skills and custom commands work when `/skill-name` appears in
  the prompt string. Terminal-only built-ins such as `/login` are unavailable. `/model`, `/effort`,
  `/fast`, `/color`, `/rename` take a value as an argument (v2.1.205+); `/mcp` alone prints a text
  status summary; `/config key=value` changes a setting; `/output-style <style>` (v2.1.269+).
  (Source: § "Create a commit".)
- Without `--bare`, a `-p` session runs hooks from the project's `.claude/settings.json` and connects
  servers from its `.mcp.json` even in an untrusted folder. There is no workspace trust dialog and no
  per-server approval prompt under `-p`. (Source: § "Start faster with bare mode".)

### Exit codes and where errors go

Source: https://code.claude.com/docs/en/headless.md § "Basic usage"; https://code.claude.com/docs/en/headless.md § "Stop a run with SIGTERM"; https://code.claude.com/docs/en/headless.md § "Pipe data through Claude"; https://code.claude.com/docs/en/cli-reference.md § "CLI flags"; https://code.claude.com/docs/en/cli-reference.md § "CLI commands"

| Situation | Behaviour |
| --- | --- |
| Run succeeds | exit 0 |
| Run fails | non-zero exit |
| Invalid flag | error on stderr, before the run starts |
| Failure inside the run (for example, missing authentication) | failure printed as the result on stdout |
| `--max-turns` limit reached | exits with an error (no specific code given) |
| Piped stdin larger than 10MB | clear error, non-zero exit |
| Unreadable stdin | warning on stderr; continues with the command-line prompt (Windows crash fixed in v2.1.211) |
| Invalid `--json-schema` | exits with `Error: --json-schema is not a valid JSON Schema` plus a diagnostic (v2.1.205+) |
| SIGTERM | exit 143; the in-progress turn is left unfinished with no result recorded |
| `claude auth status` | 0 if logged in, 1 if not |
| `claude daemon status` | 1 if the supervisor is not running |
| `claude ultrareview` | 0 on success, 1 on failure |

SIGTERM detail: Claude Code kills the process tree of any running Bash command, records it as killed,
runs `SessionEnd` hooks, and exits. During shutdown it starts no new tool call, model request, or
hook other than `SessionEnd`. A pending permission prompt is left unanswered. Resuming the session
continues the unfinished turn. Send SIGINT (or the SDK's `interrupt()`) first if you want the turn
to end cleanly.

`CLAUDE_CODE_STARTUP_FAILURE_RESULTS=1` makes a `--output-format stream-json` session write a result
message naming why startup was refused, for failures that would otherwise only reach stderr
(v2.1.274+). (Source: env-vars.md § "Variables".)

### Background work at exit

Source: https://code.claude.com/docs/en/headless.md § "Background tasks at exit"

- A background Bash task (dev server, watch build) is terminated about five seconds after the final
  result is returned and stdin has closed.
- A background subagent or workflow keeps `claude -p` open until it finishes, because its output is
  part of the result. The wait ends after 10 minutes of continuous idle waiting; remaining work is
  stopped and its partial result dropped. `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS` changes the ceiling;
  `0` means no ceiling.
- A `Monitor` watch is waited on until it times out (five minutes after start by default) or the
  ten-minute cap ends the wait.

## Bare mode (`--bare`)

Source: https://code.claude.com/docs/en/headless.md § "Start faster with bare mode"; https://code.claude.com/docs/en/cli-reference.md § "CLI flags"; https://code.claude.com/docs/en/env-vars.md § "Variables"

`--bare` is a minimal mode meant for scripts and CI where the same result is wanted on every
machine. It sets `CLAUDE_CODE_SIMPLE` (and `CLAUDE_CODE_SIMPLE=1` is equivalent to the flag).

Skipped (no auto-discovery): hooks, skills, custom commands, subagents, plugins, MCP servers, auto
memory, CLAUDE.md. A teammate's `~/.claude` hook or a project `.mcp.json` server will not run.

Kept or changed:

- Tools: only Bash, file read, and file edit. MCP tools from `--mcp-config` are still available.
- A minimal system prompt (per the `CLAUDE_CODE_SIMPLE` row).
- `--add-dir` directories are a partial exception: their `.claude/skills/` loads, but their
  `.claude/commands/` and `.claude/agents/` do not.
- Authentication: OAuth credentials and the system keychain are never read. For the Anthropic API,
  set `ANTHROPIC_API_KEY` or supply `apiKeyHelper` in `--settings` JSON. Bedrock, Google Cloud's Agent
  Platform, and Microsoft Foundry still read their own provider credentials.
- System-prompt recording across resumes is off in bare mode unless `--system-prompt-snapshot on` is
  passed (outside cloud sessions). (Source: cli-reference.md § "System prompt flags in resumed conversations".)
- `CLAUDE_CODE_DISABLE_AUTO_MEMORY=0` forces auto memory back on even under `--bare`.

Explicit re-injection flags in bare mode:

| To load | Flag |
| --- | --- |
| System prompt additions | `--append-system-prompt`, `--append-system-prompt-file` |
| Settings | `--settings <file-or-json>` |
| MCP servers | `--mcp-config <file-or-json>` |
| Custom agents | `--agents <json>` |
| A plugin | `--plugin-dir <path>`, `--plugin-url <url>` |

The source says `--bare` is the recommended mode for scripted and SDK calls and will become the
default for `-p` in a future release.

## Safe mode and restricted mode

Source: https://code.claude.com/docs/en/cli-reference.md § "CLI flags"; https://code.claude.com/docs/en/env-vars.md § "Variables"

| | `--bare` | `--safe-mode` | `--restricted` |
| --- | --- | --- | --- |
| Purpose | fast, reproducible scripted runs | troubleshoot a broken configuration | evaluation harness on a shared machine |
| Env equivalent | `CLAUDE_CODE_SIMPLE=1` | `CLAUDE_CODE_SAFE_MODE=1` (inherited by direct child processes) | `CLAUDE_CODE_RESTRICTED=1` (ignored in a settings `env` block) |
| Built-in tools | Bash, read, edit only | normal | removes tools that run commands or code, and WebFetch, unless named individually in `--tools` (not via `default`) |
| Customizations | not discovered | not loaded | loads only managed settings and `--settings` |
| Auth | API key or `apiKeyHelper` only | normal | not stated |
| Min version | not stated | not stated | v2.1.248 |

Safe mode does not load: CLAUDE.md, skills, plugins, hooks, MCP servers, custom commands and agents,
output styles, workflows, custom themes, custom keybindings, status line and file-suggestion commands,
LSP servers, auto memory. Authentication, model selection, built-in tools, and permissions work
normally. Managed policy still applies, including policy-configured hooks, status line, and
file-suggestion commands; managed plugins, managed skills, managed CLAUDE.md, and policy MCP servers
do not load.

Restricted mode also confines built-in file tools to the working directories, refuses
`bypassPermissions`, and refuses to create cloud sessions. Removing Bash this way also restores
`Glob` and `Grep` on macOS, Linux, and WSL (tools-reference.md § "Glob tool behavior").

## Setup hooks, `--init`, `--maintenance`, `--init-only`

Source: https://code.claude.com/docs/en/cli-reference.md § "CLI flags"; https://code.claude.com/docs/en/headless.md § "Read session metadata"; https://code.claude.com/docs/en/env-vars.md § "Variables"

What the sources say, and nothing more:

| Flag | Effect | Mode |
| --- | --- | --- |
| `--init` | Runs Setup hooks with the `init` matcher before the session | print mode only |
| `--maintenance` | Runs Setup hooks with the `maintenance` matcher before the session | print mode only |
| `--init-only` | Runs Setup and `SessionStart` hooks, then exits without starting a conversation | not stated as print-only; example is `claude --init-only` |

- In stream-json output, `hook_started`, `hook_progress`, and `hook_response` events for a running
  `SessionStart` or `Setup` hook stream before `system/init` (live delivery restored in v2.1.204).
- `--include-hook-events` is not needed for `SessionStart` and `Setup` events; they are always included.
- Setup hooks (with SessionStart, CwdChanged, FileChanged) can populate `CLAUDE_ENV_FILE`.

## Output formats and structured output

Source: https://code.claude.com/docs/en/headless.md § "Get structured output"; https://code.claude.com/docs/en/headless.md § "Stream responses"; https://code.claude.com/docs/en/headless.md § "Pipe data through Claude"

`--output-format` (print mode):

| Value | Shape |
| --- | --- |
| `text` | default; plain text |
| `json` | one JSON object: text in `result`, plus `session_id`, usage, metadata, `total_cost_usd`, per-model cost breakdown |
| `stream-json` | newline-delimited JSON events; last line is a `result` message with final text, cost, session metadata |

- `--json-schema '<schema>'` with `--output-format json` puts schema-conforming output in
  `structured_output`. The `format` keyword is accepted as an annotation only (not enforced).
- Cost figures are client-side estimates. With `--continue`/`--resume` they report the whole
  conversation's total, earlier runs included.
- Token-level streaming: `--output-format stream-json --verbose --include-partial-messages`; text
  deltas appear as `stream_event` lines with `.event.delta.type == "text_delta"`.
- A slow consumer delays exit while queued output drains, capped at 30 seconds (v2.1.214+).

### Stream events worth gating on

Source: https://code.claude.com/docs/en/headless.md § "Read session metadata"; https://code.claude.com/docs/en/headless.md § "Fail CI when a plugin or MCP server doesn't load"; https://code.claude.com/docs/en/headless.md § "Handle API retries"; https://code.claude.com/docs/en/headless.md § "Track plugin installs"; https://code.claude.com/docs/en/headless.md § "Follow subagent messages"

| Event / field | Use |
| --- | --- |
| `system/init` | model, tools, MCP servers, loaded plugins; optional `capabilities` array for feature detection (v2.1.205+) |
| `system/init.plugins` | plugins that loaded (`name`, `path`) |
| `system/init.plugin_errors` | load errors (`plugin`, `type`, `message`); key omitted when empty |
| `system/init.mcp_servers` | servers with `name`, `status` |
| `system/init.mcp_server_errors` | `--mcp-config` entries skipped by validation (`unknown_type`, `url_missing_type`, `invalid_config`, `reserved_name`, ...); key omitted when empty (v2.1.219+) |
| `system/api_retry` | emitted before a retry: `attempt`, `max_retries`, `retry_delay_ms`, `error_status`, `error` category |
| `system/plugin_install` | only with `CLAUDE_CODE_SYNC_PLUGIN_INSTALL`; `status` is `started`/`installed`/`failed`/`completed` |
| `permission_denied` | system message per denial when prompts are off; final result lists `permission_denials` |
| `parent_tool_use_id` | non-null on subagent messages; subagent text/thinking only with `--forward-subagent-text` or `CLAUDE_CODE_FORWARD_SUBAGENT_TEXT` |

An invalid `--mcp-config` entry does not fail the run; it exits cleanly. The stderr warning is
suppressed when stderr is captured (CI), so a gate must read `mcp_server_errors`. With `-p` and
`--mcp-config`, Claude Code waits for pending servers up to `MCP_TIMEOUT` (default 30 s) before the
first turn (v2.1.221+).

## Input formats and stdin

Source: https://code.claude.com/docs/en/cli-reference.md § "CLI flags"; https://code.claude.com/docs/en/headless.md § "Pipe data through Claude"

- `--input-format` accepts `text` or `stream-json` (print mode).
- `--replay-user-messages` echoes stdin user messages back on stdout; requires both input and output
  formats to be `stream-json`.
- With `--input-format stream-json`, a message still queued when `--max-turns` ends a turn stays
  queued and starts a new turn with its own limit.
- Piped stdin is read as input and capped at 10MB; for bigger inputs, write a file and reference it.

## Permissions in unattended runs

Source: https://code.claude.com/docs/en/headless.md § "Auto-approve tools"; https://code.claude.com/docs/en/headless.md § "Turn off permission prompts in unattended runs"; https://code.claude.com/docs/en/headless.md § "Create a commit"; https://code.claude.com/docs/en/cli-reference.md § "CLI flags"

- For `-p`, the built-in starting mode is Manual (`default`) on every plan; pass the mode you want.
- `--permission-mode` values: `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`,
  `bypassPermissions`, and `manual` (alias of `default`, v2.1.200+). Overrides `defaultMode` from
  settings. `--dangerously-skip-permissions` equals `--permission-mode bypassPermissions`.
- `dontAsk`: denies anything that would prompt. Still runs actions that need no approval in Manual
  (reads inside working directories, the read-only command set) and anything covered by
  `--allowedTools` or `permissions.allow`. `AskUserQuestion`, org-`ask` connector tools, and MCP tools
  marked `requiresUserInteraction` are denied even if an allow rule matches.
- `acceptEdits`: file writes plus common filesystem commands (`mkdir`, `touch`, `mv`, `cp`) are
  auto-approved; other shell commands and network requests still need allow entries.
- `auto`: a classifier reviews most actions.
- `--permission-prompts none` (v2.1.259+): anything that would prompt is denied unless a
  `PermissionRequest` hook allows it; Claude is told not to retry; tools needing a human (such as
  `AskUserQuestion`) are removed; unanswered MCP elicitations are cancelled. Rules, hooks, and mode
  still decide first. Default is `host` (send to SDK host or `--permission-prompt-tool`).
- `--allowedTools` / `--allowed-tools`: tools that run without prompting, in permission-rule syntax.
  `Bash(git diff *)` is a prefix match; the space before `*` matters (`Bash(git diff*)` also matches
  `git diff-index`).
- `--disallowedTools` / `--disallowed-tools`: deny rules. A bare name removes the tool from context
  (`"*"` removes all, `"mcp__*"` all MCP). A scoped rule such as `Bash(rm *)` keeps the tool and denies
  matching calls.
- `--tools`: restricts which built-in tools exist (`""` none, `"default"`, or a list). Does not affect
  MCP tools.
- `--permission-prompt-tool <mcp tool>`: MCP tool that answers prompts; it cannot approve a tool
  marked as requiring user interaction (v2.1.199+).

## System prompt flags

Source: https://code.claude.com/docs/en/cli-reference.md § "System prompt flags"; https://code.claude.com/docs/en/cli-reference.md § "System prompt flags in resumed conversations"; https://code.claude.com/docs/en/headless.md § "Customize the system prompt"

| Flag | Effect |
| --- | --- |
| `--system-prompt` | replace the whole default prompt |
| `--system-prompt-file` | replace with file contents |
| `--append-system-prompt` | append text to the default prompt |
| `--append-system-prompt-file` | append file contents |
| `--system-prompt-snapshot on/off` | `on` (default) reuses the prompt recorded on the first request; `off` rebuilds every request (v2.1.257+) |
| `--append-subagent-system-prompt` | append to every subagent's prompt (not forks); `-p` only (v2.1.205+) |
| `--append-subagent-system-prompt-file` | file form; not combinable with the text form; `-p` only (v2.1.261+) |
| `--exclude-dynamic-system-prompt-sections` | move per-machine sections into the first user message for cache reuse; ignored with a replacement prompt |

- The two replacement flags are mutually exclusive; append flags combine with either.
- Replacing drops the default tool guidance and safety instructions; appending keeps them.
- A line containing only `__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__` splits a custom prompt into a cached
  static part and a changing part (v2.1.275+).
- On resume, the recorded prompt is reused until compaction, so changed flag text only takes effect
  after compaction or in a new conversation, unless `--system-prompt-snapshot off`.

## Sessions: continue, resume, persistence

Source: https://code.claude.com/docs/en/headless.md § "Continue conversations"; https://code.claude.com/docs/en/cli-reference.md § "CLI flags"; https://code.claude.com/docs/en/cli-reference.md § "CLI commands"

| Flag | Behaviour |
| --- | --- |
| `--continue`, `-c` | most recent conversation in the current directory. Interactive `-c` skips `-p`/SDK/`/loop` sessions; `claude -p --continue` includes them |
| `--resume`, `-r` | by session ID, name, or absolute path to a `.jsonl` transcript; searches the current project, its worktrees, then every project on the machine (v2.1.223+) |
| `--fork-session` | new session ID when resuming |
| `--session-id <uuid>` | use a specific session ID |
| `--name`, `-n` | display name; resumable by name |
| `--no-session-persistence` | do not save to disk; print mode only |

- Capture a session ID from `--output-format json` (`.session_id`) and pass it to `--resume`.
- `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1` does what `--no-session-persistence` does, in any mode.
- A nested `claude -p` launched from a Claude Code tool subprocess still persists; nested interactive
  sessions do not (`CLAUDE_CODE_CHILD_SESSION`, env-vars.md § "Variables").

## Load-bearing CLI flags

Source: https://code.claude.com/docs/en/cli-reference.md § "CLI flags"

`claude --help` does not list every flag. Flags already covered above are omitted here.

| Flag | Summary |
| --- | --- |
| `--max-turns N` | cap agentic turns; print mode only; no default limit. Env: `CLAUDE_CODE_MAX_TURNS` (flag wins) |
| `--max-budget-usd N` | spend cap; print mode only; subagent spend counts |
| `--settings <file-or-json>` | overrides same keys from settings files for this session; file max 2 MiB |
| `--setting-sources user,project,local` | which setting sources to load |
| `--mcp-config` / `--strict-mcp-config` | load MCP servers; strict ignores all other MCP config |
| `--plugin-dir <path>` | session-only plugin from a dir or `.zip`; repeatable; folder-of-plugins v2.1.265+ |
| `--plugin-url <url>` | session-only plugin `.zip` from a URL |
| `--agents <json>` / `--agent <name>` | define subagents inline / pick the session agent |
| `--add-dir` | extra working directories (file access, not most `.claude/` config) |
| `--disable-slash-commands` | disable all skills and commands for the session |
| `--model`, `--fallback-model`, `--effort` | model selection; effort `low`..`max`, `ultracode` |
| `--debug[=filter]`, `--debug-file <path>` | debug logging; file form implies debug |
| `--verbose` | full turn-by-turn output; needed with stream-json partials |
| `--include-hook-events` | hook lifecycle events in stream-json |
| `--worktree`, `-w` | run in an isolated git worktree under `.claude/worktrees/<name>` |
| `--version`, `-v` | print version |

## Subcommands

Source: https://code.claude.com/docs/en/cli-reference.md § "CLI commands"

| Command | Summary |
| --- | --- |
| `claude update` / `claude install [version]` | update / install native binary (`stable`, `latest`, or a version) |
| `claude auth login|logout|status` | sign in (`--console`, `--sso`, `--email`); status is JSON (`--text`), exit 0/1 |
| `claude setup-token` | print a long-lived OAuth token for CI; requires a subscription; not saved |
| `claude doctor` | read-only install and settings diagnostics, including settings-file validation errors |
| `claude mcp`, `claude mcp login|logout <name>` | manage MCP servers; OAuth without the `/mcp` panel (v2.1.186+) |
| `claude plugin` (alias `claude plugins`) | manage plugins; subcommands live in the plugins reference, not here |
| `claude auto-mode defaults|config|reset` | print classifier rules / effective config / reset |
| `claude agents`, `attach`, `logs`, `respawn`, `rm`, `stop` | background session management |
| `claude daemon status|stop --any` | background supervisor |
| `claude project purge [path]` | delete local state for a project (`--dry-run`, `-y`, `--all`) |
| `claude ultrareview [target]` | non-interactive review; `--json`, `--timeout`, `--post` |
| `claude import`, `gateway`, `remote-control`, `self-hosted-runner` | import configs, gateway server, Remote Control, runners |

A mistyped subcommand prints a suggestion and exits without starting a session.

## Built-in tools

Source: https://code.claude.com/docs/en/tools-reference.md § "Tools reference"

Names are exact strings for permission rules, subagent tool lists, and hook matchers. "Permission"
means whether the tool prompts in Manual mode for paths inside the working directory. File tools
marked No still prompt outside the working and additional directories; Bash is Yes but runs a
built-in read-only command set without prompting.

| Tool | Perm | Note |
| --- | --- | --- |
| `Agent` | No | spawn subagent / teammate |
| `Artifact` | Yes | publish HTML/Markdown page; paid plan + `/login` |
| `AskUserQuestion` | No | multiple-choice questions |
| `Bash` | Yes | shell commands |
| `CronCreate`, `CronDelete`, `CronList` | No | session-scoped scheduled prompts |
| `Edit` | Yes | targeted file edits |
| `EndConversation` | No | ends session (v2.1.213+) |
| `EnterPlanMode` | No | |
| `EnterWorktree` | Yes | |
| `ExitPlanMode` | Yes | |
| `ExitWorktree` | No | |
| `Glob` | No | absent by default on macOS/Linux/WSL |
| `Grep` | No | ripgrep; absent by default on macOS/Linux/WSL |
| `ListAgents` | No | cross-session messaging only |
| `ListMcpResourcesTool`, `ReadMcpResourceTool` | No | MCP resources |
| `LSP` | No | language-server code intelligence |
| `Monitor` | Yes | background command/WebSocket feeding lines back |
| `NotebookEdit` | Yes | Jupyter cells |
| `PowerShell` | Yes | native PowerShell; see below |
| `PushNotification` | No | desktop/phone notification |
| `Read` | No | |
| `RemoteTrigger` | No | claude.ai Routines |
| `ReportFindings` | No | structured code-review findings |
| `ScheduleWakeup` | No | self-paced `/loop` |
| `SendFeedback` | No | drafts feedback, sends nothing without you |
| `SendMessage` | No | message another agent/session |
| `SendUserFile` | No | Remote Control / cloud only |
| `ShareOnboardingGuide` | Yes | |
| `Skill` | Yes | runs a skill |
| `SubagentHandback` | No | auto mode, local non-fork subagents (v2.1.271+) |
| `TaskCreate`, `TaskGet`, `TaskList`, `TaskUpdate` | No | model-gated; see below |
| `TaskOutput` | No | deprecated |
| `TaskStop` | No | |
| `TodoWrite` | No | off by default; `CLAUDE_CODE_ENABLE_TASKS=0` |
| `ToolSearch` | No | deferred tool loading |
| `WaitForMcpServers` | No | only when tool search is disabled |
| `WebFetch` | Yes | |
| `WebSearch` | Yes | 200 calls per session cap |
| `Workflow` | Yes | dynamic workflows |
| `Write` | Yes | |

### Rule formats

Source: https://code.claude.com/docs/en/tools-reference.md § "Configure tools with permission rules and hooks"

| Rule | Applies to |
| --- | --- |
| `Bash(npm run *)` | Bash, Monitor |
| `PowerShell(Get-ChildItem *)` | PowerShell |
| `Read(path)` | Read, Grep, Glob, LSP |
| `Edit(path)` | Edit, Write, NotebookEdit |
| `Skill(name *)` | Skill |
| `Agent(Explore)` | Agent |
| `WebFetch(domain:x)` | WebFetch |
| `WebSearch` | bare only |

Other tools take the bare name only. Hook `matcher` fields use bare names, not the parenthesized form.
An `Edit(...)` allow also grants read; a `Read(...)` deny also blocks Edit and Write on that path.

### Glob, Grep, and task tools availability

Source: https://code.claude.com/docs/en/tools-reference.md § "Glob tool behavior"; https://code.claude.com/docs/en/tools-reference.md § "Task tool availability"

- Windows: Glob and Grep are in the default set. macOS/Linux/WSL: they are left out and searches go
  through Bash `find`/`grep` (embedded `bfs`/`ugrep`), reaching hooks as `Bash` calls. They return if
  named in `--tools`/`--allowedTools` at launch (a settings allow rule does not do this), if Bash is
  removed (deny rule, `--disallowedTools`, `--restricted`), or via a subagent that lists them and omits Bash.
- Task tools are default only on Claude 3.x, Opus 4 to 4.7, Sonnet 4 to 4.6, Haiku 4.5 (v2.1.268+).
  Opt in with `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`, by naming one in `--allowedTools`, or listing in `--tools`.

## Bash tool

Source: https://code.claude.com/docs/en/tools-reference.md § "Bash tool behavior"; https://code.claude.com/docs/en/tools-reference.md § "What persists between commands"; https://code.claude.com/docs/en/tools-reference.md § "Timeout and output limits"; https://code.claude.com/docs/en/tools-reference.md § "Output limits"; https://code.claude.com/docs/en/tools-reference.md § "Background commands"; https://code.claude.com/docs/en/tools-reference.md § "Memory limit on Linux and WSL"; https://code.claude.com/docs/en/env-vars.md § "Variables"

- Each command runs in a separate process.
- Working directory: a `cd` in the main session carries over while it stays inside the project or an
  added directory; outside them it resets and appends `Shell cwd was reset to <dir>`. Subagents never
  carry `cd` over. `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1` makes every command start in the
  project directory.
- Environment: `export` does not persist. Aliases, functions, and shell options from `~/.zshrc`,
  `~/.bashrc`, or `~/.profile` are captured at session start and applied. To persist variables, set
  `CLAUDE_ENV_FILE` to a script run before each command, or populate it from a SessionStart hook.
- Timeouts: Claude passes a per-call `timeout`. `BASH_DEFAULT_TIMEOUT_MS` (default 120000) and
  `BASH_MAX_TIMEOUT_MS` (default 600000; effective ceiling is the larger of the two).
- A command that hits its timeout is moved to the background rather than killed (unless it starts
  with `sleep`); `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` disables this and all background tasks.
- Output: streamed to a working file; killed past 5 GB. Valid results inline to about 30,000 chars,
  then a file path plus 2,000-char preview. Failures inline to about 10,000 chars as head-and-tail.
  `BASH_MAX_OUTPUT_LENGTH` sets the read-back window (default 30000, max 150000); the
  `bashOutputMaxChars` setting (up to 128,000, v2.1.261+) overrides it.
- Exit 1 counts as success only for `grep`, `rg`, `egrep`, `fgrep`, `find`, `diff`, `test`, `[`,
  `git diff`, `git grep`.
- Shell choice: `CLAUDE_CODE_SHELL` accepts a `bash` or `zsh` path only; otherwise auto-detect.
  On Windows, `CLAUDE_CODE_GIT_BASH_PATH` points at Git Bash. (env-vars.md § "Variables".)
- Linux/WSL memory cap: `CLAUDE_CODE_TOOL_MEMORY_LIMIT` (for example `4G`) caps Bash, PowerShell,
  and Monitor commands together via a cgroup (v2.1.233+). (§ "Memory limit on Linux and WSL".)

## PowerShell tool

Source: https://code.claude.com/docs/en/tools-reference.md § "PowerShell tool"; https://code.claude.com/docs/en/tools-reference.md § "Enable the PowerShell tool"; https://code.claude.com/docs/en/env-vars.md § "Variables"; https://code.claude.com/docs/en/env-vars.md § "Features that need feature-flag fetching"

Tool name `PowerShell`, permission required, rule form `PowerShell(Get-ChildItem *)`. It runs
PowerShell natively; on Windows that means not routing through Git Bash.

| Platform | Default | Control via `CLAUDE_CODE_USE_POWERSHELL_TOOL` |
| --- | --- | --- |
| Windows, no Git Bash | enabled automatically | `0` disables |
| Windows, Git Bash installed | on for claude.ai and Console accounts | `1` enables on Bedrock, Agent Platform, Foundry; `0` turns off |
| Linux, macOS, WSL | opt-in | `1` enables; requires PowerShell 7+ (`pwsh`) on `PATH` |

- The variable can be set in the shell or in a settings `env` block.
- With feature-flag fetching off (`DISABLE_TELEMETRY`, `DO_NOT_TRACK`, `DISABLE_GROWTHBOOK`,
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, or a third-party provider), Windows-with-Git-Bash does
  not get the tool by default; shell commands go through Git Bash unless
  `CLAUDE_CODE_USE_POWERSHELL_TOOL=1` is set. Without Git Bash it stays on.
- Windows executable: auto-detects `pwsh.exe` (7+), falls back to `powershell.exe` (5.1).
- When enabled, Claude treats PowerShell as the primary shell; Bash stays available for POSIX scripts
  when Git Bash is installed.
- Execution policy: spawned with `-ExecutionPolicy Bypass` at process scope (tool calls, hooks, status
  line). Does not override Group Policy `MachinePolicy`/`UserPolicy`.
  `CLAUDE_CODE_POWERSHELL_RESPECT_EXECUTION_POLICY=1` drops the bypass.
- Hooks: PreToolUse receives the command in `tool_input.command`, same fields as Bash. Match
  `Bash|PowerShell` in shell-inspecting hooks; matching `Bash` alone is not enough.
- The Bash working-directory reset rules and `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR` apply.
- `CLAUDE_CODE_DISABLE_WINDOWS_SHELL_LAUNCHER=1` starts PowerShell commands directly instead of via
  the `cmd.exe` launcher; backgrounded commands then stop when the session process exits (v2.1.269+).
- Preview limitations: PowerShell profiles are not loaded; sandboxing is not supported on Windows.

### Shell selection and exit codes

Source: https://code.claude.com/docs/en/tools-reference.md § "Shell selection in settings, hooks, and skills"; https://code.claude.com/docs/en/tools-reference.md § "Windows encoding and exit codes"

| Setting | Effect | Needs the tool enabled? |
| --- | --- | --- |
| `"defaultShell": "powershell"` (settings.json) | interactive `!` commands via PowerShell | yes |
| `"shell": "powershell"` on a command hook | that hook runs in PowerShell | no; hooks spawn PowerShell directly |
| `shell: powershell` in skill frontmatter | `` !`command` `` blocks run in PowerShell | yes |

- Exit 1 from `grep`, `rg`, `egrep`, `fgrep`, `findstr`, `git grep` means no matches; from `git diff`
  means differences; not failures (v2.1.196+). `robocopy` 0 to 7 informational, 8+ failure.
- Windows v2.1.214+: `>`/`>>` write UTF-8 on 5.1; piped stdin to natives is UTF-8; stderr captured
  without ANSI; a child waiting on stdin gets EOF; `where.exe` exit 1 means no match and `fc.exe`/
  `diff.exe` exit 1 means differ when output is produced (silenced forms still count as failure).

## Environment variables

Source: https://code.claude.com/docs/en/env-vars.md § "Variables"; https://code.claude.com/docs/en/env-vars.md § "In settings files"; https://code.claude.com/docs/en/env-vars.md § "Precedence"

General rules: booleans accept `1`/`true` and `0`/`false`; a settings `env` value overrides the same
shell variable; settings files can set but not remove a variable (set `""` to neutralize); shell
variables are read at startup, settings `env` values are reapplied when the file changes. Some
variables are ignored in project/local settings or in any settings `env` block, as noted.

| Area | Variable | Effect |
| --- | --- | --- |
| Config dir | `CLAUDE_CONFIG_DIR` | replaces `~/.claude` (settings, history, plugins); shell/user/managed only |
| Config dir | `CLAUDE_CODE_PROJECT_DIR_NAME` | fixed `projects/` subdir name; needs `CLAUDE_CONFIG_DIR`; shell only (v2.1.234+) |
| Config dir | `CLAUDE_CODE_TMPDIR` | internal temp dir; shell/user/managed only |
| Headless | `CLAUDE_CODE_SIMPLE` | same as `--bare` |
| Headless | `CLAUDE_CODE_SAFE_MODE` | same as `--safe-mode` |
| Headless | `CLAUDE_CODE_RESTRICTED` | same as `--restricted`; ignored in settings `env` |
| Headless | `CLAUDE_CODE_MAX_TURNS` | default turn cap; `--max-turns` wins; invalid value fails startup |
| Headless | `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS` | `-p` idle wait for background work (default 600000; `0` none) |
| Headless | `CLAUDE_CODE_SKIP_PROMPT_HISTORY` | no transcripts or history on disk |
| Headless | `CLAUDE_CODE_STARTUP_FAILURE_RESULTS` | stream-json result for startup refusals (v2.1.274+) |
| Headless | `CLAUDE_CODE_FORWARD_SUBAGENT_TEXT` | like `--forward-subagent-text`; ignored where flag would error |
| Headless | `CLAUDE_CODE_EXIT_AFTER_STOP_DELAY` | ms idle before auto-exit in SDK mode |
| Headless | `CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS` | `-p` only; removes Explore, Plan, general-purpose |
| Auth | `ANTHROPIC_API_KEY` | in `-p`, always used when present |
| Auth | `CLAUDE_CODE_OAUTH_TOKEN` | OAuth token for automation (from `claude setup-token`) |
| Hooks | `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` | SessionEnd budget (default 1.5 s, raised up to 60 s by hook timeouts) |
| Hooks | `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` | max consecutive Stop/SubagentStop blocks (default 8; `0` no cap) |
| Hooks | `CLAUDE_CODE_DISABLE_PERMISSION_PROMPT_NOTIFY_HOOKS` | skip Notification hooks for SDK-hosted prompts; no effect in terminal |
| Hooks/shell | `CLAUDE_CODE_SHELL_PREFIX` | wrapper for Bash calls, hooks, status line, stdio MCP; not PowerShell or exec-form hooks |
| Hooks/shell | `CLAUDE_ENV_FILE` | script sourced before each Bash command; hooks can populate it |
| Subprocess | `CLAUDECODE` | `1` in Claude-spawned subprocesses (also IDE terminals) |
| Subprocess | `CLAUDE_CODE_CHILD_SESSION` | `1` in tool/hook/status-line subprocesses only (v2.1.172+) |
| Subprocess | `CLAUDE_CODE_SESSION_ID`, `CLAUDE_PID` | session ID and parent PID in tool and hook subprocesses |
| Subprocess | `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` | strip credentials (and config pointers, v2.1.251+) from child env |
| Skills | `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` | remove bundled skills and workflows |
| Skills | `CLAUDE_CODE_DISABLE_POLICY_SKILLS` | skip system-wide managed skills dir (CI/container use) |
| Skills | `CLAUDE_CODE_SYNC_SKILLS` | `-p`: fetch claude.ai-enabled skills before first query |
| Skills | `CLAUDE_CODE_DISABLE_WORKFLOWS` | disable workflows |
| Plugins | `CLAUDE_CODE_PLUGIN_DIRS` | like repeated `--plugin-dir`; absolute paths; `;` on Windows (v2.1.280+) |
| Plugins | `CLAUDE_CODE_PLUGIN_SEED_DIR` | read-only pre-populated plugin dirs for images |
| Plugins | `CLAUDE_CODE_PLUGIN_CACHE_DIR` | plugins root (default `~/.claude/plugins`) |
| Plugins | `CLAUDE_CODE_SYNC_PLUGIN_INSTALL` (+ `_TIMEOUT_MS`) | `-p`: wait for plugin install before first query |
| Plugins | `CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL` | skip official marketplace registration, permanently if set at that moment |
| Plugins | `FORCE_AUTOUPDATE_PLUGINS` | plugin updates even with `DISABLE_AUTOUPDATER` |
| Memory | `CLAUDE_CODE_DISABLE_CLAUDE_MDS` | load no CLAUDE.md files |
| Memory | `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | `1` off; `0` forces on even in bare mode |
| Memory | `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` | load memory files from `--add-dir` dirs |
| Tools | `CLAUDE_CODE_ENABLE_TASKS`, `CLAUDE_CODE_ENABLE_TODO_TOOLS` | Task vs TodoWrite; task tools on every model |
| Tools | `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` | no background tasks or auto-backgrounding |
| PowerShell | `CLAUDE_CODE_USE_POWERSHELL_TOOL` | enable/disable PowerShell tool (table above) |
| PowerShell | `CLAUDE_CODE_POWERSHELL_RESPECT_EXECUTION_POLICY` | drop `-ExecutionPolicy Bypass` |
| PowerShell | `CLAUDE_CODE_DISABLE_WINDOWS_SHELL_LAUNCHER` | skip `cmd.exe` launcher (v2.1.269+) |
| Shells | `CLAUDE_CODE_SHELL`, `CLAUDE_CODE_GIT_BASH_PATH` | Bash tool shell; Git Bash path on Windows |
| Shells | `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR` | reset cwd after each Bash/PowerShell command |
| Shells | `BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_TIMEOUT_MS`, `BASH_MAX_OUTPUT_LENGTH` | timeouts and output window |
| Shells | `CLAUDE_CODE_TOOL_MEMORY_LIMIT` | Linux/WSL memory cap for shell tools |
| MCP | `MCP_TIMEOUT` | server startup timeout (default 30000) |
| Telemetry off | `DISABLE_TELEMETRY`, `DISABLE_ERROR_REPORTING` | any non-empty value opts out, even `0` |
| Telemetry off | `DO_NOT_TRACK` | standard boolean; `1` like `DISABLE_TELEMETRY` |
| Telemetry off | `DISABLE_GROWTHBOOK` | no feature-flag fetch; telemetry stays unless also disabled |
| Telemetry off | `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | any non-empty value (even `0`): no updates, telemetry, error reports, feedback, flag fetch |
| Telemetry on | `CLAUDE_CODE_ENABLE_TELEMETRY` | `1` enables OpenTelemetry |
| Updates | `DISABLE_AUTOUPDATER` / `DISABLE_UPDATES` | stop background updates / block all updates incl. `claude update`/`install` |
| Admin | `CLAUDE_CODE_DISABLE_ADMIN_ENV_UNION` | pre-v2.1.223 managed `env` merging; launch env only |

## Not found in source

Source: https://code.claude.com/docs/en/headless.md § "Run Claude Code programmatically"; https://code.claude.com/docs/en/cli-reference.md § "CLI reference"; https://code.claude.com/docs/en/tools-reference.md § "Tools reference"; https://code.claude.com/docs/en/env-vars.md § "Environment variables"

- A distinct numeric exit code for `--max-turns` exhaustion or `--max-budget-usd` exhaustion
  (only "exits with an error" for max-turns; nothing for budget).
- The JSON schema of `--output-format json` beyond the named fields, and the message schema for
  `--input-format stream-json`.
- The Setup hook event's input payload, its full matcher list beyond `init` and `maintenance`,
  whether `--init-only` is restricted to print mode, and `--init-only`'s exit code.
- A dedicated environment variable that disables all hooks. None is listed. `CLAUDE_CODE_SIMPLE=1`
  (bare) and `CLAUDE_CODE_SAFE_MODE=1` (safe mode) skip hooks as part of a wider effect, and safe
  mode still runs policy-configured (managed) hooks.
- `claude plugin ...` and `claude mcp ...` subcommand lists (deferred to other pages).
- A settings key or variable that removes the Bash tool on Windows; only `--tools`,
  `--disallowedTools`, deny rules, and `--restricted` are described as removing tools.
- PowerShell-specific timeout defaults or output limits (only the cwd rules, memory cap,
  background launcher, and exit-code rules are stated for PowerShell).
- Which flags `--restricted` treats as authentication inputs.
