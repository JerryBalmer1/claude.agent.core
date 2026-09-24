---
verified: 2026-09-23
sources:
  - https://code.claude.com/docs/en/sub-agents.md
  - https://code.claude.com/docs/en/agents.md
  - https://code.claude.com/docs/en/agent-teams.md
  - https://code.claude.com/docs/en/workflows.md
  - https://code.claude.com/docs/en/cross-session-messaging.md
  - https://code.claude.com/docs/en/worktrees.md
scope: Claude Code's mechanisms for running agents in parallel (subagents, forks, agent teams, dynamic workflows, cross-session messaging, worktrees) as those six pages describe them; it does not cover agent view, projects, routines, the full hooks reference, or the settings reference beyond what these pages state.
---

# Agents and parallelism

Claude Code has several ways to split work across more than one Claude. They differ in who
coordinates the work (Claude turn by turn, a lead session, or a script), whether the workers can
talk to each other, and whether their file edits are isolated. Every worker in every approach is a
Claude session; another tool can take part only when exposed to Claude as an MCP server.
Running several agents at once multiplies token usage.

| Mechanism | What it is | Reach for it when | Source |
| :-- | :-- | :-- | :-- |
| Subagent | A worker inside one session with its own context window; returns a summary to its caller | A side task would flood the main context with output you will not reuse; you want tool limits on a worker | sub-agents.md § "Create custom subagents"; agents.md § "Choose an approach" |
| Agent team | A lead session plus separate teammate sessions, a shared task list, and a mailbox. Experimental, off by default | Workers must share findings, challenge each other, and self-coordinate | agent-teams.md § "Compare with subagents" |
| Dynamic workflow | A JavaScript script the runtime executes, spawning many subagents; the plan lives in code | The job outgrows a handful of subagents, or findings must be cross-checked | workflows.md § "When to use a workflow" |
| Cross-session messaging | `ListAgents` + `SendMessage` between your independent sessions (local, other machine, cloud) | Sessions you run yourself need to pass a finding or status mid-task | cross-session-messaging.md § "When to use cross-session messaging" |
| Worktree | A separate git checkout per session or subagent | Parallel workers would otherwise edit the same files | worktrees.md § "Run parallel sessions with worktrees"; agents.md § "Choose an approach" |

Note: agent teams do not put teammates in worktrees; partition files by teammate instead
(agents.md § "Choose an approach").

## The parallel-work overview page

Source: https://code.claude.com/docs/en/agents.md § "Run agents in parallel"; https://code.claude.com/docs/en/agents.md § "Choose an approach"; https://code.claude.com/docs/en/agents.md § "Check on running work"

- The page lists five approaches: subagents, agent view (`claude agents`, research preview), agent
  teams (experimental, disabled by default), projects (claude.ai/code or desktop, public beta on Pro
  and Max), and dynamic workflows.
- Three supporting tools are not themselves ways to run agents: worktrees, cross-session messaging,
  and `/batch` (a skill that splits one large change into 5 to 30 worktree-isolated subagents, each
  opening a pull request).
- Not parallelism features in this sense: background bash commands, forked subagents (a way to spawn
  a subagent, started with `/subtask`; `/fork` copies the whole session into a background session),
  and routines (scheduled cloud runs).
- Communication paths: subagents report to the conversation that spawned them; agent-view sessions
  report only to you; teammates message each other directly and share a task list when they have the
  Task tools; your own sessions use cross-session messaging.
- Checking on work: `claude agents` (agent view), `/tasks` (background items of the current
  session, including finished subagents), `/workflows` (workflow runs). `/agents` no longer opens a
  panel as of v2.1.198 and is distinct from `claude agents`.

## Subagents

Source: https://code.claude.com/docs/en/sub-agents.md § "Create custom subagents"

### Definition file format

Source: https://code.claude.com/docs/en/sub-agents.md § "Write subagent files"; https://code.claude.com/docs/en/sub-agents.md § "Frontmatter reference"

- A subagent is a Markdown file: YAML frontmatter between `---` markers, then a body that becomes
  the subagent's system prompt.
- The subagent gets only that system prompt plus basic environment details (such as working
  directory), not the Claude Code system prompt.
- Only `name` and `description` are required. Field names are camelCase and must match exactly; an
  unknown field is silently ignored.
- Claude Code watches `~/.claude/agents/` and `.claude/agents/` and picks up edits within seconds.
  A restart is still needed for: a newly created `agents` directory, agents under `--add-dir`
  directories, and sessions started with `--disable-slash-commands`.
- In non-interactive mode, `--append-subagent-system-prompt` (v2.1.205+) or
  `--append-subagent-system-prompt-file` (v2.1.261+) appends text to every subagent's system prompt,
  nested ones included, except forks.

### Frontmatter fields

Source: https://code.claude.com/docs/en/sub-agents.md § "Frontmatter reference"

| Field | Req. | Meaning (paraphrased) |
| :-- | :-- | :-- |
| `name` | yes | Unique identifier; hooks see it as `agent_type`. Filename need not match. Must not contain `:` (reserved for plugin scoping); such files are not loaded (v2.1.218+) |
| `description` | yes | When Claude should delegate to this subagent |
| `tools` | no | Allowlist, comma string or YAML list. Omitted means every tool available to subagents. If nothing resolves, launch usually fails. Use `skills`, not `Skill`, to preload skills |
| `disallowedTools` | no | Denylist removed from the inherited or listed set. An entry with a specifier such as `Bash(git push *)` removes the whole tool |
| `model` | no | `sonnet`, `opus`, `haiku`, `fable`, a full model ID, or `inherit` |
| `permissionMode` | no | `default`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, `plan`; `manual` aliases `default` (v2.1.200+). Ignored for plugin subagents |
| `maxTurns` | no | Turn cap; at the cap output is returned marked partial (v2.1.246+) and the subagent can be resumed |
| `skills` | no | Skills whose full content is injected at startup. Does not restrict which skills can be invoked |
| `mcpServers` | no | Named references to configured servers or inline server definitions. Ignored for plugin subagents |
| `hooks` | no | Lifecycle hooks scoped to this subagent. Ignored for plugin subagents |
| `memory` | no | Persistent memory scope: `user`, `project`, or `local` |
| `background` | no | `true` keeps it in the background even when Claude asks for foreground |
| `omitClaudeMd` | no | `true` skips user, project, and local CLAUDE.md; managed policy files still load (except for managed subagents). Ignored under `--agent`/`agent` setting. v2.1.271+ |
| `effort` | no | `low`, `medium`, `high`, `xhigh`, `max`; overrides session effort; availability depends on model |
| `isolation` | no | `worktree` runs it in a temporary git worktree branched by default from the default branch, not the parent's `HEAD`; auto-removed if no changes |
| `color` | no | `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan` |
| `initialPrompt` | no | First user turn auto-submitted when the agent is the main session agent (`--agent` or `agent` setting). Ignored for plugin subagents |
| `experimental` | no | Map; only `cacheTtl` (`5m` or `1h`) is read, from subagent files only. v2.1.248+ |

