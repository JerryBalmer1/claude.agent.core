---
verified: 2026-09-23
sources:
  - https://code.claude.com/docs/en/hooks.md
  - https://code.claude.com/docs/en/hooks-guide.md
scope: Claude Code hook events, configuration schema, matchers, handler types, exit-code and JSON output semantics, trust and disable rules, as stated in the two pinned pages; it does not restate per-tool input schemas in full, the Agent SDK callback API, or settings/permissions pages that the sources only link to.
---

# Hooks

Hooks are handlers that Claude Code runs automatically at fixed lifecycle points. A handler can be a shell command, an HTTP endpoint, an MCP tool call, a single-turn LLM prompt, or a subagent. Each handler gets a JSON description of the event and can optionally return a decision. This file condenses the pinned reference and guide pages. Where they give a version number for a behavior, the number is kept.

## Configuration model
Source: https://code.claude.com/docs/en/hooks.md § "Configuration"

Hooks live in JSON settings files, nested three levels deep:

1. **Hook event**, the lifecycle point (for example `PreToolUse` or `Stop`), as a key under `hooks`.
2. **Matcher group**, an object with an optional `matcher` and a `hooks` array.
3. **Hook handler**, each object in that inner `hooks` array.

In the source, "hook" alone means the feature in general.

### Hook locations and merging
Source: https://code.claude.com/docs/en/hooks.md § "Hook locations"; https://code.claude.com/docs/en/hooks-guide.md § "Configure hook location"

| Location | Scope | Shareable |
| :-- | :-- | :-- |
| `~/.claude/settings.json` | All your projects | No |
| `.claude/settings.json` | Single project | Yes, can be committed |
| `.claude/settings.local.json` | Single project | No (gitignored when Claude Code saves to it) |
| Managed policy settings | Organization-wide | Admin-controlled |
| Plugin `hooks/hooks.json` | While the plugin is enabled | Bundled with the plugin |
| Skill frontmatter | Rest of the session once the skill is invoked | In the skill file |
| Subagent frontmatter | While that subagent runs | In the subagent file |

- Hook entries **merge** across settings levels. They do not replace each other. User, project, and local settings add hooks without removing managed ones.
- Hooks from settings files, managed settings, and plugins also run inside subagents. Tool events for a subagent's calls carry `agent_id` and `agent_type`.
- Cloud sessions do not read local `~/.claude/settings.json`. Their hooks come from the repo's `.claude/settings.json` (for a single-repo session), from synced plugins, and from server-managed settings.
- `allowManagedHooksOnly` (enterprise) blocks user, project, local, and plugin hooks. It exempts plugins force-enabled in managed `enabledPlugins`. It also narrows `statusLine`, `fileSuggestion`, and `subagentStatusLine` to managed settings, and it affects `command`-source plugins and marketplace `headersHelper` commands unless `disableCommandPluginSources` is explicitly `false`.
- HTTP allowlists apply to hooks from every source, managed included. `allowedHttpHookUrls` restricts which URLs HTTP hooks may call. `httpHookAllowedEnvVars` restricts which env vars can be interpolated into headers.
- Direct edits to hook settings are normally picked up by the file watcher. If they are not, the guide says to restart the session.

## Hook event table
Source: https://code.claude.com/docs/en/hooks.md § "Hook lifecycle"; https://code.claude.com/docs/en/hooks.md § "Matcher patterns"; https://code.claude.com/docs/en/hooks.md § "Exit code 2 behavior per event"; https://code.claude.com/docs/en/hooks.md § "Decision control"

The source groups events by cadence. `SessionStart` and `SessionEnd` fire once per session. `UserPromptSubmit`, `Stop`, and `StopFailure` fire once per turn. `PreToolUse` and `PostToolUse` fire on every tool call, except `EndConversation` calls, which skip both. "No matcher" means any `matcher` field is silently ignored and the event fires on every occurrence.

