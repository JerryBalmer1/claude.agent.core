---
verified: 2026-09-23
sources:
  - https://code.claude.com/docs/en/memory.md
  - https://code.claude.com/docs/en/claude-directory.md
  - https://code.claude.com/docs/en/context-window.md
  - https://code.claude.com/docs/en/prompt-caching.md
scope: How Claude Code discovers and loads instruction files (CLAUDE.md, AGENTS.md, rules, auto memory), what the .claude directories hold, what fills and survives the context window, and how prompt caching interacts with all of it.
---

# Memory and context

This is a condensed, source-pinned reference. Every claim below traces to one of the four pages in
the front matter. Version numbers (`v2.1.x`) are the ones the source states; nothing is inferred.

Core framing the sources repeat:

- Instruction files (CLAUDE.md, AGENTS.md, rules, auto memory) are context, not enforced config.
  For guaranteed behaviour the sources point to hooks, permissions, and managed settings.
- Project-root and user CLAUDE.md are read once at session start. Nested CLAUDE.md files and
  path-scoped rules load lazily, when Claude reads a matching file.
- Project-root and user CLAUDE.md are read once at session start and held in memory, so a
  mid-session edit neither applies nor invalidates the cache. It loads on the next `/clear`,
  `/compact`, or restart.

## Two memory systems
Source: https://code.claude.com/docs/en/memory.md § "How Claude remembers your project"; https://code.claude.com/docs/en/memory.md § "CLAUDE.md vs auto memory"

Every session starts with a fresh context window. Two mechanisms carry knowledge across sessions.

| Aspect | CLAUDE.md files | Auto memory |
| --- | --- | --- |
| Author | You | Claude |
| Content | Instructions and rules | Learnings and patterns |
| Scope | Project, user, or org | Per repository, shared across worktrees |
| Loaded | Every session | Every session (first 200 lines or 25KB of `MEMORY.md`) |
| Typical use | Coding standards, workflows, architecture | Preferences, corrections, context not derivable from code |

- Both load at the start of every conversation.
- Both are treated as context, not enforced configuration. To block an action regardless of what
  Claude decides, the source says to use a PreToolUse hook.
- Subagents can keep their own auto memory (separate feature, see the `.claude/` map below).

## CLAUDE.md files
Source: https://code.claude.com/docs/en/memory.md § "CLAUDE.md files"; https://code.claude.com/docs/en/memory.md § "When to add to CLAUDE.md"

- Plain markdown, read at the start of every session.
- Suggested triggers for adding content: Claude repeats a mistake, review catches something Claude
  should have known, you retype the same correction, a new teammate would need the same context.
- Keep to facts needed every session (build commands, conventions, layout, "always do X").
  Multi-step procedures or area-specific guidance belong in a skill or a path-scoped rule.

### Locations and load order
Source: https://code.claude.com/docs/en/memory.md § "Choose where to put CLAUDE.md files"

Listed broadest to most specific, which is also load order: later entries appear later in context.

| Scope | Location | Shared with |
| --- | --- | --- |
| Managed policy | macOS `/Library/Application Support/ClaudeCode/CLAUDE.md`; Linux/WSL `/etc/claude-code/CLAUDE.md`; Windows `C:\Program Files\ClaudeCode\CLAUDE.md` | All users in the org |
| User | `~/.claude/CLAUDE.md` | Just you, all projects |
| Project | `./CLAUDE.md` or `./.claude/CLAUDE.md` (AGENTS.md may load instead or alongside, see below) | Team via source control |
| Local | `./CLAUDE.local.md` (add to `.gitignore`) | Just you, current project |

- CLAUDE.md and CLAUDE.local.md in the directory hierarchy above the working directory load at launch.
- Files in subdirectories load on demand when Claude reads files in those directories.

### How CLAUDE.md files load
Source: https://code.claude.com/docs/en/memory.md § "How CLAUDE.md files load"

- Claude Code loads `CLAUDE.md` and `CLAUDE.local.md` from the working directory and every ancestor.
- Discovered files are concatenated, not overridden.
- Order across the tree: filesystem root first, working directory last. Instructions closest to the
  launch directory are read last.
- Within one directory: `CLAUDE.local.md` is appended after `CLAUDE.md`.
- Subdirectories below the working directory: their `CLAUDE.md` / `CLAUDE.local.md` are not loaded at
  launch; they are included when Claude reads files in that subdirectory.
- Block-level HTML comments in CLAUDE.md are stripped before injection (comments inside code blocks
  are kept). Opening the file with the Read tool still shows them.
- `claudeMdExcludes` can skip other teams' files in monorepos.

### Load from additional directories
Source: https://code.claude.com/docs/en/memory.md § "Load from additional directories"

- `--add-dir` grants access to extra directories; their CLAUDE.md files are NOT loaded by default.
- Set `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` to load `CLAUDE.md`, `.claude/CLAUDE.md`,
  `.claude/rules/*.md`, and `CLAUDE.local.md` from them. Can be set in the `env` block of
  `~/.claude/settings.json`.
- `CLAUDE.local.md` there is skipped if `local` is excluded from `--setting-sources`.