The `--agents` CLI JSON takes `prompt` (the system prompt) plus `description`, `tools`,
`disallowedTools`, `model`, `permissionMode`, `mcpServers`, `hooks`, `maxTurns`, `skills`,
`initialPrompt`, `memory`, `effort`, `background`, `omitClaudeMd`, and `isolation`. `color` and
`experimental` are ignored there. Each top-level JSON key is the agent's name
(sub-agents.md § "Choose the subagent scope").

### Files that are silently skipped

Source: https://code.claude.com/docs/en/sub-agents.md § "Subagent files Claude Code skips"

A project, user, managed, or `--add-dir` agent file is skipped without an in-session report when:
it has no `name` (treated as documentation); the opening `---` is not line 1; `name` starts with `-`
or contains `:`; it has `name` but no `description`; or the YAML fails to parse. Most reasons go to
the debug log (`--debug`). A plugin agent with no `name` or bad YAML still loads under its filename.
`claude plugin validate <dir>` (v2.1.233+) finds unparsable frontmatter in an `agents` directory.

### Where subagent files live and precedence

Source: https://code.claude.com/docs/en/sub-agents.md § "Choose the subagent scope"

| Priority | Location | Scope |
| :-- | :-- | :-- |
| 1 (highest) | Managed settings (`.claude/agents/` in the managed settings directory) | Organization |
| 2 | `--agents` CLI JSON | Current session only, not saved to disk |
| 3 | `.claude/agents/` | Current project |
| 4 | `~/.claude/agents/` | All your projects |
| 5 (lowest) | Plugin `agents/` directory | Where the plugin is enabled |

- Same `name` in several locations: the higher-priority one wins.
- Project agents are found by walking up from the working directory to the repo root; for
  duplicates across nested directories the closest wins (v2.1.178+).
- Directories are scanned recursively; subfolders do not change identity (only `name` does).
  Duplicate names inside one directory tree: one is loaded, chosen by filesystem read order.
- `--add-dir` / `/add-dir` directories also contribute their `.claude/agents/`.
- Plugin subfolders become part of the scoped id, e.g. `my-plugin:review:security`.
- Plugin subagents ignore `hooks`, `mcpServers`, and `permissionMode` for security reasons.
- Subagent definitions from any scope can be referenced when spawning agent-team teammates.

### Built-in subagents

Source: https://code.claude.com/docs/en/sub-agents.md § "Built-in subagents"

| Agent | Model | Tools | Notes |
| :-- | :-- | :-- | :-- |
| Explore | Inherits main model, capped at Opus on the Claude API (v2.1.198+) | Read-only; Write and Edit denied | Skips CLAUDE.md and git status. Thoroughness: quick, medium, very thorough. One-shot, cannot be resumed |
| Plan | Inherits main model | Read-only; Write and Edit denied | Used in plan mode. Skips CLAUDE.md and git status. One-shot |
| general-purpose | `CLAUDE_CODE_SUBAGENT_MODEL` if set and nothing else assigns one, else main model | Every tool available to subagents | Exploration plus modification |
| claude | Follows subagent model order | Every tool available to subagents | Catch-all; default agent for a dispatched background session |
| statusline-setup | Sonnet | not stated | Used by `/statusline` |
| claude-code-guide | Haiku | not stated | Questions about Claude Code features |

- All built-ins inherit the parent conversation's permissions.
- A user or project agent named `Explore` overrides the built-in and keeps its own `model`.
- To restrict: deny `Agent(<type>)` in `permissions.deny`; deny `Agent` entirely to stop all
  delegation; `CLAUDE_CODE_DISABLE_EXPLORE_PLAN_AGENTS=1` removes only Explore and Plan (v2.1.198+);
  `CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS=1` removes all built-ins in non-interactive mode and SDK.
- An Agent call without `subagent_type` fails with `subagent_type is required` if there is no
  `general-purpose` to fall back on.

### Model selection

Source: https://code.claude.com/docs/en/sub-agents.md § "Choose a model"; https://code.claude.com/docs/en/sub-agents.md § "Run every subagent on one model"

Resolution order:

1. Per-invocation `model` parameter on the Agent call.
2. Definition's `model` frontmatter (`inherit` means the main model).
3. `CLAUDE_CODE_SUBAGENT_MODEL` env var.
4. Main conversation's model.

- A family alias that matches the main model's family resolves to the main model exactly
  (including `[1m]`). An alias inside `CLAUDE_CODE_SUBAGENT_MODEL` always resolves to the alias target.
- Before v2.1.251 the env var came first. Setting it to `inherit` equals unset.
- Values are checked against the org `availableModels` allowlist; blocked values are substituted
  and interactive sessions warn.
- Subagents inherit the main session's extended thinking setting (v2.1.198+); there is no
  per-subagent thinking setting.
- `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` (v2.1.257+) makes one model apply to every subagent,
  teammate, and workflow agent: definition `model` fields are ignored and Claude cannot pass one.
  Forks, and skills run in a subagent with `model: inherit`, still use the main model.