| Event | Fires when | Matcher filters on | Can block? How |
| :-- | :-- | :-- | :-- |
| `SessionStart` | Session begins or resumes | `source`: `startup`, `resume`, `clear`, `compact`, `fork` | No. Exit 2 shows stderr to the user only. Context only |
| `Setup` | `--init-only`, or `-p` with `--init` / `--maintenance` | `init`, `maintenance` | No. Exit code, stderr, and JSON fields are ignored |
| `UserPromptSubmit` | Prompt submitted, before Claude processes it | No matcher | Yes. Exit 2 or `decision: "block"` blocks the prompt and erases it |
| `UserPromptExpansion` | A typed command expands into a prompt | `command_name` | Yes. Exit 2 or `decision: "block"` blocks the expansion |
| `PreToolUse` | Before a tool call executes | tool name | Yes. Exit 2, or `hookSpecificOutput.permissionDecision: "deny"` |
| `PermissionRequest` | Claude Code is about to show a permission prompt | tool name | Exit 2 is **not** honored. Deny via `hookSpecificOutput.decision.behavior: "deny"` |
| `PermissionDenied` | Auto mode denies a tool call | tool name | No. Can return `retry: true` |
| `PostToolUse` | Tool call succeeded | tool name | No, the tool already ran. Exit 2 shows stderr to Claude. `decision: "block"` adds `reason` |
| `PostToolUseFailure` | Tool call failed | tool name | No. Exit 2 shows stderr to Claude |
| `PostToolBatch` | Whole batch of parallel calls resolved, before the next model call | No matcher | Yes. Exit 2, `decision: "block"`, or `continue: false` stops the agentic loop |
| `Notification` | Claude Code sends a notification | notification type | No. Exit code and stderr are ignored |
| `MessageDisplay` | While assistant text streams to screen | No matcher | No. Can replace displayed text only |
| `SubagentStart` | Subagent spawned or resumed | agent type | No. Exit 2 shows stderr to user only. Context only |
| `SubagentStop` | Subagent finishes responding | agent type | Yes. Exit 2 or `decision: "block"` keeps it running |
| `TaskCreated` | Task being created via `TaskCreate` | No matcher | Yes. Exit 2 or `decision: "block"` rolls back creation |
| `TaskCompleted` | Task being marked completed | No matcher | Yes. Exit 2 prevents completion |
| `Stop` | Main agent finished responding | No matcher | Yes. Exit 2 or `decision: "block"` keeps Claude going |
| `StopFailure` | Turn ended due to an API error | error type | No. Output and exit code are ignored except `terminalSequence` |
| `TeammateIdle` | Agent-team teammate about to go idle | No matcher | Yes. Exit 2 keeps it working |
| `InstructionsLoaded` | CLAUDE.md or `.claude/rules/*.md` loaded | `load_reason` | No. Exit code is ignored |
| `ConfigChange` | Config file changes during session | config source | Yes. Exit 2 or `decision: "block"`, except `policy_settings` |
| `CwdChanged` | Working directory changes (e.g. `cd`) | No matcher | No |
| `DirectoryAdded` | Directory added via `/add-dir` or SDK `register_repo_root` | `slash_command`, `register_repo_root` | No. Already added |
| `FileChanged` | Watched file changes on disk | literal filenames (see below) | No |
| `WorktreeCreate` | Worktree being created | No matcher | Any non-zero exit fails creation |
| `WorktreeRemove` | Worktree being removed | No matcher | Any non-zero exit fails removal if the directory still exists |
| `PreCompact` | Before compaction | `manual`, `auto` | Yes. Exit 2 or `decision: "block"` |
| `PostCompact` | After compaction | `manual`, `auto` | No |
| `PreModelSwitch` | Before a requested model switch | canonical target model name | Yes. Exit 2, `decision: "block"`, `permissionDecision: "deny"`, or a timeout |
| `PostModelSwitch` | After the session model changes | canonical target model name | No |
| `Elicitation` | MCP server requests user input | MCP server name | Yes. Exit 2 denies |
| `ElicitationResult` | After user answers an elicitation | MCP server name | Yes. Exit 2 turns the action into `decline` |
| `SessionEnd` | Session terminates | reason: `clear`, `resume`, `logout`, `prompt_input_exit`, `other` | No |

`StopFailure` matcher values are `rate_limit`, `overloaded`, `authentication_failed`, `oauth_org_not_allowed`, `account_on_hold`, `billing_error`, `invalid_request`, `model_not_found`, `server_error`, `max_output_tokens`, `cloud_credential_error`, and `unknown`. `cloud_credential_error` requires v2.1.267+. `ConfigChange` sources are `user_settings`, `project_settings`, `local_settings`, `policy_settings`, and `skills`.

## Matchers
Source: https://code.claude.com/docs/en/hooks.md § "Matcher patterns"; https://code.claude.com/docs/en/hooks-guide.md § "Filter hooks with matchers"

The characters in a matcher decide how it is evaluated:

| Matcher value | Evaluated as |
| :-- | :-- |
| `"*"`, `""`, or omitted | Match everything |
| Only letters, digits, `_`, `-`, spaces, `,`, `\|` | Exact string, or a list of exact strings split on `\|` or `,` (surrounding whitespace allowed) |
| Any other character | JavaScript regex, **unanchored** (`RegExp.prototype.test`) |

- Because regexes are unanchored, `Edit.*` matches both `Edit` and `NotebookEdit`. Use `^Edit$` for a whole-string match.
- Version notes: comma separators and whitespace tolerance need v2.1.191+. Hyphens count as exact-match characters from v2.1.195. Before that, `code-reviewer` was an unanchored regex and also matched `senior-code-reviewer`.
- `FileChanged` and `StopFailure` use a narrower exact set: letters, digits, `_`, and `|` only. A hyphen, space, or comma sends the matcher down the regex path, and only `|` separates alternatives.
- Tool events match `tool_name`. `PreModelSwitch` and `PostModelSwitch` match the canonical name derived from `to_model`.
- The guide notes that matchers are case-sensitive.
- MCP tools are named `mcp__<server>__<tool>`. To match a whole server you must append `.*`, as in `mcp__memory__.*`. A bare `mcp__memory` is an exact string and matches no tool. Plugin-bundled servers use `mcp__plugin_<plugin>_<server>__<tool>`.
- Plugin subagent types look like `my-plugin:reviewer`. The colon puts the matcher on the regex path, so anchor it: `^my-plugin:reviewer$`.
- `FileChanged` is special. Its matcher is split on `|` into **literal filenames** that make up the watch list. The same value then filters hook groups by the changed file's basename. A regex such as `^\.env` would watch a file literally named `^\.env`, and `"*"` registers a literal file named `*`.

### The `if` field
Source: https://code.claude.com/docs/en/hooks.md § "Common fields"; https://code.claude.com/docs/en/hooks-guide.md § "Filter by tool name and arguments with the `if` field"