### Imports with @
Source: https://code.claude.com/docs/en/memory.md § "Import additional files"

- Syntax: `@path/to/import` anywhere in a CLAUDE.md. Imported files expand into context at launch
  with the file that references them.
- Relative paths resolve against the importing file, not the working directory. Absolute paths and
  `~/` paths are allowed.
- Recursive imports allowed, maximum depth four hops.
- Imports inside Markdown code spans and fenced blocks are ignored; wrap a path in backticks to keep
  it literal.
- Imports do not reduce context: imported content still loads at launch.
- External imports (path resolves outside the working directory) in a project-level file trigger a
  one-time approval dialog. Declining disables them permanently and the dialog does not reappear.
- User-scope files (`~/.claude/CLAUDE.md`, `~/.claude/rules/`) load imports without the dialog,
  except in Cowork desktop sessions, where out-of-working-directory imports in user-scope files are
  skipped, as are a symlinked/hard-linked `~/.claude/CLAUDE.md` and symlinked rules pointing outside.
- Worktree tip: a gitignored `CLAUDE.local.md` exists only in one worktree; import a home-directory
  file instead to share personal instructions across worktrees.

### Set up and /init
Source: https://code.claude.com/docs/en/memory.md § "Set up a project CLAUDE.md"; https://code.claude.com/docs/en/memory.md § "Migrate instructions from other tools"

- To confirm the file loaded: run `/context` and look under **Memory files**.
- `/init` generates a starting CLAUDE.md from the codebase. If one exists, it suggests improvements
  instead of overwriting.
- `CLAUDE_CODE_NEW_INIT=1` makes `/init` interactive and multi-phase: asks which artifacts to set up
  (CLAUDE.md files, skills, hooks), explores with a subagent, asks follow-ups, shows a reviewable
  proposal before writing. Its personal option also creates and gitignores `CLAUDE.local.md`.
- `/init` reads other tools' files: `.cursor/rules/`, `.cursorrules`,
  `.github/copilot-instructions.md`; with `CLAUDE_CODE_NEW_INIT=1` also `AGENTS.md`, `.devin/rules/`,
  `.windsurf/rules/`, `.windsurfrules`, `.clinerules`.
- `/import` (v2.1.213+) appends a one-time copy of another agent's instruction files such as
  `AGENTS.md` to the matching CLAUDE.md, and carries over MCP servers, commands, subagents, skills.

### Writing guidance and size limits
Source: https://code.claude.com/docs/en/memory.md § "Write effective instructions"; https://code.claude.com/docs/en/memory.md § "My CLAUDE.md is too large"; https://code.claude.com/docs/en/memory.md § "How it works"

- Target under 200 lines per CLAUDE.md; longer files cost context and reduce adherence.
- A CLAUDE.md up to 4 MiB loads in full; a larger file is skipped.
- Contradictory rules: Claude may pick one arbitrarily. Review CLAUDE.md, nested CLAUDE.md, and
  `.claude/rules/` periodically.
- Write verifiable instructions ("Run `npm test` before committing", not "Test your changes").
- `/doctor` proposes trims for a checked-in CLAUDE.md (v2.1.206+): cuts derivable content, keeps
  pitfalls, rationale, and non-default conventions.

## AGENTS.md
Source: https://code.claude.com/docs/en/memory.md § "AGENTS.md"

AGENTS.md is read natively (no import or setting needed) on v2.1.277 or later, but by default only
when no CLAUDE.md counts. Import is the fallback where native support is unavailable.

| Repository has | Claude reads by default |
| --- | --- |
| `AGENTS.md`, no `CLAUDE.md`/`CLAUDE.local.md` in cwd or above | `AGENTS.md` |
| `AGENTS.md` plus a `CLAUDE.md` or `CLAUDE.local.md` in cwd or above | CLAUDE.md files only |
| A `CLAUDE.md` that imports `@AGENTS.md` | CLAUDE.md, with AGENTS.md via the import |

### When Claude Code reads AGENTS.md
Source: https://code.claude.com/docs/en/memory.md § "When Claude Code reads AGENTS.md"

- Counts as "has CLAUDE.md" (suppresses AGENTS.md): `CLAUDE.md`, `.claude/CLAUDE.md`, or
  `CLAUDE.local.md` in the working directory or any ancestor.
- Does not count (keeps loading alongside AGENTS.md): `~/.claude/CLAUDE.md`, managed CLAUDE.md,
  `.claude/rules/` files.
- When read at start: every `AGENTS.md` and `.claude/AGENTS.md` in cwd and ancestors. Interactive
  sessions show a line like `no CLAUDE.md found; AGENTS.md loaded: <path>`.
- Subdirectory `AGENTS.md` loads when Claude opens a file there with Read and that subdirectory has
  none of the three CLAUDE.md files.
- `@path` imports expand inside AGENTS.md; `claudeMdExcludes` applies; subagents that skip project
  instructions skip these too.
- Never read: `AGENTS.local.md`, `AGENTS.override.md`, anything under `.agents/`.
- Gotcha: adding a `CLAUDE.local.md` stops AGENTS.md loading unless the setting is
  `claude-md-and-agents-md`.