- `/tasks` shows the model (and effort, when set) on each running subagent's row (v2.1.242+).

### Tool access

Source: https://code.claude.com/docs/en/sub-agents.md § "Available tools"; https://code.claude.com/docs/en/sub-agents.md § "Restrict which subagents can be spawned"

- Subagents inherit built-in and MCP tools of the main conversation, then two filters apply. Forks
  skip both filters.
- Filter 1 always removes: `Agent` (at depth limit), `AskUserQuestion`, `EndConversation`,
  `EnterPlanMode`, `ExitPlanMode` (unless `permissionMode: plan`), `ScheduleWakeup`,
  `WaitForMcpServers`, `Workflow`. A subagent therefore cannot launch a workflow.
- Filter 2 (background subagents, which is the default): keeps all MCP tools but only these
  built-ins: `Read`, `Grep`, `Glob`, `LSP`, `Bash`, `PowerShell`, `Edit`, `Write`, `NotebookEdit`,
  `WebFetch`, `WebSearch`, `TodoWrite`, `Skill`, `ToolSearch`, `EnterWorktree`, `ExitWorktree`,
  `Monitor`, `TaskStop`, `SendMessage`, `Artifact`, plus `SubagentHandback` where used. The same
  definition can resolve differently in foreground vs background.
- Teammates additionally keep `TaskCreate`, `TaskGet`, `TaskList`, `TaskUpdate`, `CronCreate`,
  `CronDelete`, `CronList`.
- When both `tools` and `disallowedTools` are set, the deny list applies first. MCP patterns
  `mcp__<server>` / `mcp__<server>__*` work in both; `mcp__*` in `disallowedTools` drops all MCP.
- To block specific commands but keep the tool, use a `permissions.deny` rule, which applies to the
  main conversation and subagents alike.
- `Agent(worker, researcher)` in `tools` is a spawn allowlist only for an agent run as the main
  thread with `claude --agent`. In a subagent definition the parenthesized list is ignored; listing
  `Agent` just allows nesting. Omitting `Agent` forbids spawning. `Task(...)` still works as an alias
  (renamed in 2.1.63).

### MCP servers scoped to a subagent

Source: https://code.claude.com/docs/en/sub-agents.md § "Scope MCP servers to a subagent"

- Inline servers (types `stdio`, `http`, `sse`, `ws`, same schema as `.mcp.json`) connect when the
  subagent starts and disconnect when it ends; string references share the parent's connection.
  Inline servers keep their tools out of the main conversation.
- Inline servers from a project or `--add-dir` `.claude/agents/` file load only after that exact
  folder is trusted (v2.1.238+); parent-folder trust and `-p`/SDK auto-trust do not count.
- No folder-trust check for: name references, `~/.claude/agents/` files, `--agents`/SDK `agents`
  definitions, managed definitions.
- `--strict-mcp-config`, `--bare`, managed MCP config, and `allowedMcpServers`/`deniedMcpServers`
  apply to frontmatter servers (v2.1.153+). `--strict-mcp-config` does not filter `--agents`/SDK
  inline servers.

### Permission modes

Source: https://code.claude.com/docs/en/sub-agents.md § "Permission modes"

- Unset `permissionMode` inherits the main conversation's mode.
- If the main conversation is in `bypassPermissions`, `acceptEdits`, or auto, the subagent uses
  that same mode and the frontmatter value is ignored. Under auto, the classifier checks subagent
  tool calls with the main rules and also reviews the subagent's work and final report before
  delivery.
- If the main conversation is in `default`, `dontAsk`, or `plan`, the frontmatter mode applies,
  except `bypassPermissions`, which is refused (keeps the main mode; v2.1.267+).
- `dontAsk` auto-denies prompts but still denies `AskUserQuestion`, MCP tools marked
  `requiresUserInteraction`, and org-`ask` connector tools even if allowed.

### Skills and persistent memory

Source: https://code.claude.com/docs/en/sub-agents.md § "Preload skills into subagents"; https://code.claude.com/docs/en/sub-agents.md § "Enable persistent memory"

- `skills` injects full skill content at startup. Skills with `disable-model-invocation: true`
  (including bundled `/verify`) cannot be preloaded. Missing or disabled skills are skipped with a
  debug-log warning. To forbid skill use, remove `Skill` from tools.
- `memory` directories: `user` → `~/.claude/agent-memory/<name>/`; `project` →
  `.claude/agent-memory/<name>/`; `local` → `.claude/agent-memory-local/<name>/`. `project` is the
  recommended default.
- With memory on, the prompt gets memory instructions and the first 200 lines or 25KB of
  `MEMORY.md`, and Read/Write/Edit are enabled automatically. Turning auto memory off
  (`autoMemoryEnabled` or `CLAUDE_CODE_DISABLE_AUTO_MEMORY`) disables the field.

### Hooks for subagents

Source: https://code.claude.com/docs/en/sub-agents.md § "Define hooks for subagents"; https://code.claude.com/docs/en/sub-agents.md § "Hooks in subagent frontmatter"; https://code.claude.com/docs/en/sub-agents.md § "Project-level hooks for subagent events"; https://code.claude.com/docs/en/sub-agents.md § "Conditional rules with hooks"

- Hooks from settings files, managed policy, and plugins all fire inside subagents; a settings
  `PreToolUse` hook runs before every subagent tool call.
- Frontmatter hooks run only while that agent is active, both as a subagent and as the main agent
  via `--agent`. All hook events are supported; a frontmatter `Stop` becomes `SubagentStop` at
  runtime.
- Frontmatter hooks of a project agent run only after its folder is trusted; parent trust and `-p`
  do not count (v2.1.218+). Untrusted: the subagent runs but its hooks are skipped. User-level and
  `--agents` hooks need no trust step.
- Settings events `SubagentStart` and `SubagentStop` match on agent type name (frontmatter `name`,
  or plugin-scoped id). A colon-containing id is an unanchored regex; anchor with `^...$`.
  Hyphenated names match exactly on v2.1.195+.