- `if` is set on an individual handler. It holds one permission rule, such as `"Bash(git *)"` or `"Edit(*.ts)"`. The handler process spawns only when the tool call matches the rule.
- There is no `&&`, `||`, or list syntax. For several conditions, use separate handlers.
- `if` is evaluated only on the tool events `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, and `PermissionDenied`. **On any other event, a handler with `if` never runs.**
- Bash matching:
  - Leading `VAR=value` assignments are stripped.
  - Each subcommand of `&&` chains is checked.
  - Commands inside `$()` and backticks are checked.
  - If the command name comes from a variable (`$TOOL git push`), the hook runs.
  - A pattern that specifies more than the command name, such as `Bash(git push *)`, runs the hook whenever `$()`, backticks, or `$VAR` appear.
- **Best-effort:** if Claude Code cannot determine which commands a Bash input runs, it runs the hook whatever the pattern. The source's instruction: "use the permission system rather than a hook to enforce a hard allow or deny."
- Path patterns: from v2.1.214, `"Edit(src/**)"` matches only `src` directly under the working directory. Use `"Edit(**/src/**)"` for any depth.

## Handler types
Source: https://code.claude.com/docs/en/hooks.md § "Hook handler fields"; https://code.claude.com/docs/en/hooks-guide.md § "How hooks work"

| `type` | What it does |
| :-- | :-- |
| `command` | Runs a command. Gets the JSON input on stdin and answers through its exit code, stdout, and stderr |
| `http` | POSTs the JSON input to a URL. The response body uses the same JSON output format |
| `mcp_tool` | Calls a tool on an already-connected MCP server. The tool's text output is treated like command stdout |
| `prompt` | Sends a prompt plus the input to a Claude model (Haiku by default) for a single-turn JSON decision |
| `agent` | Spawns a subagent with tools (Read, Grep, Glob, etc.) to verify conditions, up to 50 turns. **Experimental** |

- All matching hooks run **in parallel**.
- If the same handler is defined in more than one settings file, it runs once. A plugin's or skill's copy stays separate.
- Handlers run in the current directory with Claude Code's environment. If that directory no longer exists, command hooks fall back to the session start directory, then the project root, then home, then system temp. A warning goes to the debug log.

### Common handler fields
Source: https://code.claude.com/docs/en/hooks.md § "Common fields"

| Field | Notes |
| :-- | :-- |
| `type` | Required. One of the five types above |
| `if` | Optional permission-rule filter. Tool events only (see above) |
| `timeout` | Seconds. Defaults: 600 for `command`/`http`/`mcp_tool`, 30 for `prompt`, 60 for `agent`. The `command`/`http`/`mcp_tool` default is lowered to 30 on `UserPromptSubmit`, `PreModelSwitch`, and `PostModelSwitch`, and to 10 on `MessageDisplay`. Not enforced on `async: true` command hooks |
| `statusMessage` | Custom spinner text |
| `once` | If `true`, the hook is removed after its first **successful** run. A run that fails, blocks with exit 2, or times out stays registered. Honored **only in skill frontmatter**. Ignored in settings files and agent frontmatter |

### Command hooks: exec form vs shell form
Source: https://code.claude.com/docs/en/hooks.md § "Command hook fields"; https://code.claude.com/docs/en/hooks.md § "Exec form and shell form"

Command-specific fields are `command` (required), `args`, `async`, `asyncRewake`, and `shell`.

- **Exec form** is used when `args` is present, even as `"args": []`. `command` is resolved as an executable on `PATH` and spawned directly with `args` as the argument vector. No shell is involved and no tokenization happens on any platform. Apostrophes, `$`, and backticks pass through verbatim. Path placeholders are substituted into `command` and into each `args` element as plain strings. The source recommends exec form for any hook that references a path placeholder.
- **Shell form** is used when `args` is absent. The string goes to `sh -c` on macOS/Linux, to Git Bash on Windows, or to PowerShell when Git Bash is not installed. Pipes, `&&`, redirects, globs, and variable expansion work. Placeholders should be wrapped in double quotes.
- **Windows `.exe` rule:** in exec form, `command` must resolve to a real executable such as a `.exe`. The `.cmd` and `.bat` shims in `node_modules/.bin` (npm, npx, eslint, etc.) cannot be spawned without a shell. Either call `node` with the script path in `args`, or use shell form to run a shim by name.
- In exec form, `command` is only the executable. A bare name that contains whitespace alongside `args` logs a warning, because the spawn will fail. An absolute path with spaces (e.g. under `Program Files`) is fine.
- Both forms export `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`, and `CLAUDE_PLUGIN_DATA` as environment variables.
- Plugin `${user_config.*}` values are substituted in exec form only. A shell-form plugin hook that references them fails with an error (since v2.1.207). Shell form should read `$CLAUDE_PLUGIN_OPTION_<KEY>` instead.
- `asyncRewake: true` runs the hook in the background and wakes Claude on exit 2. The hook's stderr, or its stdout if stderr is empty, reaches Claude as a system reminder.

### Shell selection and PowerShell
Source: https://code.claude.com/docs/en/hooks.md § "Command hook fields"; https://code.claude.com/docs/en/hooks.md § "Windows PowerShell tool"; https://code.claude.com/docs/en/hooks.md § "PowerShell"

- The `shell` field accepts `"bash"` or `"powershell"`. The default is `"bash"`, or `"powershell"` on Windows when Git Bash is not installed. The field is **ignored when `args` is set**.
- `"shell": "powershell"` does not require `CLAUDE_CODE_USE_POWERSHELL_TOOL`, because hooks spawn PowerShell directly. Claude Code auto-detects `pwsh.exe` (PowerShell 7+) and falls back to `powershell.exe` (5.1).
- From v2.1.198, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_ROOT}`, and `${CLAUDE_PLUGIN_DATA}` in a PowerShell shell-form command are rewritten to `${env:NAME}`. They expand inside double quotes but not inside single quotes. Before v2.1.198 this rewrite applied only to plugin hooks.
- Do not write bare `$CLAUDE_PROJECT_DIR` in a PowerShell hook. PowerShell resolves it to `$null`, and Claude Code only logs a warning. `$env:CLAUDE_PROJECT_DIR` works on every version.
- The source's PowerShell examples use exec form: `"command": "powershell.exe"` with `args` of `-NoProfile`, `-ExecutionPolicy`, `Bypass`, `-File`, and the script path.
- On Windows, when the PowerShell tool is enabled, Claude routes shell commands through it. Without Git Bash, the Bash tool is not registered at all. Hooks that inspect shell commands should match `Bash|PowerShell`, because a `Bash`-only matcher never fires there.

