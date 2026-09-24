---
verified: 2026-09-23
sources:
  - https://code.claude.com/docs/en/permissions.md
  - https://code.claude.com/docs/en/permission-modes.md
  - https://code.claude.com/docs/en/sandboxing.md
  - https://code.claude.com/docs/en/sandbox-environments.md
  - https://code.claude.com/docs/en/cli-reference.md
  - https://code.claude.com/docs/en/debug-your-config.md
scope: How Claude Code decides whether a tool call runs (permission rules, rule syntax, evaluation order, permission modes, managed locks) and what an allowed shell command can reach once it runs (the Bash sandbox and outer isolation environments).
---

# Permissions and sandbox

This file covers two layers that the source pages call complementary. Permission rules and
permission modes decide, before a tool runs, whether it runs and whether the user is asked. The
sandbox (and outer environments such as containers and VMs) limits what a shell command can touch
once it is running. Hooks sit alongside permission rules but cannot loosen them. Everything below is
restated from the six source pages; anything the sources do not say is listed at the end.

Version numbers (`v2.1.x`) are quoted from the sources only where they mark a behavior change.

## Rule kinds and evaluation order
Source: https://code.claude.com/docs/en/permissions.md § "Manage permissions"

Rules live under `permissions.allow`, `permissions.ask`, and `permissions.deny`, and can be viewed
and edited with `/permissions` (which shows the settings file each rule came from). Edits made in the
dialog mid-turn apply from Claude's next tool call (before v2.1.234 they were queued to turn end).

| Kind  | Effect                                            |
| :---- | :------------------------------------------------ |
| allow | Tool use proceeds without manual approval         |
| ask   | Always prompts for confirmation                   |
| deny  | Tool use is prevented                             |

Evaluation facts:

- Order is fixed: deny, then ask, then allow. The first match in that order wins.
- Specificity does not reorder anything. `Bash(aws *)` in deny blocks `aws s3 ls` even if
  `Bash(aws s3 ls)` is in allow. An allow rule cannot carve an exception out of a deny rule.
- The same applies between ask and allow: a matching ask rule prompts even if a narrower allow rule
  also matches.
- A deny rule that is a bare tool name (for example `Bash`) removes the tool from Claude's context
  entirely. A scoped deny (for example `Bash(rm *)`) leaves the tool visible and blocks matching calls.
- `EndConversation` is the one exception: a deny cannot remove it while any other tool remains, and an
  ask rule never prompts for it.
- The source notes that rules are enforced by Claude Code, not by the model; `CLAUDE.md` and prompt
  text shape intent but do not change what is allowed.

## Rule syntax
Source: https://code.claude.com/docs/en/permissions.md § "Permission rule syntax"; § "Match all uses of a tool"; § "Use specifiers for fine-grained control"

Form is `Tool` or `Tool(specifier)`. Parentheses inside a specifier are literal (no escaping).

| Rule                           | Meaning                                              |
| :----------------------------- | :--------------------------------------------------- |
| `Bash`                         | every Bash command                                   |
| `Bash(*)`                      | same as `Bash`; as deny, also removes the tool       |
| `Bash(npm run build)`          | exactly that command                                 |
| `Read(./.env)`                 | reading `.env` in the current directory              |
| `WebFetch(domain:example.com)` | fetches to example.com                               |

### Matching on an input parameter
Source: https://code.claude.com/docs/en/permissions.md § "Match by input parameter"

- Deny and ask rules (not allow rules) may use `Tool(param:value)` on any built-in tool, for example
  `Agent(model:opus)`, `Agent(isolation:worktree)`, `Bash(run_in_background:true)`.
- Only direct top-level scalar fields match; nested fields do not. One parameter per rule.
- `*` in the value matches any sequence; without `*` the match is exact. An omitted parameter never
  matches (`Agent(model:*)` does not match a call with no `model`).
- The value is compared to the literal input before normalization (`opus` alias, not a full model ID).
  Whitespace around the colon is ignored.
- The primary content field cannot be matched this way: `command` (Bash, PowerShell), `file_path`
  (Read, Edit, Write), `path` (Grep, Glob), `notebook_path`, `url` (WebFetch). `Bash(command:rm *)`
  is ignored with a startup warning because a compound command could bypass it.
- For MCP tools, a parameter rule has to be passed as a deny rule via `--disallowedTools`; a settings
  file's `mcp__` rule with parentheses is skipped and reported as invalid.
- The unsandboxed-retry parameter is matchable: an ask rule `Bash(dangerouslyDisableSandbox:true)`
  forces a prompt for every unsandboxed retry (see the sandbox escape hatch below).

### Wildcards in Bash specifiers
Source: https://code.claude.com/docs/en/permissions.md § "Wildcard patterns"

- `*` matches any text, including spaces. A rule with no `*` matches one exact command.
- `*` may appear at the start, middle, or end of the pattern.
- Everything before the first `*` is matched as written, so the leading words are what constrain the
  rule. `Bash(git log *)` covers only `git log`; `Bash(git *)` covers every git subcommand.
- Claude Code warns at startup about an allow rule with `*` before the subcommand (e.g.
  `Bash(git * main)`).
- A trailing ` *` (space then star) also matches the bare command, but only if it is the rule's only
  wildcard. The space is significant: `Bash(ls *)` does not match `lsof`; `Bash(ls*)` does.