- Pattern shown: a `PreToolUse` hook that exits 2 to block a disallowed Bash command; on Windows use
  PowerShell scripts with `shell: powershell`.

### Invoking and running subagents

Source: https://code.claude.com/docs/en/sub-agents.md § "Invoke subagents explicitly"; https://code.claude.com/docs/en/sub-agents.md § "Run subagents in foreground or background"; https://code.claude.com/docs/en/sub-agents.md § "Subagent names"

- Three ways: name it in natural language (Claude decides), @-mention it (guaranteed; `@agent-<name>`
  also works), or run the whole session as it with `--agent <name>` or the `agent` setting (CLI flag
  wins). Under `--agent` the agent prompt replaces the default system prompt entirely; CLAUDE.md
  still loads even with `omitClaudeMd`.
- Foreground subagents block and pass permission prompts to you. Background subagents surface
  prompts in the main session naming the subagent; Esc denies that one call. A lasting grant given
  there applies to the whole session.
- Foreground/background decision: in-process teammate's subagents are foreground;
  `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` forces foreground; with fork mode on (interactive default)
  everything runs in background and `run_in_background` is removed; with fork mode off (default in
  `-p` and SDK) background is default unless Claude needs the result.
- Claude may name a subagent (`name` parameter) on its own; names make it addressable. With agent
  teams enabled, a named non-fork subagent without call-level `isolation` launches as a teammate.

### What a subagent sees

Source: https://code.claude.com/docs/en/sub-agents.md § "What loads at startup"

| Loads | Does not load (non-fork) |
| :-- | :-- |
| Its own system prompt plus environment details | The Claude Code system prompt |
| The delegation message Claude writes | Your conversation history, invoked skills, files already read |
| Full CLAUDE.md hierarchy incl. managed policy and AGENTS.md (except Explore/Plan, or `omitClaudeMd`) | Output style |
| Git status snapshot (except Explore/Plan; not configurable otherwise) | Main conversation's auto memory |
| Preloaded `skills` | The parent's context window size (its own model decides) |
| Sibling roster of named agents, when it has `SendMessage` (v2.1.206+, snapshot at start) | |

If a rule must reach a subagent, restate it in the delegation prompt.

### Output scanning and trust of reports

Source: https://code.claude.com/docs/en/sub-agents.md § "Subagent output scanning"

- Since v2.1.210, each final report is scanned before Claude reads it. The scan never removes text;
  it backslash-escapes imitations of harness output (`<system-reminder>`, `Human:`, `Assistant:`)
  and prepends a `[harness: subagent output matched instruction-shaped pattern(s):` line for tag
  imitations or mentions of settings like `bypassPermissions`.
- It does not judge maliciousness. Reports arrive under a header stating the contents carry no
  authority from you; background reports arrive as automated completion notifications.

### Nesting, concurrency, resume, errors

Source: https://code.claude.com/docs/en/sub-agents.md § "Let subagents spawn their own subagents"; https://code.claude.com/docs/en/sub-agents.md § "Concurrent subagent limit"; https://code.claude.com/docs/en/sub-agents.md § "Resume subagents"; https://code.claude.com/docs/en/sub-agents.md § "API errors in subagents"

- Depth: default three layers below main; `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` changes it (`1`
  disables nesting). At the limit `Agent` is withheld.
- Concurrency: 20 running subagents by default, then spawning fails with `Concurrent subagent limit
  reached`; `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` changes it (v2.1.217+). Not enforced under
  ultracode. No cap on total spawned per session. Resumes and `/subtask` forks take slots without
  being blocked. Workflow agents and teammates have their own limits.
- Resume: `SendMessage` with the agent ID or name resumes a finished subagent in the background with
  full history. Explore and Plan return no ID and cannot be resumed. A subagent you stopped yourself
  refuses messages. Names are checked against the agent they previously reached (v2.1.199+).
- Messages from the launching agent count as task direction, but no agent message is ever user
  approval for a permission prompt, and none can change permissions, `CLAUDE.md`, or configuration.
- Transcripts: `~/.claude/projects/{project}/{sessionId}/subagents/agent-{agentId}.jsonl`,
  unaffected by main compaction, deleted after `cleanupPeriodDays` (default 30).
- API errors: foreground returns partial output with a cut-off note, or fails with `Agent
  terminated early due to an API error`; background is marked failed with last output included.
  Fallback model chains apply.

### Forks

Source: https://code.claude.com/docs/en/sub-agents.md § "Fork the current conversation"; https://code.claude.com/docs/en/sub-agents.md § "How forks differ from other subagents"; https://code.claude.com/docs/en/sub-agents.md § "Turn fork mode on or off"

- A fork inherits the full conversation, system prompt, tools, and model, and shares the parent's
  prompt cache (cheaper than a fresh subagent for same-context tasks). Only its result returns.
- Start one with `/subtask <task>` (v2.1.212+), or Claude requests subagent type `fork`. Forks can
  take `isolation: "worktree"` on the call; a fork cannot spawn forks.
- Fork mode: on by default interactively (v2.1.232+), off in `-p` and SDK.
  `CLAUDE_CODE_FORK_SUBAGENT=1` / `0` overrides. Deny `Agent(fork)` to keep fork mode but stop forks.

## Agent teams

Source: https://code.claude.com/docs/en/agent-teams.md § "Orchestrate teams of Claude Code sessions"

### Enabling and how teams start

Source: https://code.claude.com/docs/en/agent-teams.md § "Enable agent teams"; https://code.claude.com/docs/en/agent-teams.md § "How Claude starts agent teams"; https://code.claude.com/docs/en/agent-teams.md § "Claude spawns teammates instead of subagents"

- Off by default. Enable with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in the environment or a
  settings `env` block. Without it, no team is set up and Claude does not spawn teammates.
- Interactive only: in `-p` and Agent SDK sessions no teammates spawn; named subagents stay subagents.
- A teammate launches whenever Claude calls Agent with a `name` while teams are enabled, unless it is
  a fork or passes `isolation` on the call. No confirmation is asked, and Claude names subagents on
  its own, so teams can form unrequested.