### Choose which instruction files load
Source: https://code.claude.com/docs/en/memory.md § "Choose which instruction files load"

Set via `/config` > **Project instructions**, or in settings under
`pluginConfigs["agents-md@builtin"].options.instructionFiles`. Honoured in `~/.claude/settings.json`,
a `--settings` file, or managed settings; ignored in project and local settings files. Change
applies from the next message and in every new session.

| Value | Effect |
| --- | --- |
| `claude-md-or-agents-md` (default) | CLAUDE.md files, or AGENTS.md when no CLAUDE.md/CLAUDE.local.md in cwd or above |
| `claude-md-and-agents-md` | Both; per directory CLAUDE.md first, then AGENTS.md; an already-loaded AGENTS.md (imported or symlinked) is not read twice |
| `claude-md` | CLAUDE.md files only |
| `managed-only` | Managed CLAUDE.md and auto memory at launch only. Project/local/user CLAUDE.md, `.claude/rules/`, and all AGENTS.md left out. Subdirectory CLAUDE.md, subdirectory `.claude/rules/`, and path-scoped rules still load when Claude reads a file there |

### When AGENTS.md support is unavailable
Source: https://code.claude.com/docs/en/memory.md § "When AGENTS.md support is unavailable"; https://code.claude.com/docs/en/memory.md § "My AGENTS.md isn't loading"

CLAUDE.md-only sessions (and the **Project instructions** setting is hidden) when:

- version is before v2.1.277;
- the built-in `agents-md` plugin is disabled in `/plugin`;
- in some cases, the first session after upgrading from v2.1.276 or earlier (next session reads it);
- before v2.1.281, some sessions such as Amazon Bedrock or telemetry-disabled ones.

Workaround in all these cases: a CLAUDE.md containing `@AGENTS.md`.
Verify with `/memory` (look for the AGENTS.md path). Before v2.1.280, `/memory` and `/context` did
not list a directly read AGENTS.md.

### Where AGENTS.md differs from CLAUDE.md
Source: https://code.claude.com/docs/en/memory.md § "Where AGENTS.md differs from CLAUDE.md"

| Behaviour | CLAUDE.md | AGENTS.md read through the setting |
| --- | --- | --- |
| `InstructionsLoaded` hooks | Fire | Do not fire (they do fire for an AGENTS.md reached via CLAUDE.md import or symlink) |
| `--add-dir` dirs with `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` | Load | Do not load |
| External `@path` import | Approval prompt | Loads only if external imports already approved; no prompt |

### Old workarounds and sharing one file
Source: https://code.claude.com/docs/en/memory.md § "Remove an earlier AGENTS.md workaround"; https://code.claude.com/docs/en/memory.md § "Share one file with other coding tools"

- `CLAUDE.md` with `@AGENTS.md`: fine to keep; never double-reads.
- `CLAUDE.md` that says in prose "read AGENTS.md": Claude only sees AGENTS.md if it chooses to open
  it. Replace with an `@AGENTS.md` import or delete the CLAUDE.md.
- `CLAUDE.md` symlinked to `AGENTS.md`: content read once. Edit/Write refuse to write through a
  symlink. On Windows prefer the import: symlinks need Admin or Developer Mode, and git checks a
  committed symlink out as a one-line text file unless `core.symlinks` is enabled.
- `SessionStart` hook that prints AGENTS.md: remove it, it now adds a duplicate copy.
- Claude-specific content goes below the `@AGENTS.md` line; the import is read first.

## Rules in `.claude/rules/`
Source: https://code.claude.com/docs/en/memory.md § "Organize rules with `.claude/rules/`"; https://code.claude.com/docs/en/memory.md § "Set up rules"

- One topic per `.md` file; all `.md` files are discovered recursively (subfolders allowed).
- Rules without `paths` front matter load at launch with the same priority as `.claude/CLAUDE.md`.
- Project rules are skipped if `project` is excluded from `--setting-sources`. Before v2.1.211,
  on-demand rules (path-scoped, nested `.claude/rules/`) loaded even when `project` was excluded.
- Rules are guidance, like CLAUDE.md; the source recommends skills for task-specific content that
  should not sit in context all the time.

### Path-scoped rules
Source: https://code.claude.com/docs/en/memory.md § "Path-specific rules"

- Front matter `paths:` takes glob patterns (YAML list or comma-separated string).
- `paths` is the only field read from a rule; other fields are silently ignored. Front matter is
  removed before the rule enters context.
- Trigger: Claude reads a file matching a pattern. Not evaluated on every tool use.
- Symlinked checkout paths match as of v2.1.198.
- Brace expansion supported (`src/**/*.{ts,tsx}`). Budget per rule: 1,000 expanded patterns and
  4 MiB total; a pattern exceeding it is used unexpanded, so its literal braces match nothing.
  Before v2.1.217, many brace groups could stall or crash startup.
- `[` starts a bracket expression. An unparseable one (e.g. `photos [2024/**`) matches nothing while
  the rule's other patterns still work; escape as `\[`. Before v2.1.207, one invalid pattern made
  Read fail for every file the rule was evaluated against.
- Unparseable YAML front matter: the rule loads as if unscoped (always on). `claude --debug` shows
  the parse error.