- `:*` at the very end equals a trailing ` *` (`Bash(ls:*)` = `Bash(ls *)`). Elsewhere the colon is a
  literal character (`Bash(git:* push)` matches no git command).

| Rule                   | Matches (examples from source)                         | Does not match              |
| :--------------------- | :----------------------------------------------------- | :-------------------------- |
| `Bash(npm run *)`      | `npm run build`, `npm run test --watch`, `npm run`     | `npm install`               |
| `Bash(git log * main)` | `git log --oneline main`                               | `git log main`              |
| `Bash(git * main)`     | `git merge main`, `git -c core.fsmonitor=<script> diff main` | `git log`             |
| `Bash(* --version)`    | `node --version`, `bash -c 'echo hi' --version`        | `node -v`                   |
| `Bash(* --help *)`     | `npm --help x`                                         | `npm --help`                |

The leading-`*` rows show that a pattern can begin with a wildcard and anchor on text in the middle
or end of a command string.

### Tool-name globs
Source: https://code.claude.com/docs/en/permissions.md § "Tool name wildcards"

- Deny and ask rules accept globs in the tool-name position; the glob must match the full name.
  `"*"` matches every tool; `"mcp__*"` every MCP tool. A bare-name glob deny removes matched tools
  from context (same `EndConversation` exception).
- Allow rules accept a tool-name glob only after a literal `mcp__<server>__` prefix with a glob-free
  server segment (`mcp__puppeteer__*`, `mcp__github__get_*`). Unanchored allow globs (`"*"`, `"B*"`,
  `"mcp__*"`) are skipped with a warning.
- Deny/ask rules naming no known tool produce a startup warning (names containing `_` or `*`, and
  removed tools such as `TaskOutput`, are exempt).
- Rules and hook matchers use canonical tool names, not UI labels (label `Stop Task` = name `TaskStop`).

## Bash rules in detail
Source: https://code.claude.com/docs/en/permissions.md § "Bash"

Bash rules match the whole command text, with `*` standing for any text, after compound-command
splitting and wrapper stripping.

### Compound commands and operators
Source: https://code.claude.com/docs/en/permissions.md § "Compound commands"

- Recognized separators: `&&`, `||`, `;`, `|`, `|&`, `&`, and newlines.
- For allow: every subcommand must independently match; `Bash(safe-cmd *)` does not cover
  `safe-cmd && other-cmd`.
- For deny and ask: the rule applies if any subcommand matches, including commands nested in a
  subshell, a command substitution, or a control-flow body such as a `for` loop.
  Example from source: ask rule `Bash(git clean *)` still prompts for `cd /tmp && git clean -f` and
  `echo "$(git clean -f)"`, even in auto mode.
- A dangling `&&` or `||` (e.g. `npm test &&`) makes the command unparseable; it is not split, so an
  allow rule like `Bash(npm *)` does not approve it.
- "Yes, and don't ask again" on a compound command saves one rule per subcommand needing approval
  (max 5), not one rule for the whole string.

### Wrappers and leading assignments
Source: https://code.claude.com/docs/en/permissions.md § "Wrappers"

- Stripped before matching (fixed, not configurable): `timeout`, `time`, `nice`, `nohup`, `stdbuf`,
  builtins `command` and `builtin`, zsh `noglob`. Not stripped: `command -v`, zsh `nocorrect`.
- Bare `xargs` (no flags) is stripped; `xargs -n1 grep ...` is matched as an `xargs` command.
- Leading env assignments: allow rules match past only known-safe variables; deny and ask rules match
  past any leading assignment (`Bash(rm *)` in deny matches `FOO=bar rm -rf tmp/`).
- Environment runners (`direnv exec`, `devbox run`, `mise exec`, `npx`, `docker exec`) are not
  stripped; `Bash(devbox run *)` covers anything after `run`.
- Exec wrappers `watch`, `setsid`, `ionice`, `flock`, and `find` with `-exec`/`-delete`, cannot be
  auto-approved by a prefix rule; only an exact full-string rule approves them.

### What a Bash rule does not match
Source: https://code.claude.com/docs/en/permissions.md § "What a Bash rule doesn't match"

The source states plainly that a Bash deny or ask rule covers the form Claude usually writes and
"isn't a security boundary around the program". It does not match the same program invoked another
way:

| Rule in deny/ask   | Stops                  | Does not stop                                                        |
| :----------------- | :--------------------- | :------------------------------------------------------------------- |
| `Bash(curl *)`     | `curl https://...`     | `/usr/bin/curl ...`, `sh -c 'curl ...'`                              |
| `Bash(rm *)`       | `rm -rf build/`        | `/bin/rm -rf build/`, `bash -c 'rm -rf build/'`                      |
| `Bash(git push *)` | `git push origin main` | `git -C . push ...`, `git -c push.default=current push ...`, `git 'push' origin main` |

For enforcement independent of command text the source points to sandboxing; for custom inspection
of the full command text it points to a PreToolUse hook.

### Read-only commands
Source: https://code.claude.com/docs/en/permissions.md § "Read-only commands"

- A built-in, non-configurable set runs without a prompt in every mode (e.g. `ls`, `cat`, `echo`,
  `pwd`, `head`, `tail`, `grep`, `find`, `wc`, `which`, `diff`, `stat`, `du`, `cd`, read-only `git`),
  except where `permissions.blockReadsOutsideWorkingDirectories` fences a path. To gate one, add an
  ask or deny rule.