- Setting the variable to `0` stops this; it is re-read at each spawn. Higher-precedence settings
  (project, local, `--settings`, managed) can still set it to `1`.

### Architecture and storage

Source: https://code.claude.com/docs/en/agent-teams.md § "Architecture"

| Component | Role |
| :-- | :-- |
| Team lead | The main session; spawns and coordinates |
| Teammates | Separate Claude Code instances |
| Task list | Shared work items to claim and complete |
| Mailbox | Messaging between agents |

- Team name: `session-` plus the first 8 chars of the session ID.
- Mailbox per agent: `~/.claude/teams/{team-name}/inboxes/{agent-name}.json`. Malformed entries are
  reported and dropped. A send is reported only after the mailbox write succeeds.
- Team config: `~/.claude/teams/{team-name}/config.json` (runtime state, `members` array; lead has
  type `team-lead`); removed when the session ends; do not hand-edit or pre-author.
- Task list: `~/.claude/tasks/{team-name}/`; persists locally, never uploaded; retention follows
  `cleanupPeriodDays`. Dependencies auto-unblock.
- A project file like `.claude/teams/teams.json` is not configuration.

### Tasks, messaging, context

Source: https://code.claude.com/docs/en/agent-teams.md § "Assign and claim tasks"; https://code.claude.com/docs/en/agent-teams.md § "Context and communication"; https://code.claude.com/docs/en/agent-teams.md § "Shut down teammates"

- Task states: pending, in progress, completed. Dependent tasks cannot be claimed until
  dependencies complete. Lead assigns, or teammates self-claim the next unassigned, unblocked task.
  Claiming uses file locking. Agents without Task tools coordinate by messages.
- Teammates load CLAUDE.md, MCP servers, and skills like a normal session and get the lead's spawn
  prompt; the lead's history does not carry over.
- Messages deliver automatically; idle teammates notify the lead with their final answer (or error).
  Direct message by name; no broadcast (one message per recipient).
- Shutdown: the lead sends a shutdown request; the teammate may approve or reject with reasons.
  Shared directories are cleaned up at session end.

### Models, plan approval, subagent definitions

Source: https://code.claude.com/docs/en/agent-teams.md § "Specify teammates and models"; https://code.claude.com/docs/en/agent-teams.md § "Have teammates plan before implementing"; https://code.claude.com/docs/en/agent-teams.md § "Use subagent definitions for teammates"

- Teammate model order: model named in the spawn prompt; definition `model`;
  `CLAUDE_CODE_SUBAGENT_MODEL`; the lead's model. `_FORCE=1` skips the first two. Teammates inherit
  the lead's effort. `teammateDefaultModel` was removed in v2.1.234.
- A teammate spawned while the lead is in plan mode plans read-only, then sends a plan approval
  request that the lead's session approves automatically without review.
- A teammate can use a project, user, or managed subagent definition: `tools` limit it (plus
  `SendMessage` and Task tools for in-process); `model` applies; the body is appended (in-process) or
  replaces the system prompt (split-pane); `skills` are not applied; `mcpServers` apply only to
  split-pane teammates.
- A revived in-process teammate re-applies a project/`--add-dir` definition only if that folder is
  trusted.

### Permissions and trust between agents

Source: https://code.claude.com/docs/en/agent-teams.md § "Permissions"; https://code.claude.com/docs/en/agent-teams.md § "Messages between agents"

- Teammates start in the lead's permission mode, except `dontAsk`, which is not inherited.
  `--dangerously-skip-permissions` on the lead applies to all teammates. Per-teammate modes can be
  changed after spawn, not at spawn.
- Teammate permission prompts appear in the lead session.
- Received `SendMessage` content is labeled as from another Claude session. A teammate cannot
  approve prompts or give consent for you, and a denied teammate cannot relay the action to another.
- Under auto mode the classifier treats relayed approval claims as untrusted and reviews every
  inter-agent message before delivery; blocked messages never arrive.

### Quality-gate hooks

Source: https://code.claude.com/docs/en/agent-teams.md § "Enforce quality gates with hooks"

| Hook | Fires | Exit code 2 |
| :-- | :-- | :-- |
| `TeammateIdle` | A teammate is about to go idle | Sends feedback and keeps it working |
| `TaskCreated` | A task is being created | Prevents creation, sends feedback |
| `TaskCompleted` | A task is being marked complete | Prevents completion, sends feedback |

### Cost and limits

Source: https://code.claude.com/docs/en/agent-teams.md § "Token usage"; https://code.claude.com/docs/en/agent-teams.md § "Choose an appropriate team size"; https://code.claude.com/docs/en/agent-teams.md § "Limitations"; https://code.claude.com/docs/en/agent-teams.md § "Choose a display mode"

- Tokens scale with active teammates; each is a separate instance. No hard teammate cap; 3-5
  teammates and 5-6 tasks per teammate are suggested.
- In-process teammate cache TTL is 5 minutes by default; `subagentPromptCacheTtl: "1h"` extends it at
  a higher write rate.
- Limitations: `/resume` and `/rewind` do not restore in-process teammates; task status can lag;
  shutdown can be slow; one team per session; no nested teams (only the lead manages); in-process
  teammates' subagents are foreground only; the lead is fixed; permissions set at spawn; split panes
  need tmux or iTerm2 and are unsupported in VS Code terminal, Windows Terminal, and Ghostty.
- Display: `teammateMode` setting or `--teammate-mode`: `in-process` (default), `auto`, `tmux`,
  `iterm2` (v2.1.186+).
- Teammates are not placed in worktrees; avoid two teammates editing the same file.

## Dynamic workflows

Source: https://code.claude.com/docs/en/workflows.md § "Orchestrate subagents at scale with dynamic workflows"

### What they are and availability

Source: https://code.claude.com/docs/en/workflows.md § "Orchestrate subagents at scale with dynamic workflows"; https://code.claude.com/docs/en/workflows.md § "When to use a workflow"

- A JavaScript script, written by Claude, that the runtime executes in the background to orchestrate
  many subagents. The loop, branching, and intermediate results live in script variables; Claude's
  context holds only the final answer.