### HTTP, MCP tool, prompt, and agent fields
Source: https://code.claude.com/docs/en/hooks.md § "HTTP hook fields"; https://code.claude.com/docs/en/hooks.md § "MCP tool hook fields"; https://code.claude.com/docs/en/hooks.md § "Prompt and agent hook fields"

- **HTTP:** `url` (required), `headers`, and `allowedEnvVars`. Header values can interpolate `$VAR` or `${VAR}`, but only for variables listed in `allowedEnvVars`. Unlisted references become empty strings. The body is sent with `Content-Type: application/json`.
- **MCP tool:** `server` and `tool` are required. `input` is optional, and its string values support `${path}` substitution from the input JSON (e.g. `"${tool_input.file_path}"`). The server must already be connected, and the hook never triggers OAuth or a connection flow. A disconnected server or an `isError: true` result is a non-blocking error. `mcp_tool` hooks are skipped on `Setup` always, and on `SessionStart` at launch, because no MCP client context exists yet. They do run on `SessionStart` after `/clear` or compaction.
- **Prompt/agent:** `prompt` is required. `$ARGUMENTS` stands in for the input JSON; if it is absent, the input is appended. Write `\$` for a literal dollar sign. `model` is optional. Prompt hooks also accept `continueOnBlock`, which agent hooks lack.

### Hooks in skills and agents
Source: https://code.claude.com/docs/en/hooks.md § "Hooks in skills and agents"

- Skill and subagent YAML frontmatter can carry a `hooks:` block in the same format as settings.
- **Subagent hooks** run only while that subagent runs and are removed when it finishes. A `Stop` hook declared there is converted to `SubagentStop`.
- **Skill hooks** are registered when the skill is invoked and keep running for the rest of the session, including later turns. `once: true` removes one after its first successful run.
- Trust: project-skill frontmatter hooks follow the settings-file trust rule and are registered on invocation, **including in a `-p` run in an untrusted folder**. Project-subagent frontmatter hooks run only after the workspace trust dialog is accepted for the folder the agent file came from, and a `-p` session does **not** count as accepting it. Before v2.1.218 these hooks could run from untrusted folders.

### Path placeholders and environment
Source: https://code.claude.com/docs/en/hooks.md § "Reference scripts by path"; https://code.claude.com/docs/en/hooks.md § "Common input fields"; https://code.claude.com/docs/en/hooks.md § "Persist environment variables"

- `${CLAUDE_PROJECT_DIR}` is the project root where the session started. It stays put when Claude enters a worktree. The input's `cwd` field is what follows Claude into worktrees and after `cd`.
- `${CLAUDE_PLUGIN_ROOT}` is the plugin install directory. `${CLAUDE_PLUGIN_DATA}` is the plugin's persistent data directory.
- `CLAUDE_ENV_FILE` is available only to `SessionStart`, `Setup`, `CwdChanged`, and `FileChanged` hooks. `export` lines appended to it persist into later Bash commands. For `CwdChanged` and `FileChanged`, those variables are cleared at the next `CwdChanged`.
- `$CLAUDE_EFFORT` holds the effort level. `$CLAUDE_CODE_REMOTE` is `"true"` in remote web environments. `$CLAUDE_CODE_BRIDGE_SESSION_ID` is set during an active Remote Control connection (v2.1.199+).
- There is no `$CLAUDE_MODEL`. To follow model changes, use the `from_model`/`to_model` fields on the model-switch events.
- A hook inherits the parent environment, minus the `OTEL_*` exporter variables. When `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, the variables that setting strips are also removed.

## Hook input
Source: https://code.claude.com/docs/en/hooks.md § "Common input fields"

Every event's JSON includes `session_id`, `transcript_path`, `cwd`, and `hook_event_name`. Some fields appear only on certain events or versions:

- `permission_mode` is one of `default`, `plan`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`. Manual mode arrives as `"default"`. Not every event receives it.
- `prompt_id` (v2.1.196+) and `scratchpad_dir` (v2.1.257+).
- `effort.level` appears on tool-context events when the model supports effort.
- `agent_id` and `agent_type` appear inside subagents or under `--agent`.

Command hooks read this JSON on stdin. HTTP hooks receive it as the POST body. `transcript_path` is written asynchronously and may lag. For the final assistant text, use `last_assistant_message` on `Stop`/`SubagentStop`. On macOS and Linux, command hooks have no controlling terminal and cannot open `/dev/tty`.