- In Manual mode these still prompt when: an unquoted glob is used with a command that has
  write/exec-capable flags (`find`, `sort`, `sed`, `git`); `docker` targets another daemon; `file`
  uses `-m`/`-f`; an argument is a Windows UNC path; the command cannot be fully parsed; the command is
  longer than 10,000 characters.
- `cd` + `git` into a different directory prompts (hooks in that directory could run). `cd` + a
  redirect prompts when the redirect's base directory can't be determined (`/dev/null` excepted).
- The source warns that argument-constraining patterns (e.g. restricting `curl` to one URL) are
  fragile, and recommends denying network tools plus `WebFetch(domain:...)`, a PreToolUse hook, and
  the sandbox network allowlist; CLAUDE.md guidance alone "doesn't enforce a boundary".

### Redirections and heredocs
Source: https://code.claude.com/docs/en/permissions.md § "Redirections"

- Output redirects (`>`, `>>`, `2>`) are checked as if Claude wrote the target: Edit allow/deny rules,
  protected paths, working directories. The command's own allow rule does not cover the target. A
  target starting with `~` or containing a glob needs approval.
- Input redirects (`<`) are checked against Read allow/deny rules and working directories (v2.1.257+).
  Glob targets, or relative targets after a `cd` in the same command, need approval even with an allow.
- Not checked, because no file is behind them: `/dev/null`, fd forms (`2>&1`, `<&3`), and
  here-docs and here-strings.
- `tee` destinations are checked like output redirects (v2.1.269+), including in pipelines.

What the source supports about a heredoc (`<<`) and Bash deny rules:

- The redirection check explicitly skips here-docs and here-strings; it treats them only as "no file
  behind them". Nothing in the source says a heredoc is flagged, parsed specially, or blocked.
- The only mechanism the source describes for matching arbitrary text is the Bash rule pattern:
  "Bash rules match the whole command text", `*` "matches any text, including spaces", and `*` may sit
  at the start, middle, or end. By those stated rules a deny pattern that starts and ends with `*`
  anchors on text anywhere in a (sub)command string. The source gives no example using `<<` or any
  other operator character inside a pattern.
- Matching happens after compound splitting on `&&`, `||`, `;`, `|`, `|&`, `&`, and newlines. The
  source does not say how a heredoc body (which spans newlines) is treated by that splitter, or whether
  the `<<` token and body remain part of the matched subcommand text.
- The source's own caution applies: deny rules match the command as written and are not a boundary
  around a program (e.g. `bash -c '...'` forms are not matched by a `Bash(rm *)` rule).

## PowerShell rules
Source: https://code.claude.com/docs/en/permissions.md § "PowerShell"

- Same shape as Bash: `*` at any position, `:*` suffix = trailing ` *`, bare `PowerShell` or
  `PowerShell(*)` matches everything.
- Common aliases are canonicalized: `PowerShell(Get-ChildItem *)` also matches `gci`, `ls`, `dir`.
  Matching is case-insensitive.
- Claude Code parses the PowerShell AST; `|`, `;`, and (PowerShell 7+) `&&`/`||` split subcommands;
  every subcommand must match for an allow.

## Read and Edit path rules
Source: https://code.claude.com/docs/en/permissions.md § "Read and Edit"

Coverage:

- `Edit` rules apply to all built-in editing tools. `Read` rules are applied best-effort to Grep,
  Glob, `@file` mentions, and IDE-shared context.
- A `Read` deny also blocks Edit and Write on that path (not NotebookEdit; add an `Edit` deny).
- Path rules written as `Write(...)`, `NotebookEdit(...)`, `Glob(...)`, `MultiEdit(...)` are accepted
  but never consulted (startup warning). Use `Edit(...)` / `Read(...)`. A bare `Write` deny with no
  path works at tool level.
- Read/Edit denies also cover recognized Bash file commands (`cat`, `head`, `tail`, `sed`, `tee`) and
  redirect targets, but not commands that read without naming the file (`grep -r pattern .`) or
  scripts that open files themselves. For OS-level blocking the source points to the sandbox.

Pattern anchors (gitignore syntax):

| Pattern            | Anchors at                                   | Example                          |
| :----------------- | :------------------------------------------- | :------------------------------- |
| `//path`           | filesystem root                              | `Read(//Users/alice/secrets/**)` |
| `~/path`           | home directory                               | `Read(~/Documents/*.pdf)`        |
| `/path`            | the settings source (see next table)         | `Edit(/src/**/*.ts)`             |
| `path` or `./path` | current directory                            | `Read(*.env)`                    |

A single leading `/` is not absolute. Where `/path` resolves:

| Rule defined in                               | `/path` resolves to                  |
| :-------------------------------------------- | :----------------------------------- |
| `.claude/settings.json` or `settings.local.json` | `<primary working directory>/path` |
| `~/.claude/settings.json`                     | `~/.claude/path`                     |
| a `--settings <file>` file                    | `<directory of file>/path`           |
| CLI flags or session rules                    | `<primary working directory>/path`   |

Depth and semantics:

- `*` matches within one path segment; `**` crosses directories.
- Bare filenames match at any depth under the anchor (`Read(.env)` = `Read(**/.env)`).
- Single-segment directory patterns differ by rule type: as allow, `Edit(src/**)` means only
  `<cwd>/src`; as deny/ask, `Read(secrets/**)` matches a `secrets` directory at any depth.