- Available on all paid plans, Anthropic API, Bedrock, Google Cloud's Agent Platform, Microsoft
  Foundry. On Pro, turn on via `/config`.
- Scale: dozens to hundreds of agents per run; resumable within the same session.
- Supports quality patterns such as independent agents adversarially reviewing each other's
  findings before reporting.

### Opt-in and triggering

Source: https://code.claude.com/docs/en/workflows.md § "Ask for a workflow in your prompt"; https://code.claude.com/docs/en/workflows.md § "Where the keyword works"; https://code.claude.com/docs/en/workflows.md § "Let Claude decide with ultracode"; https://code.claude.com/docs/en/workflows.md § "Bundled workflows"

- Opt in per task with the keyword `ultracode` or a direct request ("use a workflow"). The keyword
  only affects structure; agent tool calls get normal permission checks and sandboxing.
- The keyword counts only in human-typed prompts (interactive, IDE panel, Remote Control, SDK input
  stamped `origin: { kind: "human" }`). It does not trigger from `-p`, unstamped SDK prompts,
  scheduled tasks, or relayed webhook/PR comments (since v2.1.210).
- `/effort ultracode` (or `claude --effort ultracode`, v2.1.203+) combines `xhigh` effort with
  automatic workflow planning for every substantive task; `ultracode` setting makes it persistent.
- Bundled: `/deep-research <question>` (needs WebSearch; runs only when invoked).

### Approval and permissions

Source: https://code.claude.com/docs/en/workflows.md § "Approve the plan before it runs"

| Mode | Prompted? |
| :-- | :-- |
| Auto | First launch only (consent saved to user settings); skipped under ultracode |
| Manual, accept edits | Every run, unless "don't ask again" for that named workflow in this project |
| Bypass permissions | Never |
| `claude -p`, Agent SDK | Never shown; the Workflow tool call goes through normal permission evaluation |

- In `-p`/SDK, allow via `Workflow` or `Workflow(<name>)` allow rules, auto mode classifier, bypass,
  a `PreToolUse` hook returning `allow`, `--permission-prompt-tool`, or SDK `canUseTool` /
  `PermissionRequest` hook.
- Spawned agents use your permission rules and the subagent permission-mode rules.

### Authoring, saving, distributing

Source: https://code.claude.com/docs/en/workflows.md § "What the saved script looks like"; https://code.claude.com/docs/en/workflows.md § "Edit a saved script"; https://code.claude.com/docs/en/workflows.md § "Save the workflow for reuse"; https://code.claude.com/docs/en/workflows.md § "Distribute a workflow in a plugin"; https://code.claude.com/docs/en/workflows.md § "Pass input to a saved workflow"

- File shape: `export const meta = { name, description }` as the first statement (literal values
  only), then a plain JS body with top-level `await`.
- API named in source: `agent()` (one subagent; options shown include `schema` and `label`),
  `pipeline()` (one per list item), `parallel()` (concurrent set), `phase()`, `log()`, and the
  `args` global. Optional `meta.phases` titles must match `phase()` titles.
- `agent()` resolves to `null` if stopped or on unrecoverable API error.
- `schema` forces JSON output; self-contradictory schemas fail before start; a call fails after five
  validation attempts by default (`MAX_STRUCTURED_OUTPUT_RETRIES`).
- `Date.now()`, `Math.random()`, and no-arg `new Date()` throw so replays are deterministic.
- In auto mode, prompts passed to `agent()` are marked script-computed and do not count as requests
  from you.
- Save from `/workflows` with `s` to `.claude/workflows/` (project) or `~/.claude/workflows/`
  (personal); runs as `/<name>`. Project wins over personal on name clash; nearest `.claude/workflows/`
  wins in monorepos. Symlinked save paths are refused.
- Plugins: `workflows/` at plugin root (or manifest `workflows` field); namespaced
  `/<plugin>:<meta.name>`.
- `/workflow-authoring` bundled skill loads the script reference (v2.1.248+); `/reload-skills`
  re-reads workflow directories.

### Runtime behavior and limits

Source: https://code.claude.com/docs/en/workflows.md § "How a workflow runs"; https://code.claude.com/docs/en/workflows.md § "Behavior and limits"; https://code.claude.com/docs/en/workflows.md § "Prompt caching in a fan-out"

- Runs in an isolated environment; each run's script is written under the session directory in
  `~/.claude/projects/`. Claude can start only a script file the session may read.
- No mid-run user input (pauses only for agent permission prompts and usage-limit waits); no direct
  filesystem or shell access from the script; `import()` fails.
- Concurrency: up to 16 agents by default (fewer with fewer CPUs);
  `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS` 1-256 (v2.1.269+).
- Max 4,096 items per `parallel()`/`pipeline()` call; 1,000 agents total per run.
- Matching agents stagger up to `CLAUDE_CODE_WORKFLOW_PREFIX_STAGGER_MS` (default 5000) to share
  the prompt-cache prefix. Workflow agent cache TTL defaults to 5 minutes.

### Resume, usage limits, cost, disabling

Source: https://code.claude.com/docs/en/workflows.md § "Resume after a pause"; https://code.claude.com/docs/en/workflows.md § "When a run hits your usage limit"; https://code.claude.com/docs/en/workflows.md § "Cost"; https://code.claude.com/docs/en/workflows.md § "Set a size guideline"; https://code.claude.com/docs/en/workflows.md § "Turn workflows off"

- Relaunch replays agents in start order: completed ones return cached results until the first
  changed prompt; a failed agent (or one you stopped individually) reruns along with every later one.
- Usage-limit pause (v2.1.271+) only for interactive claude.ai-subscription sessions with
  `autoContinueAtUsageLimit` on, reset within 24 hours, at most two waits; otherwise the agent fails.
- Cost: counts toward plan usage and rate limits. A `Large workflow` advisory appears above 25
  agents or 1.5M projected tokens (not under ultracode). Model per agent follows subagent order.