Example pattern semantics from the source:

| Pattern | Matches |
| --- | --- |
| `**/*.ts` | TypeScript files in any directory |
| `src/**/*` | Everything under `src/` |
| `*.md` | Markdown files in the project root only |
| `src/components/*.tsx` | Components in one directory |

### Symlinks and user-level rules
Source: https://code.claude.com/docs/en/memory.md § "Share rules across projects with symlinks"; https://code.claude.com/docs/en/memory.md § "User-level rules"

- `.claude/rules/` supports symlinks; circular links are handled.
- A symlink whose target is outside the working directory is treated as an external import: it
  loads only after external imports are approved, and then only rules without `paths` load. The
  approval prompt itself only appears for `@path` imports, not for symlinks alone.
- `~/.claude/rules/` applies to every project without that approval.
- User rules load before project rules. Neither overrides the other; on conflict Claude may follow
  either.

## Large teams: managed CLAUDE.md and exclusions
Source: https://code.claude.com/docs/en/memory.md § "Deploy organization-wide CLAUDE.md"; https://code.claude.com/docs/en/memory.md § "Exclude specific CLAUDE.md files"

- Managed CLAUDE.md applies to all users on the machine and cannot be excluded.
- Alternative: `claudeMd` string key inside `managed-settings.json`. Same precedence as the managed
  file (loads before user and project). Only honoured in managed/policy settings.
- Source's split: technical enforcement goes in managed settings (`permissions.deny`,
  `sandbox.enabled`, `env`, `forceLoginMethod`, `forceLoginOrgUUID`); behavioural guidance goes in
  managed CLAUDE.md.
- `claudeMdExcludes`: glob patterns matched against absolute paths; settable at user, project,
  local, or managed layer; arrays merge. For symlinked rules, a pattern may match either the path
  under `.claude/rules/` or the link target (before v2.1.239 only the target worked).

## Auto memory
Source: https://code.claude.com/docs/en/memory.md § "Auto memory"; https://code.claude.com/docs/en/memory.md § "Enable or disable auto memory"

- Claude writes notes typed in front matter as `user`, `feedback`, `project`, or `reference`.
- It skips what is derivable from code or already in CLAUDE.md; does not save every session.
- On by default. Toggle in `/memory` (writes `autoMemoryEnabled` to `~/.claude/settings.json`), set
  `autoMemoryEnabled: false` in a project's settings, or `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`.

### Storage location
Source: https://code.claude.com/docs/en/memory.md § "Storage location"

- `~/.claude/projects/<project>/memory/`, `<project>` derived from the git repository, so all
  worktrees and subdirectories of one repo share it. Outside git, the project root is used.
- `CLAUDE_CODE_PROJECT_DIR_NAME` beside `CLAUDE_CONFIG_DIR` pins the `<project>` name (v2.1.234+).
- `autoMemoryDirectory` (absolute or `~/`) relocates it; readable from any settings scope. In
  project settings files it follows the same workspace-trust rule as hooks. With
  `permissions.blockReadsOutsideWorkingDirectories` on, a repository-chosen directory is neither
  read nor written.
- Layout: `MEMORY.md` index (one line per memory) plus one topic file per memory.
- Machine-local; not shared across machines or cloud environments.
- Memory files are excluded from the `cleanupPeriodDays` transcript sweep.

### How auto memory loads
Source: https://code.claude.com/docs/en/memory.md § "How it works"

- First 200 lines or first 25KB of `MEMORY.md` (whichever first) load at conversation start; the
  rest does not.
- After a write, Claude Code checks the limits: near a limit it reminds Claude to shorten; over a
  limit the write succeeds but returns an error telling Claude to rewrite the index.
- Topic files are not loaded at startup; Claude reads them on demand.
- Main-session auto memory is not loaded into subagents, except forks.
- Interface messages "Saved N memories" / "Recalled N memories" indicate activity.
- On writing a memory file that has front matter, Claude Code stamps a `modified` ISO 8601 field
  (v2.1.214+). It never adds front matter to a file without it.

## /memory and /context
Source: https://code.claude.com/docs/en/memory.md § "View and edit with `/memory`"; https://code.claude.com/docs/en/context-window.md § "Check your own session"

- `/memory` lists CLAUDE.md, CLAUDE.local.md, and other memory locations across user and project
  scopes, including not-yet-existing ones (selecting one creates it). It toggles auto memory and
  opens the auto memory folder.
- GUI editors open separately and the session continues (before v2.1.216 `/memory` waited).
- "Remember X" in chat goes to auto memory; ask "add this to CLAUDE.md" to write CLAUDE.md instead.
- `/context` shows live usage by category and which CLAUDE.md, rules, and auto memory files loaded.

## Troubleshooting and InstructionsLoaded
Source: https://code.claude.com/docs/en/memory.md § "Claude isn't following my CLAUDE.md"; https://code.claude.com/docs/en/memory.md § "Instructions seem lost after `/compact`"

- CLAUDE.md is delivered as a user message after the system prompt, not inside the system prompt.
  No guarantee of strict compliance.
- Debug steps: `/context` > **Memory files**; check location; make instructions specific; remove
  conflicts.