For `Write`, `Edit`, and `Read`, `tool_input.file_path` is always absolute. `~` and relative paths are expanded before hooks run. On Windows the path uses backslashes, so normalize separators before comparing. A forward-slash check silently never matches, and the tool call proceeds.

## Exit codes
Source: https://code.claude.com/docs/en/hooks.md § "Exit code output"; https://code.claude.com/docs/en/hooks.md § "Exit code 0"; https://code.claude.com/docs/en/hooks.md § "Exit code 2"; https://code.claude.com/docs/en/hooks.md § "Other exit codes"

- Claude Code reads JSON from stdout on **every** exit code, not only 0.
- **Exit 0** means success and is the exit code to use when printing JSON.
  - For most events, stdout goes to the debug log only.
  - `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart`, and `PostModelSwitch` are the exceptions: their plain-text stdout is added to Claude's context.
  - Stderr on exit 0 goes to the debug log only. Claude never sees it.
- **Exit 0 with no output is not approval.** It means "no decision", and the normal permission flow still applies. In the source's words: "The hook can deny the call, but staying silent doesn't approve it."
- **Exit 2** is a blocking error on events that can block.
  - JSON cannot override it: even `permissionDecision: "allow"` loses.
  - The block message is the JSON decision's reason if the JSON makes one, and stderr otherwise.
  - Since v2.1.214, exit 2 with schema-invalid JSON still blocks and uses stderr as the reason.
  - On `Elicitation`/`ElicitationResult`, an exit-2 hook's `hookSpecificOutput` is ignored.
- **Exit 1 and any other code do not block** for most events.
  - With valid, schema-passing JSON, the exit code is ignored and the JSON alone decides.
  - With invalid or unparseable JSON, or with plain-text or empty stdout, the result is a non-blocking error. The action proceeds and the transcript shows `<hook name> hook error` / `Failed with non-blocking status code:` plus the first stderr line.
  - The source's warning: for policy enforcement, use `exit 2`.
- A hook that cannot start (missing or non-executable script, e.g. shell exit 127) falls into the same non-blocking bucket. The source warns that a mistyped path "leaves the gate silently disabled".
- Worktree exceptions: any non-zero exit fails `WorktreeCreate`. Any non-zero exit fails `WorktreeRemove` if the directory still exists afterward.
- The source's advice is to pick one approach per hook: exit codes alone, or exit 0 with JSON.

### Stdout JSON parsing rule
Source: https://code.claude.com/docs/en/hooks.md § "Exit code 0"; https://code.claude.com/docs/en/hooks-guide.md § "Hook JSON has no effect"

Whether stdout is parsed as JSON depends on its first and last characters, after surrounding whitespace is trimmed:

- **Starts with `{` and ends with `}`:** parsed as JSON. One special case: if the output is several lines that each parse as JSON on their own and none of them sets an output field, the whole thing is plain text. If one of those lines does set a field, the whole output is a parse failure.
- **Starts with `{` but does not end with `}`:** plain text.
- **Anything else,** including a JSON array or a quoted JSON string: plain text.
- **Parse or schema failure** on standard-decision events: a non-blocking error on every exit code except 2. On the context-adding events, the text is not added. Before v2.1.248 such stdout was treated as plain text.
- **Shell-profile noise:** an unconditional `echo` in a sourced shell profile (Git Bash, or `BASH_ENV` pointing at `~/.bashrc`) prepends text. The output then no longer starts with `{` and the JSON is silently ignored.
- **Misplaced fields:** a field at the wrong nesting level, such as a top-level `permissionDecision` or `additionalContext`, is ignored without an error. The debug log shows `Hook JSON output had unrecognized keys`.

### Timeouts
Source: https://code.claude.com/docs/en/hooks.md § "Timeouts"; https://code.claude.com/docs/en/hooks.md § "SessionEnd"; https://code.claude.com/docs/en/hooks.md § "UserPromptSubmit"

- A `command`, `http`, or `mcp_tool` hook that reaches its timeout is canceled and its output discarded. On most events that means no decision.
- **On `PreToolUse`, a timed-out hook does not block.** The call continues through the normal permission flow, so a stalled hook is not a gate. An Agent SDK callback hook that times out does block.
- On `PreModelSwitch`, a timeout **blocks** the switch.
- On `UserPromptSubmit`, a timeout discards the output, including any `additionalContext`, and the prompt proceeds. An SDK callback timeout there blocks the prompt instead.
- `SessionEnd` hooks share a 1.5 s budget. A higher per-hook `timeout` raises the budget, up to 60 s, but timeouts on plugin hooks do not count. `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` overrides the budget explicitly.

### HTTP response handling
Source: https://code.claude.com/docs/en/hooks.md § "HTTP response handling"

| Response | Result |
| :-- | :-- |
| 2xx, empty body | Success. Same as exit 0 with no output |
| 2xx, JSON object body | Parsed as JSON output. A schema failure is a non-blocking error |
| 2xx, other body (e.g. plain text) | Non-blocking error. The text is not added to Claude's context |
| Non-2xx status | Non-blocking error |
| Connection failure | Non-blocking error |
| Timeout | Canceled, as described under Timeouts |

Status codes alone cannot block. To block, return 2xx with a JSON decision.

## JSON output
Source: https://code.claude.com/docs/en/hooks.md § "JSON output"

The output JSON has three layers:

- **Universal fields**, accepted by every event:

  | Field | Effect |
  | :-- | :-- |
  | `continue` | `false` stops Claude entirely and overrides any event-specific decision |
  | `stopReason` | Shown to the user with `continue: false`. It stays in the conversation, so Claude sees it too |
  | `suppressOutput` | Accepted but has no effect |
  | `systemMessage` | A warning shown to the user |
  | `terminalSequence` | An escape sequence that Claude Code writes itself. Only OSC `0`/`1`/`2`/`9`/`99`/`777` and BEL are allowed; anything else causes the whole field to be ignored. Interactive sessions only, never under `-p` or the SDK |

- **Top-level `decision` and `reason`**, used by some events. `"block"` is the only value `decision` takes.
- **`hookSpecificOutput`**, which must contain `hookEventName`.

Several events discard `systemMessage` and `continue`. Each event's section in the source says which.

### additionalContext: cap and phrasing
Source: https://code.claude.com/docs/en/hooks.md § "Add context for Claude"; https://code.claude.com/docs/en/hooks.md § "JSON output"

- `additionalContext` is wrapped in a system reminder at the point where the hook fired. It does not appear as a chat message.
  - `SessionStart`/`SubagentStart`: the start of the conversation.
  - Prompt events: alongside the prompt.
  - Tool events: next to the tool result.
  - `Stop`/`SubagentStop`: the end of the turn, and the turn continues.
  - `PostModelSwitch`: with the next request.
- **Cap: 10,000 characters.** It applies separately to each of `additionalContext`, `systemMessage`, and `initialUserMessage`, and to plain stdout as a whole. Over the cap, the text is saved to a file in the session directory and Claude gets the path plus a preview of up to 2,000 characters. No setting raises the cap, and Claude Code does not ask Claude to read the file.
- When several hooks return context, Claude receives all of it.
- **Phrasing:** write context as factual statements ("The deployment target is production"), not imperative system instructions. The source gives the reason: text framed as out-of-band system commands "can trigger Claude's prompt-injection defenses". Claude then surfaces the text to the user instead of treating it as context.
- For static conventions, the source prefers CLAUDE.md.
- On `--continue`/`--resume`, saved context from mid-session events is replayed rather than regenerated, so it can be stale. `SessionStart` re-runs with `source` set to `resume` or `fork`.

### Decision control by event
Source: https://code.claude.com/docs/en/hooks.md § "Decision control"; https://code.claude.com/docs/en/hooks.md § "PreToolUse decision control"; https://code.claude.com/docs/en/hooks.md § "PermissionRequest decision control"; https://code.claude.com/docs/en/hooks.md § "PostToolUse decision control"; https://code.claude.com/docs/en/hooks.md § "Stop decision control"

| Events | Pattern | Key fields |
| :-- | :-- | :-- |
| UserPromptSubmit, UserPromptExpansion, PostToolUse, PostToolUseFailure, PostToolBatch, Stop, SubagentStop, ConfigChange, PreCompact | Top-level `decision` | `decision: "block"`, `reason` |
| TeammateIdle, TaskCompleted | Exit code or `continue: false` | Exit 2 blocks with stderr as feedback |
| TaskCreated | Exit code or `decision` | Exit 2 or `"block"` cancels the task. `continue: false` is ignored |
| PreToolUse | `hookSpecificOutput` | `permissionDecision` (`allow`/`deny`/`ask`/`defer`), `permissionDecisionReason`, `updatedInput`, `additionalContext` |
| PreModelSwitch | `hookSpecificOutput` or `decision` | `permissionDecision` (`allow`/`deny`/`ask`). No `defer` |
| PermissionRequest | `hookSpecificOutput.decision` | `behavior` (`allow`/`deny`), `updatedInput`, `updatedPermissions`, `message`, `interrupt` |
| PermissionDenied | `hookSpecificOutput` | `retry: true` |
| WorktreeCreate | Path return | Command hooks print the path as the last non-empty stdout line. HTTP hooks return `worktreePath` |
| Elicitation, ElicitationResult | `hookSpecificOutput` | `action` (`accept`/`decline`/`cancel`), `content` |
| MessageDisplay | `hookSpecificOutput` | `displayContent`, which changes the display only |
| SessionStart, SubagentStart, PostModelSwitch | Context only | `additionalContext`. SessionStart also takes `initialUserMessage`, `sessionTitle`, `watchPaths`, `reloadSkills` |
| Setup, Notification, SessionEnd, PostCompact, InstructionsLoaded, StopFailure, CwdChanged, DirectoryAdded, FileChanged | None | Side effects only |

**PreToolUse:**

- If several hooks disagree, precedence is `deny` > `defer` > `ask` > `allow`.
- `allow` skips the prompt, but deny and ask rules are still evaluated.
- `updatedInput` replaces the entire input. Permission rules are evaluated against the rewritten input. When several hooks return `updatedInput`, the last one to finish wins, which is non-deterministic.
- The `permissionDecisionReason` for a `deny` goes to Claude. For `allow` or `ask`, it goes to the user only.
- A hook `ask` forces a prompt even in auto mode.
- `defer` is honored only in `-p` mode, and only for a single tool call in the turn.
- The top-level `decision`/`reason` fields are deprecated for PreToolUse; `approve` and `block` map to `allow` and `deny`.

**PermissionRequest:**