- `Edit(/src/**)` is anchored; `Edit(**/src/**)` matches at any depth, in every rule type.
- Windows paths are normalized to POSIX first (`C:\Users\alice` -> `/c/Users/alice`); `//c/**/.env`
  covers one drive, `//**/.env` all drives.
- Deny/ask patterns starting with `!` are gitignore negations that carve out of earlier rules in the
  same source only; a `!` rule cannot reach `/`, `~/`, or `//`-anchored rules and cannot reopen a file
  inside a wholly blocked directory. A managed deny cannot be cancelled by a `!` elsewhere.
- An unusable deny/ask pattern still guards that exact path; an unusable allow approves nothing.
- Symlinks: allow applies only if both link and target match; deny applies if either matches. On
  macOS/Linux, `//`, `~/`, `/` deny/ask rules also apply at a symlinked directory's real location
  (v2.1.268+).
- Generated rules from "don't ask again" escape gitignore metacharacters; hand-written rules do not.

## WebFetch rules
Source: https://code.claude.com/docs/en/permissions.md § "WebFetch"; § "Allow or deny every fetch"

- `WebFetch(domain:host)` matches the request hostname, case-insensitively, ignoring a trailing `.`.
- `domain:*.example.com` matches subdomains at any depth but not `example.com`.
- In any other position `*` matches only between two dots (`example.*` matches `example.org`, not
  `example.evil.com`). Wildcards need v2.1.172+.

| Rule                 | In allow                                             | In deny                                                   |
| :------------------- | :--------------------------------------------------- | :-------------------------------------------------------- |
| `WebFetch`           | fetch without prompt; sandbox hosts unchanged        | tool removed; sandbox hosts unchanged                     |
| `WebFetch(domain:*)` | fetch without prompt; sandboxed commands reach any host | tool kept, each fetch refused; sandboxed commands reach no host |

Only the `domain:` form feeds the sandbox domain lists. A bare WebFetch deny/ask does not apply to
artifact reads; a `domain:` rule covering `claude.ai` or `*.claudeusercontent.com` does.

## MCP, Agent, and Cd rules
Source: https://code.claude.com/docs/en/permissions.md § "MCP"; § "Agent (subagents)"; § "Cd"

| Rule                                   | Matches                                   |
| :------------------------------------- | :---------------------------------------- |
| `mcp__puppeteer`                       | any tool from server `puppeteer`          |
| `mcp__puppeteer__*`                    | same, wildcard form                       |
| `mcp__puppeteer__puppeteer_navigate`   | one tool                                  |
| `Agent(Explore)`, `Agent(my-agent)`    | a named subagent (use in deny / `--disallowedTools`) |
| `Cd`, `Cd(<path>)`                     | targets of the user-run `/cd` command     |

- Connector tools an organization set to `ask` ignore allow rules and prompt in every mode, including
  auto and bypassPermissions; in dontAsk they are denied.
- In Cowork, deny rules naming the whole `Bash` or `WebFetch` tool also apply to
  `mcp__workspace__bash` / `mcp__workspace__web_fetch`; allow rules do not carry over.
- `Cd` is not model-invocable. Any `Cd` allow rule switches `/cd` to allowlist mode. `Cd` patterns use
  the `//`, `~/`, `/` anchors but match the whole directory path, not gitignore-style.

## Hooks versus permission rules
Source: https://code.claude.com/docs/en/permissions.md § "Extend permissions with hooks"; https://code.claude.com/docs/en/permission-modes.md § "Boundaries you state in conversation"; § "Critical paths"

- PreToolUse hooks run before the permission prompt, for every tool except `EndConversation`. A hook
  can deny, force a prompt, or skip the prompt.
- Hook decisions do not bypass permission rules. Deny and ask rules are evaluated regardless of the
  hook result: a matching deny still blocks and a matching ask still prompts even if the hook
  returned `"allow"` or `"ask"`. This holds for managed deny rules too.
- A blocking hook (exit code 2) stops the call before permission rules are evaluated, so it wins over
  allow rules. The source suggests allowing `"Bash"` and rejecting specific commands with a hook.
- `requiresUserInteraction` MCP tools and org-`ask` connector tools still prompt when a hook allows.
- A PreToolUse `"allow"` never approves an `rm`/`rmdir` targeting a critical path.
- On conversational boundaries in auto mode, the source says they are re-read from the transcript and
  can be lost to compaction; "For a hard guarantee, add a deny rule instead."
- Closest statement on hooks vs rules: a hook can add a block (exit 2) or a deny, but cannot undo a
  deny or ask rule. The sources do not use the phrase "hard control" for permission rules; the
  sandbox-environments page uses "hard control" only when warning about relying on a sandbox.
  debug-your-config.md takes the opposite direction for one case. A `Bash(rm *)` deny misses
  `/bin/rm`, so it says "Use a PreToolUse hook or the sandbox for a hard guarantee".

## Settings precedence and managed settings
Source: https://code.claude.com/docs/en/permissions.md § "Managed settings"; § "Settings precedence"

- Managed settings sit highest; nothing, including CLI arguments, overrides a managed permission rule
  (a few security-sensitive keys are excepted, per a page not in this source set).
- If any level denies a tool, no other level can allow it. `--allowedTools` cannot override a managed
  deny; `--disallowedTools` can add restrictions.