- Must-run-at-a-point behaviour belongs in a hook. System-prompt-level text uses
  `--append-system-prompt` at launch.
- `InstructionsLoaded` hook: logs which CLAUDE.md and rules files load, when, and why; the source
  recommends it for debugging path-specific rules and lazy subdirectory files. It does not fire for
  AGENTS.md read natively through the setting. The hook's payload schema is not in these sources.

## The `.claude/` directory map
Source: https://code.claude.com/docs/en/claude-directory.md § "Explore the .claude directory"; https://code.claude.com/docs/en/claude-directory.md § "File reference"

- Project files: repo `.claude/`, except `CLAUDE.md`, `.mcp.json`, `.worktreeinclude` at repo root.
- Global files: `~/.claude/` (Windows `%USERPROFILE%\.claude`; relocated by `CLAUDE_CONFIG_DIR`).
- Managed settings override everything (with documented exceptions); CLI flags like
  `--permission-mode` / `--settings` override `settings.json` per session; some env vars beat their
  setting.

| File | Scope | Commit | Purpose |
| --- | --- | --- | --- |
| `CLAUDE.md` | Project and global | yes | Instructions loaded every session |
| `rules/*.md` | Project and global | yes | Topic instructions, optionally path-gated |
| `settings.json` | Project and global | yes | Permissions, hooks, env vars, model defaults |
| `settings.local.json` | Project only | no | Personal overrides, gitignored when Claude Code saves to it |
| `.mcp.json` | Project only | yes | Team-shared MCP servers |
| `.worktreeinclude` | Project only | yes | Gitignored files copied into new worktrees |
| `skills/<name>/SKILL.md` | Project and global | yes | Prompts invoked by `/name` or auto-invoked |
| `commands/*.md` | Project and global | yes | Single-file prompts; same mechanism as skills |
| `output-styles/*.md` | Project and global | yes | Instruction sets adjusting how Claude works |
| `agents/*.md` | Project and global | yes | Subagent definitions |
| `workflows/*.js` | Project and global | yes | Dynamic workflow scripts; each becomes `/<name>` |
| `agent-memory/<name>/` | Project and global | yes | Subagent persistent memory |
| `~/.claude.json` | Global only | no | App state, OAuth, UI toggles, personal MCP servers |
| `projects/<project>/memory/` | Global only | no | Auto memory |
| `keybindings.json` | Global only | no | Keyboard shortcuts |
| `themes/*.json` | Global only | no | Color themes |

### When each file is read
Source: https://code.claude.com/docs/en/claude-directory.md § "Explore the directory"

| File | When it takes effect (per explorer) |
| --- | --- |
| Project `CLAUDE.md` | Start of every session |
| `.mcp.json` | Servers connect at session start; tool schemas deferred, loaded via tool search |
| `.worktreeinclude` | When a git worktree is created (`--worktree`, `EnterWorktree`, subagent `isolation: worktree`); not read with a non-git WorktreeCreate hook |
| `.claude/settings.json` | Overrides `~/.claude/settings.json`; overridden by local, CLI flags, managed |
| `.claude/settings.local.json` | Highest user-editable settings file; CLI flags and managed still win |
| `rules/` | Unscoped: session start. Scoped: when a matching file enters context |
| `skills/` | On `/skill-name` or when Claude matches the task |
| `commands/` | On `/command-name`; a skill of the same name wins |
| `output-styles/` | Read at startup; mid-session switches apply from next message; a style file created or edited mid-session is picked up after restart (terminal) |
| `agents/` | Own context window when invoked or @-mentioned |
| `workflows/` | Loaded at startup; project beats personal of same name |
| `agent-memory/<name>/MEMORY.md` | First 200 lines (cap 25KB) into subagent system prompt at start |
| `~/.claude.json` | Read at session start; written back by `/config` and trust prompts |
| `~/.claude/CLAUDE.md` | Start of every session, every project |
| `~/.claude/settings.json` | Defaults; project and local override matching keys |
| `keybindings.json`, `themes/` | Session start and hot-reloaded on edit |
| `projects/<project>/memory/` | `MEMORY.md` at start; topic files on demand |

Settings merge notes from the explorer: array settings such as `permissions.allow` combine across
scopes; scalar settings such as `model` take the most specific value. Permission rules approved
in-session go to `.claude/settings.local.json`. Subagent memory scopes: `memory: project` >
`.claude/agent-memory/`, `memory: local` > `.claude/agent-memory-local/`, `memory: user` >
`~/.claude/agent-memory/`.

Discrepancy to note: the explorer's `~/.claude/CLAUDE.md` entry says project instructions take
priority on conflict, while memory.md § "User-level rules" says neither user nor project rules
override the other. Treat precedence between instruction files as order-in-context, not override.

### Files outside the explorer
Source: https://code.claude.com/docs/en/claude-directory.md § "What's not shown"; https://code.claude.com/docs/en/claude-directory.md § "Frontmatter fields by file"

- `managed-settings.json` (system-level, OS-dependent), `CLAUDE.local.md` (project root),
  `AGENTS.md` (project root, `.claude/`, or any directory), `~/.claude/plugins` (installed plugins).