- Exit 2 without a `decision` object leaves the flow unchanged and discards stderr.
- An `allow` does not override a matching deny rule.
- `updatedPermissions` entries are `addRules`, `replaceRules`, `removeRules`, `setMode`, `addDirectories`, and `removeDirectories`. Their `destination` is `session`, `localSettings`, `projectSettings`, or `userSettings`, so a hook can write rules into settings files.
- `setMode` to `bypassPermissions` works only if bypass was already available at launch, and it is never persisted as `defaultMode`.

**PostToolUse:**

- `decision: "block"` adds `reason` next to the result. Claude still sees the original output.
- `updatedToolOutput` replaces what Claude sees, but only if it matches the tool's output shape. The tool has already run, and telemetry records the original.
- `classifierContext` (v2.1.236+) sends a note to the auto-mode classifier. The notes for one call are capped at 2,000 characters combined.

**Stop and SubagentStop:**

- `decision: "block"` requires a `reason`, which Claude receives as the reason to keep going.
- `hookSpecificOutput.additionalContext` continues the turn as non-error "Stop hook feedback".
- `stop_hook_active` is `true` when Claude is already continuing because of a Stop hook.
- Claude Code overrides the hook after **8 consecutive blocks**. `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` raises the cap.

## Selected per-event notes
Source: https://code.claude.com/docs/en/hooks.md § "Hook events"

- **SessionStart** supports only `command` and `mcp_tool`. It runs in the background at launch, but Claude's first response waits for it. Resumed or forked sessions (v2.1.251+) also get `seconds_since_last_response`, `context_tokens`, `prompt_cache_likely_expired`, and `estimated_cache_write_usd`. `reloadSkills: true` re-scans skills after the hook finishes.
- **Setup** supports only `command` hooks. Under `-p`, its output is visible only as `hook_response` events with `--output-format stream-json --verbose`.
- **InstructionsLoaded** runs asynchronously for observability. Inputs are `file_path`, `memory_type` (`User`/`Project`/`Local`/`Managed`), `load_reason`, `globs`, `trigger_file_path`, and `parent_file_path`. It does not fire when `AGENTS.md` is read directly through the Project instructions setting. It does fire when CLAUDE.md imports `AGENTS.md` (`load_reason: include`) or is a symlink to it.
- **UserPromptExpansion** covers typing `/skillname` directly, which bypasses `PreToolUse` on the `Skill` tool.
- **PreToolUse** does not fire for files attached with `@` in the prompt, because no tool call happens. The source recommends a `Read` deny rule instead. MCP tool inputs carry `mcp_server.source` (v2.1.274+), and the source says to base trust on `source`, not on the name.
- **PermissionRequest** runs even where no prompt can be shown, such as background subagents under `-p`. There, if no hook decides, the call is denied. It does not run for sandbox network requests. Agent hooks are skipped on this event.
- **PermissionDenied** fires only for auto-mode denials. It does not fire for manual denials, PreToolUse blocks, or `deny` rule matches.
- **TaskCompleted** fires on `TaskUpdate` completion and when a teammate ends its turn with tasks still in progress. `continue: false` is ignored when `TaskUpdate` triggered the event.
- **ConfigChange** fires for settings files, `managed-settings.json` or `managed-settings.d/`, and skill files. It does not fire for server-managed settings, macOS managed preferences, or the Windows registry. `policy_settings` cannot be blocked, though blocking hooks still fire for it. A blocked change surfaces no message to the user or to Claude; only a debug-log line is written. `reason` is "Accepted but never shown".
- **PreCompact:** blocking a proactive auto-compaction skips it. Blocking a recovery compaction after a context-limit error surfaces that error.
- **PreModelSwitch** (v2.1.251+) does not fire for automatic fallback or for restoring the model on resume. When the target has no canonical name, every PreModelSwitch hook runs regardless of matcher. Outside interactive `/model`, `ask` is treated as a refusal.
- **WorktreeCreate** replaces `git worktree` entirely, so `.worktreeinclude` is not processed. Absolute paths containing `.`/`..`, and paths through a symlink below the repo root, are refused (v2.1.216+).
- **MessageDisplay** is display-only. The transcript and what Claude sees keep the original text. The default timeout is 10 s, and on failure the original text is shown.

## Prompt and agent hooks
Source: https://code.claude.com/docs/en/hooks.md § "Prompt-based hooks"; https://code.claude.com/docs/en/hooks.md § "Response schema"; https://code.claude.com/docs/en/hooks.md § "Agent-based hooks"

Support for all five handler types varies by event:

| Events | Types supported |
| :-- | :-- |
| `PermissionDenied`, `PostToolBatch`, `PostToolUse`, `PostToolUseFailure`, `PreToolUse`, `Stop`, `SubagentStop`, `TaskCompleted`, `TaskCreated`, `TeammateIdle`, `UserPromptExpansion`, `UserPromptSubmit` | All five |
| `PermissionRequest` | Everything except `agent` |
| `SessionStart`, `Setup` | Only `command` and `mcp_tool` |
| All other events | `command`, `http`, `mcp_tool` |

The model replies with `{"ok": bool, "reason": "...", "impossible": bool}`. What `ok: false` does depends on the event:

- **`Stop`/`SubagentStop`:** the reason is fed back and the turn continues, unless `impossible: true`, in which case the stop is allowed.
- **`PreToolUse`:** the call is denied and the turn ends by default. `continueOnBlock: true` returns the reason to Claude as a tool error instead.
- **`PostToolUse`:** the turn ends by default. `continueOnBlock: true` feeds the reason back.
- **`PostToolBatch`, `UserPromptSubmit`, `UserPromptExpansion`:** the turn ends.
- **`PermissionRequest` and `PermissionDenied`:** `ok: false` has no effect.