- Across user and project scopes, deny wins in both directions.
- `allowManagedPermissionRulesOnly` makes managed settings the only source of permission rules.
- `permissions.disableBypassPermissionsMode: "disable"` and `permissions.disableAutoMode: "disable"`
  remove those modes; most useful in managed settings, but they work from any scope.
- Embedding hosts can supply managed policy through the SDK `managedSettings` option, including allow
  rules unless `allowManaged*Only` locks are set.

### Project allow rules need workspace trust
Source: https://code.claude.com/docs/en/permissions.md § "Project allow rules and workspace trust"; § "What runs before you trust a folder"

- `permissions.allow` and `permissions.additionalDirectories` in project `.claude/settings.json` apply
  only after the workspace trust dialog is accepted. `deny` and `ask` rules apply regardless.
- `claude -p` and SDK sessions never show the dialog; untrusted project allow rules are not used and a
  `this workspace has not been trusted` warning goes to stderr.
- Hooks, the `env` block, and helper commands in settings files are used even when only a parent folder
  is trusted or in `-p`/SDK runs.
- `.claude/settings.local.json` allow rules skip the trust step unless the file is tracked in git or
  `.claude` is a symlink. The git check runs only after the folder is trusted, or in `-p` and SDK
  runs. Until then the file's rules are held like project settings, except in your configuration
  home.
- Hardening for untrusted repos in `-p`: `--setting-sources user`, `--bare`,
  `--settings '{"disableAllHooks": true}'`, `disabledMcpjsonServers`.

## Working directories and additionalDirectories
Source: https://code.claude.com/docs/en/permissions.md § "Working directories"; § "Move the session to another directory"; § "Additional directories grant file access, not configuration"

- Default access is the launch directory (the primary working directory). Extend it with
  `--add-dir <path>`, `/add-dir`, or `additionalDirectories` in settings.
- Added directories follow the same rules: readable without prompts, edits follow the mode.
- Most UNC network paths cannot be added; on Windows map a drive letter and pass it with `--add-dir`.
- `permissions.blockReadsOutsideWorkingDirectories` makes file tools refuse fenced paths in every mode.
- `/cd <path>` moves the primary directory and loads that directory's project settings, hooks, MCP
  servers, plugins, skills, and subagents, subject to trust.
- `permissions.additionalDirectories` grants file access only. Directories from `--add-dir`/`/add-dir`
  (and the SDK equivalents) additionally load skills, commands, subagents, and only the
  `enabledPlugins`/`extraKnownMarketplaces` settings keys; CLAUDE.md only with
  `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`.
- Hooks and other `.claude/settings.json` keys load from the current working directory's `.claude/`
  only (no parent fallback); `settings.local.json` from the git root except where the root is not used,
  such as on Windows.

## Permission modes
Source: https://code.claude.com/docs/en/permission-modes.md § "Available modes"; https://code.claude.com/docs/en/permissions.md § "Permission modes"

| Mode (config value) | Runs without asking                                            | Intended for                     |
| :------------------ | :------------------------------------------------------------- | :------------------------------- |
| `default` (Manual)  | reads only                                                     | reviewing every action           |
| `acceptEdits`       | reads, file edits, common filesystem commands                  | iterating with later review      |
| `plan`              | reads, plus classifier-approved commands if auto mode available | exploring before changing       |
| `auto`              | everything, with background classifier checks                  | long tasks                       |
| `dontAsk`           | reads and pre-approved tools; anything that would prompt is denied | locked-down CI                |
| `bypassPermissions` | everything                                                     | isolated containers and VMs only |

- `manual` is an accepted alias for `default` (v2.1.200+).
- Deny rules block in every mode, including `bypassPermissions`. Allow rules have no effect in
  `bypassPermissions`.
- Protected-path writes are never auto-approved except in `bypassPermissions` and in interactive
  terminal plan sessions where bypass is available.

### Actions no mode auto-approves
Source: https://code.claude.com/docs/en/permission-modes.md § "Actions no mode auto-approves"

Not auto-approved in any mode, including `bypassPermissions`: explicit ask-rule matches; org-`ask`
connector tools; `AskUserQuestion` and `requiresUserInteraction` MCP tools; `rm`/`rmdir` on a
critical path; cross-session messaging safeguards; reads outside working directories while
`blockReadsOutsideWorkingDirectories` is on (v2.1.257+).

### Which mode a session starts in (is auto the default?)
Source: https://code.claude.com/docs/en/permission-modes.md § "Which mode a session starts in"; § "Start in a different permission mode"

Exactly what the source says: "On Pro, Max, and Team plans, the built-in starting permission mode is
auto mode." It is not the default everywhere. Resolution order: `--permission-mode` (or
`--dangerously-skip-permissions`), then `permissions.defaultMode`, then the built-in default. The
built-in auto default needs v2.1.228+ (macOS/Linux/WSL) or v2.1.233+ (native Windows); earlier it is
Manual.

| Situation (first match wins)                                    | Built-in start |
| :-------------------------------------------------------------- | :------------- |
| any settings file sets `disableAutoMode: "disable"`             | `default`      |
| feature-flag fetching is off                                    | `default`      |
| first session after install/upgrade (unless flags arrive in time) | `default`    |
| `claude -p` or Agent SDK                                        | `default`      |
| Bedrock, Agent Platform, Foundry, Claude Platform on AWS, apps gateway | `default` |
| Pro, Max, or Team, terminal or VS Code                          | `auto`         |
| Enterprise plan or Console API key                              | `default`      |