- Rule front matter accepts only `paths`. Skill, command, agent, and output-style front matter field
  lists are given in the source table; `agents/*.md` includes `omitClaudeMd` and `memory`.

### Application data and retention
Source: https://code.claude.com/docs/en/claude-directory.md § "Application data"; https://code.claude.com/docs/en/claude-directory.md § "Cleaned up automatically"; https://code.claude.com/docs/en/claude-directory.md § "Kept until you delete them"; https://code.claude.com/docs/en/claude-directory.md § "Plaintext storage"; https://code.claude.com/docs/en/claude-directory.md § "Clear local data"

- Transcripts at `~/.claude/projects/<project>/<session>.jsonl` hold every message, tool call, and
  tool result, in plaintext. Subagent transcripts under `<session>/subagents/`; large tool outputs
  under `<session>/tool-results/`.
- `cleanupPeriodDays` sweep: default 30, minimum 1, `0` is a validation error. Covers transcripts,
  `file-history/`, `plans/`, `debug/`, `paste-cache/`, `session-env/`, `tasks/`,
  `shell-snapshots/`, `backups/`, and others. Skipped under `claude -p --bare`, and paused when the
  retention period cannot be determined (see `retention_sweep` event).
- Not swept: auto memory files, `history.jsonl`, `stats-cache.json`, `remote-settings.json`,
  `cache/changelog.md`, `policy-limits.json`. `sessions/` holds one file per running session.
- State files to keep: `.credentials.json`, `agent-memory/`, `jobs/`, `daemon/`.
- `claude project purge [path] [--dry-run|--yes|--all|-i]` deletes a project's transcripts, auto
  memory, per-session tasks/debug/file-history, matching `history.jsonl` lines, and its
  `~/.claude.json` entry.
- `CLAUDE_CODE_SKIP_PROMPT_HISTORY` skips transcript and history writes; `--no-session-persistence`
  with `-p` also works.

## What fills the context window
Source: https://code.claude.com/docs/en/context-window.md § "Explore the context window"; https://code.claude.com/docs/en/context-window.md § "What the timeline shows"

Startup content in the simulation's order (token counts are the page's representative values in a
200,000-token window, not measurements):

| Item | Example tokens | Notes |
| --- | --- | --- |
| System prompt | 4,200 | Always first; invisible |
| Auto memory (`MEMORY.md`) | 680 | First 200 lines or 25KB |
| Environment info | 280 | cwd, platform, shell, OS, git repo flag; git branch/status/commits as separate block |
| MCP tools (deferred) | 120 | Names only; schemas via tool search. `ENABLE_TOOL_SEARCH=auto` loads schemas upfront if within 10% of window; `=false` loads all |
| Skill descriptions | 450 | One line each; `disable-model-invocation: true` skills excluded; not re-injected after `/compact` |
| `~/.claude/CLAUDE.md` | 320 | Every project |
| Project CLAUDE.md | 1,800 | Project root |

During work:

- Each file read adds its content (terminal shows a one-liner only).
- Path-scoped rules load automatically when a matching file is read; the terminal shows
  "Loaded .claude/rules/<name>.md", not the content.
- In the page's PostToolUse example, hook output enters context via
  `hookSpecificOutput.additionalContext`, and plain stdout on exit 0 does not, since it goes to the
  debug log. Per hooks.md, plain stdout *is* added as context for `UserPromptSubmit`,
  `UserPromptExpansion`, `SessionStart` and `PostModelSwitch`.
- `!command` input and output enter context as part of your message.
- A `disable-model-invocation` skill costs zero context until invoked.
- Subagents: separate context window; they load CLAUDE.md (built-in Explore and Plan skip it), the
  same MCP and skill setup, but not the conversation or main auto memory. Only the final text plus
  a metadata trailer returns.
- Output style and `--append-system-prompt` text also load at startup when configured.

## Compaction
Source: https://code.claude.com/docs/en/context-window.md § "When your context fills up"; https://code.claude.com/docs/en/context-window.md § "Explore the context window"

- Auto-compaction runs as the limit approaches and works like `/compact`.
- The summary keeps requests and intent, key concepts, files examined or modified with important
  snippets, errors and fixes, pending tasks, current work. Verbatim tool output and intermediate
  reasoning are gone.
- Options: `/compact <focus>`; `/rewind` > **Summarize from here** / **Summarize up to here**;
  `/autocompact <tokens>` (e.g. `500k`) sets the trigger point; `/clear` between tasks; delegate
  reads to subagents.
- 1M-token windows exist for Fable models, Sonnet 5, Opus 4.6+, Sonnet 4.6. Thresholds per model are
  on a different page (not in these sources).

### What survives compaction
Source: https://code.claude.com/docs/en/context-window.md § "What survives compaction"; https://code.claude.com/docs/en/memory.md § "Instructions seem lost after `/compact`"