- Size guideline `workflowSizeGuideline`: `unrestricted`, `small` (<5), `medium` (<10, default),
  `large` (<50); advice only, runtime caps still apply. Pro default is `small` (v2.1.271+).
- Disable: `/config` toggle, `"disableWorkflows": true` (user or managed settings), or
  `CLAUDE_CODE_DISABLE_WORKFLOWS=1`.

## Cross-session messaging

Source: https://code.claude.com/docs/en/cross-session-messaging.md § "Message your other Claude Code sessions"

### Scope, tools, delivery

Source: https://code.claude.com/docs/en/cross-session-messaging.md § "Message your other Claude Code sessions"; https://code.claude.com/docs/en/cross-session-messaging.md § "Message another session"; https://code.claude.com/docs/en/cross-session-messaging.md § "Message delivery"

- On by default when requirements are met: v2.1.224+ (macOS, Linux, WSL 2), v2.1.234+ native
  Windows.
- Tools: `ListAgents` (discover) and `SendMessage` (deliver by name). `SendMessage` also serves
  subagents and teammates. Only text is sent, never history or files.
- Claude may send on its own initiative. Address with `@<session-name>` (v2.1.232+); quote names
  with spaces.
- Delivered between tool calls during an active turn, or as a new turn when idle. `@` mentions in a
  message attach nothing on the receiver (v2.1.251+).
- Sender-side refusals: over size cap, burst limit reached, reply target fails safety check,
  addressed to itself. Receiver outcomes: delivered, held, refused. Delivered messages count toward
  usage.

### Addressing and reachability

Source: https://code.claude.com/docs/en/cross-session-messaging.md § "See which sessions Claude can reach"; https://code.claude.com/docs/en/cross-session-messaging.md § "Message sessions on other machines"

- `/list-agents` (alias `/peers`) shows own name, then subagents, teammates, other local sessions
  (those binding an inbox socket), cloud sessions and Remote Control sessions (only while connected
  to Remote Control).
- Names come from `/rename` or `--name`, otherwise auto-generated. Duplicate names get an identifier.
- Transport: same machine via per-session Unix socket or Windows named pipe, never via Anthropic;
  other machines and cloud via Anthropic servers over Remote Control.
- Sessions must see the same files to find each other: host vs container, and WSL 2 vs native
  Windows, cannot reach each other.
- Without a Remote Control connection, cross-machine messages are one-way (no reply address).

### Trust limits on incoming messages

Source: https://code.claude.com/docs/en/cross-session-messaging.md § "How a session treats an incoming message"; https://code.claude.com/docs/en/cross-session-messaging.md § "What a message looks like"

- Labeled as from another session, not from you. It cannot approve anything, cannot change
  configuration, slash commands in it do not run, and the receiver's own permission prompts still
  fire.
- Senders are told never to ask another session for an action denied in their own session.
- Shown as a one-line preview; Claude reads the full text. A subagent-written message arrives under
  the sending session's name; replies go to that session's main conversation.

### Inbound controls

Source: https://code.claude.com/docs/en/cross-session-messaging.md § "Control inbound messages"; https://code.claude.com/docs/en/cross-session-messaging.md § "Non-interactive sessions"

- `crossSessionInbound`: `accept`, `hold` (notice only; released if `accept` later applies),
  `refuse` (drop).
- Default when unset depends on permission class: a prompting receiver delivers unless the sender
  claims to bypass; a bypassing receiver holds unless the sender also bypasses. Held messages open
  an approval dialog that expires after `dialogExpiry` (default 5 minutes). At most 100 held.
- `-p` sessions bind a socket and can receive; bare mode does not. Default-held messages in `-p`
  expire at `dialogExpiry` (`"never"` keeps them). Use `--settings` with `crossSessionInbound:
  accept` for an unattended `-p` worker.

### Inbox socket for scripts and hooks

Source: https://code.claude.com/docs/en/cross-session-messaging.md § "The session's inbox socket"

- Path in `/status` (`Peer address`, prefix `uds:`) and exported as `CLAUDE_CODE_MESSAGING_SOCKET`
  to hooks and Bash (before `SessionStart` runs). Token exported as `CLAUDE_CODE_MESSAGING_TOKEN`.
- First line `{"type":"auth","token":"<token>"}`: optional on macOS/Linux, required on native
  Windows. A connection with no complete line within 30 seconds is closed.
- Socket is restricted to your OS user (Windows: key auth). Fallback dir `/tmp/cc-socks-<uid>`.
- Own-child messages (a hook or Bash command posting to its own session) are delivered when no
  `crossSessionInbound` value applies, if verified by process evidence (Linux; macOS while running)
  or by the token. Unverified ones are treated like any peer message.
- Sandbox access is controlled by `sandbox.network.allowAllUnixSockets` / `allowUnixSockets`.

### Idle notices, restrictions, limits

Source: https://code.claude.com/docs/en/cross-session-messaging.md § "Get a notice when another session goes idle"; https://code.claude.com/docs/en/cross-session-messaging.md § "Restrict cross-session messaging"; https://code.claude.com/docs/en/cross-session-messaging.md § "Require approval for cross-machine messages"; https://code.claude.com/docs/en/cross-session-messaging.md § "Turn off cross-session messaging"; https://code.claude.com/docs/en/cross-session-messaging.md § "Limitations"

- `SendMessage` input `notify_when_idle` (v2.1.236+): one-shot notice when a local session next goes
  idle or exits; expires after 12 hours. Only the main conversation may subscribe, and only to local
  sessions.
- `isolatePeerMachines: true` requires your approval before any message leaves the machine, even in
  `bypassPermissions`; a `true` from any scope applies.
- Turn off receiving with `crossSessionInbound: refuse`; sending/listing with deny rules on
  `SendMessage` and `ListAgents` (bare names). Denying `SendMessage` also removes subagent and
  teammate messaging.
- Limits: plain text only; about 1 million characters per same-machine message; burst refusals at
  the sender; per-sender rate limits, duplicate drops, and a 50-message accepted queue on the receiver.

## Worktrees

Source: https://code.claude.com/docs/en/worktrees.md § "Run parallel sessions with worktrees"