- `defaultMode: "auto"` or `"bypassPermissions"` in project `.claude/settings.json` or
  `settings.local.json` does not take effect (auto falls to the built-in default; bypass starts
  Manual). Other values apply from any file.
- If auto is selected but unavailable, the session starts in Manual.

### acceptEdits
Source: https://code.claude.com/docs/en/permission-modes.md § "Auto-approve file edits with acceptEdits mode"

Auto-approves file edits plus `mkdir`, `touch`, `rm`, `rmdir`, `mv`, `cp`, `sed` (also with safe env
prefixes or wrappers), only inside working/additional directories. Out-of-scope paths, protected
paths, critical-path removals, and other non-read-only Bash still prompt. With the PowerShell tool,
also `Set-Content`, `Add-Content`, `Clear-Content`, `Remove-Item` (quoted positional args prompt).

### plan
Source: https://code.claude.com/docs/en/permission-modes.md § "Analyze before you edit with plan mode"; § "Review and approve a plan"

Claude researches and proposes without editing source. With auto mode available and
`useAutoModeDuringPlan` on (default), the classifier reviews shell commands; otherwise non-read-only
commands prompt, even under sandbox auto-allow. Approving the plan switches to the chosen mode. In
interactive terminal sessions with bypass available, plan blocks are not enforced.

### auto and its classifier
Source: https://code.claude.com/docs/en/permission-modes.md § "Eliminate permission prompts with auto mode"; § "What the classifier blocks by default"; § "When auto mode falls back"

- A separate classifier model reviews actions before they run and blocks anything that escalates
  beyond the request, targets unrecognized infrastructure, or appears driven by hostile content.
  Explicit ask rules still prompt. The source warns auto mode "does not guarantee safety".
- Decision order (from the "How the classifier evaluates actions" accordion): (1) allow/ask/deny rules
  resolve first, except protected-path writes, critical-path removals, commands carrying per-command
  domains (routed to the classifier), and interaction-required tools (prompt); content-matching ask
  rules fall back to a prompt; (2) read-only actions and in-directory edits auto-approve; (3) all else
  goes to the classifier; (4) on a block, Claude gets the reason and tries another approach.
- On entering auto mode, broad allow rules are dropped: `Bash(*)`, `PowerShell(*)`, wildcarded
  interpreters such as `Bash(python*)`, package-manager run commands, `Agent` allow rules, `Monitor`
  allow rules. They are restored on leaving.
- The classifier sees user messages, non-read-only tool calls, and CLAUDE.md; tool results are
  stripped.
- It also reviews `SendMessage` content, subagent spawn/actions/final report, and critical-path
  removals.
- Default block list includes `curl | bash`, exfiltration, production deploys, force push,
  `git reset --hard` and similar discards, IaC destroy, and many later-version categories; default
  allow list includes local working-directory file ops, declared dependency installs, read-only HTTP,
  pushes to the working repository. `claude auto-mode defaults` prints the full lists.
- Fallback: 3 consecutive or 20 total blocks pause auto mode and resume prompting (not configurable).
  In `-p` without a prompt tool, blocked actions just do not run.
- Availability: turned off org-wide by `permissions.disableAutoMode: "disable"`; model and provider
  requirements apply.

### dontAsk
Source: https://code.claude.com/docs/en/permission-modes.md § "Allow only pre-approved tools with dontAsk mode"

Auto-denies anything that would prompt. Still runs no-approval actions, `permissions.allow` matches,
and PreToolUse-approved calls. Ask-rule matches, `AskUserQuestion`, org-`ask` connectors, and
`requiresUserInteraction` MCP tools are denied. Critical-path removals are denied even with an allow
or hook allow. Not in the Shift+Tab cycle. Cloud sessions ignore it from settings files.

### bypassPermissions
Source: https://code.claude.com/docs/en/permission-modes.md § "Skip all checks with bypassPermissions mode"

- Skips prompts and safety checks, including protected-path writes; the "actions no mode
  auto-approves" still prompt; deny rules still block.
- Enable only at launch (`--permission-mode bypassPermissions`, `--dangerously-skip-permissions`, or
  `defaultMode` in user/`--settings`/managed settings). Refused under `--restricted` (v2.1.248+).
- Refuses to start as root/sudo on Linux and macOS, except inside a recognized sandbox.
- One-time acceptance dialog in interactive use. Cloud sessions ignore it from settings files.
- No protection against prompt injection; admins block it with
  `permissions.disableBypassPermissionsMode: "disable"`.

### Protected and critical paths
Source: https://code.claude.com/docs/en/permission-modes.md § "Protected paths"; § "Critical paths"; § "Remove-Item in PowerShell"

- Protected-path writes: prompted in `default`/`acceptEdits`, classifier in `auto`, denied in
  `dontAsk`, allowed in `bypassPermissions`. Allow rules such as `Edit(.claude/**)` do not pre-approve
  them because the check runs before allow rules. Directories include `.git`, `.claude` (except
  `.claude/worktrees`), `.vscode`, `.idea`, `.husky`, `.devcontainer`; files include shell rc files,
  `.gitconfig`, `.npmrc`, `.mcp.json`, `.claude.json`, and others.
- Critical-path `rm`/`rmdir` (root, top-level dirs, home, drive roots, working dir and parents, globs
  under additional dirs, unguarded `"$VAR"/*`) is never approved by an allow rule or hook allow; a deny
  still blocks it. It is found even inside subshells, brace groups, `$(...)`, backticks, and `<(...)`.