| Content | After compaction |
| --- | --- |
| System prompt, output style | Still apply |
| Project-root CLAUDE.md, unscoped rules | Re-injected from disk |
| Auto memory | Re-injected from disk |
| Git status snapshot | Freshly re-read |
| Plan-mode plan | Re-injected from disk |
| Path-scoped rules | Reloaded only when a matching file is read again |
| Nested CLAUDE.md | Reloaded only when a file in that subdirectory is read again |
| Files read/edited | Up to five re-read, most recently modified first; >5,000 tokens become a `Referenced file` path |
| Invoked skill bodies | Re-injected, 5,000 tokens per skill, 25,000 total, oldest dropped; truncation keeps the top |
| Background commands/subagents | Keep running; Claude is reminded |
| Hook-added context | Summarized away |
| SessionStart hooks matching `compact` | Run; output added |

- Since v2.1.198 the summarization request inherits the session's extended-thinking setting.
- Path-scoped rules and nested CLAUDE.md live in message history, so compaction summarizes them away.
  To persist a rule across compaction, drop its `paths:` or move it to project-root CLAUDE.md.
- Instructions given only in conversation do not survive.

## Prompt caching
Source: https://code.claude.com/docs/en/prompt-caching.md § "How Claude Code uses prompt caching"; https://code.claude.com/docs/en/prompt-caching.md § "How the cache is organized"

- Each message re-sends the full context. The API caches by exact prefix match; any change recomputes
  everything after it. No per-file or per-segment caching.

| Layer | Content | Changes when |
| --- | --- | --- |
| System prompt | Core instructions, tool definitions | Loaded tool definition set changes |
| Project context | CLAUDE.md, auto memory, unscoped rules | Session start, `/clear`, `/compact` |
| Conversation | Messages, responses, tool results | Every turn |

- Model and (on most models) effort level each have their own cache.
- Plan mode and skill loading append messages and keep the prefix.
- Mid-conversation system context such as file-change notices is appended and cached (uncached if
  `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` is set).
- Cache location: Anthropic infra for API key, subscription, Claude Platform on AWS; provider infra
  for Bedrock / Google Agent Platform; Foundry depends on hosting; gateways depend on how they treat
  `cache_control` markers (forward: fine; 400 then marker moved to last message; silently stripped:
  whole history uncached every turn).

### Why CLAUDE.md edits do not apply mid-session
Source: https://code.claude.com/docs/en/prompt-caching.md § "Editing CLAUDE.md mid-session"; https://code.claude.com/docs/en/prompt-caching.md § "Editing files in your repository"

- Project-root and user CLAUDE.md are read once at session start and held in memory.
- A mid-session edit neither invalidates the cache nor applies. The session keeps the start-time
  version until `/clear`, `/compact`, or a restart.
- Nested CLAUDE.md and `paths:` rules load when a matching file is first read. Editing before that
  takes effect; after load, the content is conversation history and an edit does not change it.
- Other repo files: an edit to an already-read file does not rewrite the earlier read; Claude Code
  appends a `<system-reminder>` that the file changed, and Claude re-reads if needed.
- On `/compact`, project context reloads from disk and cache-hits only if CLAUDE.md and memory are
  unchanged since session start.

### Actions that invalidate the cache
Source: https://code.claude.com/docs/en/prompt-caching.md § "Actions that invalidate the cache"; https://code.claude.com/docs/en/prompt-caching.md § "Switching models"; https://code.claude.com/docs/en/prompt-caching.md § "Changing effort level"; https://code.claude.com/docs/en/prompt-caching.md § "Turning on fast mode"; https://code.claude.com/docs/en/prompt-caching.md § "Connecting or disconnecting an MCP server"; https://code.claude.com/docs/en/prompt-caching.md § "Enabling or disabling a plugin"; https://code.claude.com/docs/en/prompt-caching.md § "Denying an entire tool"; https://code.claude.com/docs/en/prompt-caching.md § "Compacting the conversation"; https://code.claude.com/docs/en/prompt-caching.md § "Accumulating many images"; https://code.claude.com/docs/en/prompt-caching.md § "Upgrading Claude Code"

| Action | Effect |
| --- | --- |
| `/model` switch (also `opusplan` plan toggles, automatic model fallback, a skill/command with a different `model`) | Full re-read on new model. `/model` confirms only while cache is warm (TTL check since v2.1.238); PreModelSwitch hook can require or skip |
| Effort change | Full re-read on most models; Opus 5.5 and Fable 5.1 with API key or subscription keep cache (not on Bedrock, Agent Platform, Claude apps gateway, with `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS`, or HIPAA) |
| Fast mode on | Header is part of cache key: one miss per conversation; later toggles keep cache |
| MCP server connect/disconnect | Only if tools are loaded into the prefix (tool search off/unavailable, `alwaysLoad`, threshold loading). Deferred tools just append. MCP config edits only apply on restart |
| Plugin enable/disable | Skills, commands, agents, hooks, monitors, themes append (cache kept); plugin MCP servers follow MCP rules. `/reload-plugins` warns and holds a full-re-read change; `--force` applies |
| Bare tool deny rule (`Bash`, `Bash(*)`, `"*"`, `"mcp__*"`) | Keeps cache under tool search; otherwise removes the definition and invalidates. Scoped denies and allow/ask rules never change the prefix |
| `/compact` | Invalidates conversation layer by design; system prompt layer reused |
| Many images/PDFs | Oldest batch dropped; reprocess from earliest affected message |
| Upgrade | New system prompt/tools; first session after restart is uncached. Auto-update applies on next launch only; `DISABLE_AUTOUPDATER=1` controls timing |

