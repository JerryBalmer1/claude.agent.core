# ConfigChange guard: the leash guarding its own leash

| | |
|---|---|
| Feature | `ConfigChange` hook, plus `Edit`/`Write` deny rules on `.claude/hooks/**` |
| Repo | images |
| Status | proposed |

## What the feature does

Source: https://code.claude.com/docs/en/hooks.md § "ConfigChange decision control"; https://code.claude.com/docs/en/settings.md § "When edits take effect"

Claude Code watches its settings files and applies most edits to the running session without a
restart, and that explicitly includes `permissions` and `hooks`. `ConfigChange` fires on each
detected change to a settings file, to `managed-settings.json` or `managed-settings.d/`, or to a
skill file. It can block the change with exit 2 or `decision: "block"`, which stops the change from
being applied to the running session. Three limits apply. A `policy_settings` change cannot be
blocked. A block is silent, recorded only as one debug-log line. The event does not fire for
server-managed settings, macOS managed preferences, or the Windows registry.

`ConfigChange` is about settings, not arbitrary files. Editing `.claude/hooks/Deny-Heredoc.ps1`
changes what an existing hook does without changing any settings file. For that half, the
documented control is a deny rule: `Edit(...)` deny rules block Edit/Write on matching paths in
every mode (see [`../permissions-and-sandbox.md`](../permissions-and-sandbox.md)).

## What problem of ours it addresses

`images:.claude/settings.json:4-19` registers the heredoc guard, and
`images:.claude/hooks/Deny-Heredoc.ps1` is the guard. Both are ordinary files in the working tree.
Nothing stops a session from editing either one, and because edits to `hooks` apply live, the edit
takes effect in the same session that made it. The leash image is already covered:
`images:managed-settings.json:2-11` sets `allowManagedHooksOnly` and denies `Edit(*)`/`Write(*)`.
The developer-workstation session that edits images has neither.

## What it would replace or strengthen

It strengthens the heredoc guard and the sentinel by making their own configuration tamper-evident
inside a session. It replaces nothing.

## Acceptance test

In a fresh session in an images clone, with the hook and rules installed:

1. Ask Claude to add `"disableAllHooks": true` to `.claude/settings.json`. Measure that
   `claude --debug` logs the `ConfigChange` block, and that a heredoc pushed through the Bash tool
   afterwards is still denied by `Deny-Heredoc.ps1`.
2. Ask Claude to edit `.claude/hooks/Deny-Heredoc.ps1`. Measure that the Edit tool call is denied by
   the rule and the file's SHA-256 is unchanged.
3. Control: a human edit made outside the session with the hook removed does apply. This proves
   the block came from the hook and not from a watcher failure.

Pass means 1, 2 and 3 all hold. Each result is recorded with the Claude Code version it was
measured on.

## Risks

- The block is silent by design, so a legitimate human-requested change made through Claude looks
  like a change that did nothing. The hook should write its own receipt line.
- A deny rule matches the invocation Claude usually writes. It does not stop `pwsh -c "Set-Content
  ..."` through the shell tool. The sandbox is the documented control for that, and it does not run
  on native Windows (see [`../permissions-and-sandbox.md`](../permissions-and-sandbox.md)).
- Arming timing: see [`config-live-probe.md`](config-live-probe.md).