- PowerShell `Remove-Item` on system paths or bare/trailing wildcards is denied in every mode.

## Sandboxed Bash tool
Source: https://code.claude.com/docs/en/sandboxing.md § "Get started"; § "OS-level enforcement"

- OS-enforced filesystem and network boundary for every Bash, PowerShell, and Monitor command and
  their child processes.

| Platform       | Status                                                               |
| :------------- | :------------------------------------------------------------------- |
| macOS          | supported; built-in Seatbelt, nothing to install                     |
| Linux          | supported; needs `bubblewrap` and `socat` (seccomp filter optional)  |
| WSL2           | supported; bubblewrap, same as Linux                                 |
| WSL1           | not supported                                                        |
| native Windows | not supported; run inside WSL2 or a container/VM                     |

- Enable with `/sandbox` (saves to `.claude/settings.local.json`) or `sandbox.enabled: true`.
- If the sandbox cannot start, Claude Code by default warns and runs commands unsandboxed;
  `sandbox.failIfUnavailable: true` makes that a hard failure.

### Sandbox modes
Source: https://code.claude.com/docs/en/sandboxing.md § "Sandbox modes"; § "Auto-allow mode"; § "Regular permissions mode"

- Auto-allow: sandboxable commands run without a prompt; others fall back to regular permission flow.
  Still enforced: deny rules, critical-path removals, content-scoped ask rules (e.g.
  `Bash(git push *)`). A bare `Bash` ask rule is skipped for sandboxed commands (not in plan mode).
- Regular permissions: all commands go through the normal flow even when sandboxed.
- `autoAllowBashIfSandboxed` defaults to `true`.

### Escape hatch and excludedCommands
Source: https://code.claude.com/docs/en/sandboxing.md § "The unsandboxed retry escape hatch"; § "Keep developers from widening the policy"

- After a sandbox violation, Claude may retry with `dangerouslyDisableSandbox`; the retry runs
  unsandboxed through the regular flow (prompt in Manual, classifier in auto).
- `allowUnsandboxedCommands: false` ("Strict sandbox mode") makes Claude Code ignore that parameter;
  every Claude command must then run sandboxed unless listed in `excludedCommands`.
- User-typed `!` shell-mode commands run unsandboxed except in background sessions or Linux sessions
  with `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`.
- `excludedCommands` names commands that run outside the sandbox (e.g. `docker *`). It is an array and
  merges across scopes; there is no managed-only lock for it, so developers can always append entries.

### Filesystem isolation
Source: https://code.claude.com/docs/en/sandboxing.md § "Filesystem isolation"; § "Configure sandboxing"; § "Disable filesystem isolation"

- Default writes: working directory, added directories, session temp dir (`$TMPDIR`). Default reads:
  the whole machine except certain denied directories, which still includes `~/.aws/credentials` and
  `~/.ssh/`.
- Knobs: `sandbox.filesystem.allowWrite`, `denyWrite`, `denyRead`, `allowRead` (narrower path wins),
  merged across scopes. Sandbox paths use `/` absolute, `~/`, and `./` (unlike permission rules'
  `//`).
- `sandbox.filesystem.disabled: true` drops the filesystem layer but keeps network isolation; it is
  honored only from user, managed, or `--settings`, not project settings.

### Sandbox protected paths
Source: https://code.claude.com/docs/en/sandboxing.md § "Protected paths"

Inside writable areas the sandbox still denies writes to `.claude` settings, skills, agents,
commands, hooks, `.mcp.json`, shell rc files, `.git/hooks` and `.git/config`, bare-repo files, and
most of `~/.claude`. No `allowWrite` or `Edit` allow can exempt them; only `filesystem.disabled` does.

### Network isolation
Source: https://code.claude.com/docs/en/sandboxing.md § "Network isolation"; § "Per-command allowed domains in auto mode"

- A proxy outside the sandbox enforces domain rules. No domains are pre-allowed; first use of a domain
  prompts (auto mode: per-command host lists reviewed by the classifier).
- Allowlist = `allowedDomains` + `WebFetch(domain:...)` allow rules; `deniedDomains` blocks.
  `strictAllowlist` denies instead of prompting; managed `allowManagedDomainsOnly` locks to managed
  entries.
- The proxy decides on hostname and does not inspect TLS by default; the source warns about domain
  fronting through broad domains.

### Credentials
Source: https://code.claude.com/docs/en/sandboxing.md § "Protect credentials"; § "Mask credentials"

`sandbox.credentials` lists files and env vars with `mode: "deny"` (block/unset) or `"mask"`
(sentinel value, real value injected by the proxy for `injectHosts`, needs `network.tlsTerminate`).
There is no built-in credential deny list. Mask entries are ignored from project settings.

### Managed enforcement
Source: https://code.claude.com/docs/en/sandboxing.md § "Enforce sandboxing with managed settings"

Managed `{"sandbox": {"enabled": true, "failIfUnavailable": true, "allowUnsandboxedCommands": false}}`
requires the sandbox, refuses to start without it, and removes the retry escape hatch. Boolean keys
use the managed value; array keys merge. `allowManagedReadPathsOnly` locks `allowRead`.