### Starting, entering, cleanup

Source: https://code.claude.com/docs/en/worktrees.md § "Start Claude in a worktree"; https://code.claude.com/docs/en/worktrees.md § "Ask Claude to create a worktree"; https://code.claude.com/docs/en/worktrees.md § "Clean up worktrees"

- `claude --worktree <name>` (`-w`) creates `.claude/worktrees/<name>/` on branch
  `worktree-<name>`; name auto-generated if omitted. Interactive runs need workspace trust; `-p`
  skips it.
- Mid-session, Claude uses `EnterWorktree` / `ExitWorktree`. Entering a path outside
  `.claude/worktrees/` always prompts; only `bypassPermissions` skips it.
- `${CLAUDE_PROJECT_DIR}` in hooks stays at the original project root; hook input `cwd` follows the
  worktree.
- On interactive exit: clean unnamed worktrees are removed with their branch; named sessions or
  worktrees with work prompt keep/remove; unverifiable state prompts. `-p` runs never clean up and
  leave their lock.

### Isolation enforcement

Source: https://code.claude.com/docs/en/worktrees.md § "How Claude Code enforces isolation"

Four checks apply to an isolated session and every subagent it spawns: file edits into the main
checkout are blocked; Bash/PowerShell/Monitor commands whose working directory is (or cannot be
verified not to be) the main checkout are blocked; git redirects (`git -C`, `--git-dir`, `GIT_DIR`,
`GIT_WORK_TREE`, `cd` then git) are blocked; commands whose git use cannot be verified from text are
blocked and cannot be turned off. PowerShell gets only the working-directory check.

### Subagent worktrees and sweep

Source: https://code.claude.com/docs/en/worktrees.md § "Isolate subagents with worktrees"; https://code.claude.com/docs/en/worktrees.md § "Clean up subagent and background-session worktrees"

- `isolation: worktree` in frontmatter, or ask Claude to use worktrees for agents. Worktree removed
  if no changes; otherwise kept until the periodic sweep.
- Sweep removes Claude-created subagent and background-session worktrees older than
  `cleanupPeriodDays`, but keeps ones with changes, unpushed commits, dirty or uninspectable
  submodules, filter-driver problems, non-backgrounded `--worktree` sessions, and user-created ones
  (identified by a marker Claude writes into git metadata).
- A `git worktree lock` is held while an agent runs; stale locks from exited sessions are released,
  user locks never are.

### Customization and hooks

Source: https://code.claude.com/docs/en/worktrees.md § "Choose the base branch"; https://code.claude.com/docs/en/worktrees.md § "Branch from a pull request"; https://code.claude.com/docs/en/worktrees.md § "Copy gitignored files into worktrees"; https://code.claude.com/docs/en/worktrees.md § "Reuse a worktree name"; https://code.claude.com/docs/en/worktrees.md § "Replace worktree creation with a hook"; https://code.claude.com/docs/en/worktrees.md § "Non-git version control"

- `worktree.baseRef`: `"fresh"` (default; remote default branch, fetched if stale >24h) or
  `"head"`. Branch names are not accepted.
- `--worktree "#1234"` or a GitHub/GitLab PR/MR URL creates `.claude/worktrees/pr-<number>`.
- `.worktreeinclude` (gitignore syntax) copies files that match and are gitignored.
- Reusing an existing name reopens it, resetting to the default branch only when clean, on its own
  branch, and with no commits of its own (or merged and remote branch deleted).
- `WorktreeCreate` hook replaces git creation entirely (prints the directory path on stdout);
  `WorktreeRemove` handles cleanup. `.worktreeinclude` is not processed with the hook.

### Shared state and safety refusals

Source: https://code.claude.com/docs/en/worktrees.md § "What worktrees share with the main checkout"; https://code.claude.com/docs/en/worktrees.md § "Claude Code refuses to use a worktree"; https://code.claude.com/docs/en/worktrees.md § "Git LFS files are pointer files in a worktree Claude Code created"

- Shared: the `.git` directory; project-scope plugins; "don't ask again" Bash approvals (saved to the
  main checkout's `.claude/settings.local.json`, except on Windows and similar cases); untracked
  `.claude/skills`, `.claude/agents`, `.claude/commands` when the worktree lacks its own.
- Claude refuses a directory whose git metadata resolves into the main checkout, and refuses
  symlinked `.claude` / `.claude/worktrees` paths.
- Repo-local filter drivers (e.g. `git lfs install --local`) are skipped at creation because they
  are shell commands; run `git lfs pull` in the worktree.

## Not found in source

Source: https://code.claude.com/docs/en/sub-agents.md § "Create custom subagents"; https://code.claude.com/docs/en/agents.md § "Run agents in parallel"; https://code.claude.com/docs/en/agent-teams.md § "Orchestrate teams of Claude Code sessions"; https://code.claude.com/docs/en/workflows.md § "Orchestrate subagents at scale with dynamic workflows"; https://code.claude.com/docs/en/cross-session-messaging.md § "Message your other Claude Code sessions"; https://code.claude.com/docs/en/worktrees.md § "Run parallel sessions with worktrees"

Items a reader might expect here that these six pages do not state:

- Input/output JSON schemas for `SubagentStart`, `SubagentStop`, `TeammateIdle`, `TaskCreated`,
  `TaskCompleted`, `WorktreeCreate`, `WorktreeRemove` (all deferred to the hooks page).
- Whether `SubagentStop` can block or send feedback via exit code 2 (not stated on these pages).
- Any way to run a non-Claude model as a subagent, teammate, or workflow agent; the source says only
  that other tools participate as MCP servers.
- The full workflow script API (all `agent()` options, `parallel()` signature), deferred to the
  `/workflow-authoring` skill and the Agent SDK reference.
- The wire format of a message posted to the inbox socket beyond the auth line.
- Tool lists for `statusline-setup` and `claude-code-guide`.
- Agent view, projects, and routines details (only mentioned).
- Specific token or price figures per teammate or per workflow agent (deferred to the costs page).
