# Is the extension config actually live? A probe, not a belief

| | |
|---|---|
| Feature | `claude doctor`, `claude --debug`, live settings reload |
| Repo | images |
| Status | proposed (beyond the seed list) |

## What the feature does

Source: https://code.claude.com/docs/en/settings.md § "When edits take effect"; https://code.claude.com/docs/en/debug-your-config.md § "Check hooks"; https://code.claude.com/docs/en/debug-your-config.md § "Test against a clean configuration"

Claude Code watches settings files and applies most edits, including `hooks` and `permissions`,
to the running session. A settings file created mid-session loads if its folder existed at session
start. The project `.claude/` folder is loaded even if it is created during the session.
`claude doctor`, run from a shell, is read-only and starts no session. It reports invalid settings
files, skipped rules, and hooks keys dropped from managed settings. `claude --debug` logs each hook
event, the matchers checked, and each hook's exit code and output. `--safe-mode` together with an
empty `CLAUDE_CONFIG_DIR` gives a clean baseline to compare against.

## What problem of ours it addresses

**Our measurement and the pinned docs disagree.** `images:.claude/hooks/Deny-Heredoc.ps1:36-43`
and `images:END_GOAL.md:182-187` record that the heredoc hook did not arm in the session that
created `.claude/`. A heredoc run minutes later went through. The pinned settings page says the
project `.claude/` folder is loaded even when it is created mid-session. Per AGENTS.md, the
measurement wins and the gap is a finding. Either the behaviour changed between versions, or the
doc describes something narrower than it seems to. Neither the version measured on that day nor the
version the doc describes is recorded.

This is the case for a probe. "The hook is installed" was believed, and it was false for one
session.

## What it would replace or strengthen

It replaces "open /hooks once or start a new session" (`images:END_GOAL.md:187`), which is a ritual,
with a measurement. A script runs `claude doctor`, then a short `claude -p` canary that attempts a
heredoc and asserts the denial. The script is recorded with `claude --version`.

## Acceptance test

1. `claude doctor` in an images clone exits cleanly and reports no invalid settings files and no
   skipped rules. Record its output.
2. Canary: `claude -p` asked to run `cat <<EOF` … `EOF` through Bash. Measure that the denial reason
   from `Deny-Heredoc.ps1` appears in the stream-json output.
3. Reproduce the arming question on the current version. Start a session in a clone with no
   `.claude/`, create it mid-session, push a heredoc. Record armed or not, with `claude --version`.
   That settles the finding.

## Risks

- `claude doctor` has no documented exit codes or machine-readable output
  (see [`../commands-and-debugging.md`](../commands-and-debugging.md), "Not found in source"), so
  test 1 parses text, and that can break.
- `-p` treats the folder as trusted and runs project hooks without a dialog (hooks.md § "Workspace
  trust"). The canary proves the hook works under `-p`. It does not prove the hook works in an
  interactive session in an untrusted folder.