### Actions that keep the cache
Source: https://code.claude.com/docs/en/prompt-caching.md § "Actions that keep the cache"; https://code.claude.com/docs/en/prompt-caching.md § "Changing permission mode"; https://code.claude.com/docs/en/prompt-caching.md § "Changing output style"; https://code.claude.com/docs/en/prompt-caching.md § "Invoking skills and commands"; https://code.claude.com/docs/en/prompt-caching.md § "Running `/recap`"; https://code.claude.com/docs/en/prompt-caching.md § "Rewinding the conversation"

- Editing repo files; editing CLAUDE.md (no effect until reload, see above).
- Permission mode changes (except `opusplan` + plan mode, a model switch).
- Output style change: new style delivered as a message, applies from next message (before
  v2.1.251 it waited for `/clear` or a new session).
- Skills and commands inject user messages at invocation.
- `/recap` appends output; `/rewind` truncates to an already-cached prefix.
- Spawning a subagent.

### Resume, TTL, scope
Source: https://code.claude.com/docs/en/prompt-caching.md § "Resuming a session"; https://code.claude.com/docs/en/prompt-caching.md § "Cache lifetime"; https://code.claude.com/docs/en/prompt-caching.md § "Which TTL each request gets"; https://code.claude.com/docs/en/prompt-caching.md § "Choose the TTL yourself"; https://code.claude.com/docs/en/prompt-caching.md § "Cache scope"

- Resumed sessions keep their original system prompt by default; an upgrade or new
  `--append-system-prompt` takes effect after compaction or in a new conversation.
- TTLs: 5 minutes or 1 hour; each cache hit resets the timer.

| Bucket | Subscription within plan | Usage credits, API key, cloud |
| --- | --- | --- |
| Main conversation | 1 hour | 5 minutes |
| Everything else (subagents, workflows, teammates, forks, compaction, titles) | 5 minutes (server-chosen helpers 1 hour) | 5 minutes |

- Controls (v2.1.242+): `promptCacheTtl` / `CLAUDE_CODE_PROMPT_CACHE_TTL` (main);
  `subagentPromptCacheTtl` / `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL` (everything else). Values `5m`
  or `1h` only.
- Priority: `FORCE_PROMPT_CACHING_5M=1` > bucket env var > bucket setting > subagent
  `experimental.cacheTtl` (v2.1.248+) > `ENABLE_PROMPT_CACHING_1H=1` > default.
- Verify: `claude -p "hello" --output-format json`, read `usage.cache_creation`
  (`ephemeral_1h_input_tokens` / `ephemeral_5m_input_tokens`).
- Scope: effectively one machine and one directory. The prefix carries cwd, platform, shell, OS,
  auto memory paths, and the startup git status snapshot (branch, recent commits). Worktrees miss
  each other's cache. Parallel sessions in the same directory share it.

### Monitoring, subagents, disabling
Source: https://code.claude.com/docs/en/prompt-caching.md § "Check cache performance"; https://code.claude.com/docs/en/prompt-caching.md § "Subagents and the cache"; https://code.claude.com/docs/en/prompt-caching.md § "Disable prompt caching"

- `cache_creation_input_tokens` vs `cache_read_input_tokens` per response (statusline
  `current_usage`). Persistently high creation means the prefix keeps changing.
- `/usage` shows a `Prompt cache (main)` line (v2.1.251+) with hit ratio, misses, warmth, and a
  likely miss cause (v2.1.260+). Statusline `prompt_cache` object has the same numbers. OpenTelemetry
  exports cache tokens per user and session.
- Subagents build their own cache; forks, resumed subagents, `/fork` copies, compaction, and
  workflow fan-outs can reuse a prefix.
- Disable with `DISABLE_PROMPT_CACHING` (or `_HAIKU`, `_SONNET`, `_OPUS`, `_FABLE`) set to `1`;
  org-wide via managed settings `env`.

## Not found in source
Source: https://code.claude.com/docs/en/memory.md § "Related resources"

Expected but not stated in these four files:

- The `InstructionsLoaded` hook's input schema, matcher values, and "reason" field names (only its
  purpose is described; details live on the hooks page).
- Any mechanism for hot-reloading project or user CLAUDE.md mid-session other than `/clear`,
  `/compact`, or restart.
- A precedence rule that makes one instruction file override another (sources describe
  concatenation and order in context only; the explorer's "project takes priority" line is the lone
  exception and conflicts with memory.md).
- Exact auto-compaction thresholds per model (deferred to the model-config page).
- A token budget for CLAUDE.md itself beyond the 200-line guidance and the 4 MiB skip limit.
- Any worked example of a path-scoped rule for Dockerfiles or other extensionless file names; only
  extension and directory globs are shown.
- Whether path-scoped rules trigger on Edit/Write of a file not previously read (source says "reads").
- A machine-readable log or receipt of loaded instruction files other than `/context`, `/memory`,
  and the `InstructionsLoaded` hook.