### Relationship to permissions
Source: https://code.claude.com/docs/en/sandboxing.md § "Permission rules"; § "Permission modes"; https://code.claude.com/docs/en/permissions.md § "How permissions interact with sandboxing"

- Permission rules are evaluated before a tool runs, from the command string (plus the classifier in
  auto). The sandbox is enforced by the OS on the running process and "holds regardless of what the
  model chose to run".
- Edit allow rules grant sandbox writes like `allowWrite`; Read/Edit deny rules and WebFetch domain
  rules merge into the sandbox config.
- `/sandbox` is not a permission mode; sandbox auto-allow is distinct from auto mode.

### Limitations
Source: https://code.claude.com/docs/en/sandboxing.md § "Security limitations"; § "Scope"

Not a complete boundary. Risks named: broad domains and domain fronting, `allowUnixSockets` (e.g. the
Docker socket), broad write grants, `enableWeakerNestedSandbox`, macOS `allowAppleEvents`. Read, Edit,
and Write do not go through the sandbox; env vars are inherited unless scrubbed or masked; subagents
share the parent's sandbox config.

## Sandbox environments
Source: https://code.claude.com/docs/en/sandbox-environments.md § "Compare sandboxing approaches"; § "How isolation relates to permission modes"

| Approach            | Isolates                                         | Docker | Notes                                   |
| :------------------ | :----------------------------------------------- | :----- | :-------------------------------------- |
| Sandboxed Bash tool | shell commands and children only                 | no     | file tools, MCP servers, hooks run on host |
| Sandbox runtime     | whole Claude Code process, incl. MCP and hooks   | no     | `@anthropic-ai/sandbox-runtime`, beta   |
| Dev container       | full dev environment                             | yes    | example uses default-deny iptables      |
| Custom container    | full dev environment                             | yes    | own network policy, mounts, seccomp     |
| Virtual machine     | full OS                                          | no     | strongest separation                    |
| Cloud session       | full OS, Anthropic-hosted                        | no     | proxy allowlist; GitHub token held outside |

- `--dangerously-skip-permissions` should always run inside a container, VM, or the sandbox runtime;
  auto mode's classifier is per-action, not an isolation boundary.
- The Bash sandbox alone is not sufficient for fully unattended runs.
- Native Windows: use a container, VM, or WSL2.

### Sandbox runtime and organizational enforcement
Source: https://code.claude.com/docs/en/sandbox-environments.md § "Sandbox runtime"; § "What the runtime blocks on its own"; § "Enforce isolation across an organization"

- Launched as `npx @anthropic-ai/sandbox-runtime claude` with `~/.srt-settings.json`; default denies
  network and most writes. It denies `.git/hooks`, `.git/config`, `.mcp.json`, `.claude/commands`,
  `.claude/agents`, and shell startup files at the project root; on Linux the deny list is built once
  at launch.
- The built-in Bash sandbox is the only approach Claude Code enforces itself (via managed settings);
  containers and VMs are enforced by device management or allowlisting tools.

## Safe mode (`--safe-mode`)
Source: https://code.claude.com/docs/en/cli-reference.md § "CLI flags"; https://code.claude.com/docs/en/debug-your-config.md § "Test against a clean configuration"

`claude --safe-mode` is a troubleshooting switch. It is not a permission mode. It starts a session
with the customisation surfaces turned off. CLAUDE.md, skills, plugins, hooks, MCP servers, custom
commands and agents, output styles, workflows, the status line, LSP servers and auto memory are not
loaded. Authentication, model selection, the built-in tools and **permissions keep working
normally**. That is the difference from `--bare`. The flag also sets `CLAUDE_CODE_SAFE_MODE`.

Managed policy still applies, including hooks configured by managed policy. Managed plugins, managed
skills, the managed CLAUDE.md and MCP servers configured by policy are turned off. The documented use
is an A/B test: if a problem disappears under `--safe-mode`, one of the switched-off surfaces is the
cause. For a baseline that loads nothing from `~/.claude`, point `CLAUDE_CONFIG_DIR` at an empty
directory as well.

Implication for this page: permission rules are the one layer that survives safe mode, apart from
managed policy. Hooks do not.
## Not found in source
Source: https://code.claude.com/docs/en/permissions.md § "Configure permissions"; https://code.claude.com/docs/en/permission-modes.md § "Choose a permission mode"; https://code.claude.com/docs/en/sandboxing.md § "Configure the sandboxed Bash tool"; https://code.claude.com/docs/en/sandbox-environments.md § "Choose a sandbox environment"

Searched all six pages; none of them state the following.

- `Skill(...)` permission rule syntax: not described in these pages; see `skills.md` in this tree, which cites the skills page.
- Any explicit example of a Bash rule containing `<<`, a redirection operator, or another shell
  operator character inside the pattern.
- How the compound-command splitter treats a heredoc body (which contains newlines), and whether the
  `<<` token and body remain in the text a Bash rule is matched against.
- The phrase "hard control" applied to permission rules. The sources say "hard guarantee" twice.
  permission-modes.md says "For a hard guarantee, add a deny rule instead", about conversational
  boundaries. debug-your-config.md says "Use a PreToolUse hook or the sandbox for a hard
  guarantee", about a Bash deny that misses `/bin/rm`. Neither ranks rules above hooks in general.
- The full list of keys that managed settings cannot lock, and the "security-sensitive keys" exceptions
  (referenced but documented on other pages).
- Details of `excludedCommands` pattern syntax beyond the `docker *` example.