Agent hooks behave like prompt hooks with `continueOnBlock: true`. They have no `continueOnBlock` field and no `impossible` field. The source advises using command hooks for production workflows.

## Async hooks
Source: https://code.claude.com/docs/en/hooks.md § "Run hooks in the background"; https://code.claude.com/docs/en/hooks.md § "Limitations"

- `"async": true` is available on `command` hooks only. The hook runs in the background.
- Async hooks cannot block or decide: `decision`, `permissionDecision`, and `continue` have no effect.
- `additionalContext` and `systemMessage` are delivered to Claude on the next turn and are not shown to the user.
- `timeout` is not enforced once an async hook is running. It is enforced on `asyncRewake` hooks.
- Under `-p`, async hooks still running at teardown are killed with outcome `cancelled`.
- There is no deduplication across repeated firings. Each firing is a separate process.

## Combining multiple hooks
Source: https://code.claude.com/docs/en/hooks-guide.md § "Combine results from multiple hooks"; https://code.claude.com/docs/en/hooks-guide.md § "Limitations"

- Every matching hook runs to completion before results are merged. One hook's `deny` does not stop its siblings or their side effects.
- The most restrictive PreToolUse decision wins.
- All `additionalContext` values are passed to Claude.

## Hooks and permission modes
Source: https://code.claude.com/docs/en/hooks-guide.md § "Hooks and permission modes"

`PreToolUse` fires before any permission-mode check, in every mode including `dontAsk`. A hook `deny` blocks even under `bypassPermissions` or `--dangerously-skip-permissions`. A hook `allow` does not get past deny rules from settings, and it cannot suppress prompts for MCP tools marked `requiresUserInteraction` or for org-`ask` connector tools. The guide's summary: hooks "can tighten restrictions but not loosen them past what permission rules allow."

## Security and workspace trust
Source: https://code.claude.com/docs/en/hooks.md § "Security considerations"; https://code.claude.com/docs/en/hooks.md § "Workspace trust"; https://code.claude.com/docs/en/hooks.md § "Security best practices"

- Command hooks run with the user's full permissions.
- **Interactive sessions:** hooks from **every** settings file, the user's own `~/.claude/settings.json` included, are held back until the workspace trust dialog is accepted for the folder or for a parent directory whose trust covers it.
- **`-p` and SDK sessions:** no dialog is shown and the folder is treated as trusted. A repository's committed `.claude/settings.json` hooks therefore run in folders the user has never trusted. The source's mitigations are to review `.claude/` first, use `--bare`, or pass `--settings '{"disableAllHooks": true}'`.
- The frontmatter trust rules are covered under "Hooks in skills and agents" above.
- The source's best practices:
  - validate inputs
  - quote shell variables
  - block `..` path traversal
  - use absolute paths
  - skip sensitive files such as `.env`, `.git/`, and keys

## Disabling hooks
Source: https://code.claude.com/docs/en/hooks.md § "Disable or remove hooks"; https://code.claude.com/docs/en/hooks-guide.md § "Configure hook location"

- To remove a hook, delete its entry. There is no way to disable a single hook while keeping it in the config.
- `"disableAllHooks": true` turns off hooks. The effective value is whatever remains after settings precedence, so a project-level `false` overrides a user-level `true`.
- `--settings '{"disableAllHooks": true}'` takes precedence over project and local settings for one run.
- **Managed precedence:** `disableAllHooks` set in user, project, or local settings cannot disable managed hooks. Only `disableAllHooks` set in managed settings can.

## The `/hooks` menu
Source: https://code.claude.com/docs/en/hooks.md § "The `/hooks` menu"; https://code.claude.com/docs/en/hooks-guide.md § "Set up your first hook"

- `/hooks` opens a **read-only** browser. To add, change, or remove hooks, edit the settings JSON or ask Claude to do it.
- It lists events with hook counts, lets you drill into matchers, and shows each handler with a `[type]` prefix and a source label: `User Settings`, `Project Settings`, `Local Settings`, `Plugin Hooks`, or `Session Hooks`.
- The source's list of labels does not include managed or frontmatter sources.

## Debugging
Source: https://code.claude.com/docs/en/hooks.md § "Debug hooks"; https://code.claude.com/docs/en/hooks-guide.md § "Debug techniques"; https://code.claude.com/docs/en/hooks-guide.md § "Hook not firing"

- `claude --debug-file <path>` writes the debug log to a known file. `claude --debug` writes to `~/.claude/debug/<session-id>.txt`, and `--debug` does not print to the terminal. `/debug` enables logging mid-session.
- `CLAUDE_CODE_DEBUG_LOG_LEVEL=verbose` adds matcher-count and query-matching lines.
- `Ctrl+O` opens the transcript view. A successful hook shows nothing there. A block shows its reason or stderr, except on `ConfigChange` and `Elicitation`, which surface no message. A non-blocking error shows a `<hook name> hook error` notice.
- To test a hook by hand, pipe sample JSON into the script and check `$?`.
- On macOS and Linux, scripts must be executable.

## Not found in source
Source: https://code.claude.com/docs/en/hooks.md § "Hooks reference"; https://code.claude.com/docs/en/hooks-guide.md § "Automate actions with hooks"

Every MUST-COVER item for this file is supported by the pinned sources. None had to be omitted.
