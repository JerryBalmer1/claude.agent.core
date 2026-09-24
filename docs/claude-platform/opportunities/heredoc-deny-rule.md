# Bash(*<<*) deny rule: hard control, with the hook as the reporting layer

| | |
|---|---|
| Feature | Permission deny rule `Bash(*<<*)` |
| Repo | images |
| Status | proposed, pending measurement |

## What the feature does

Source: https://code.claude.com/docs/en/permissions.md § "Wildcard patterns"; https://code.claude.com/docs/en/permissions.md § "Compound commands"; https://code.claude.com/docs/en/permissions.md § "What a Bash rule doesn't match"; https://code.claude.com/docs/en/permissions.md § "Extend permissions with hooks"; https://code.claude.com/docs/en/hooks.md § "Timeouts"

What the source states:

- In a Bash rule, `*` matches any text, including spaces, and may appear anywhere in the pattern.
- Commands are split on `&&`, `||`, `;`, `|`, `|&`, `&` and **newlines**. A deny rule fires if any
  subcommand matches, including one nested in a subshell or a command substitution.
- Deny rules apply in every mode, and a hook returning `allow` does not bypass them.
- A Bash rule matches the command text Claude writes. It is **not** a security boundary around the
  program, so `bash -c '...'` and similar forms escape it. For inspecting the full command text, the
  source points to a PreToolUse hook.
- A timed-out PreToolUse command hook does not block. The call continues through the normal
  permission flow.

What the source does **not** state: how a heredoc splits. A heredoc body contains newlines, and
newlines are separators, so the `<<` token lands in the first subcommand and the body lines become
subcommands of their own. The pinned pages give no example with `<<` in a rule
(see [`../permissions-and-sandbox.md`](../permissions-and-sandbox.md), "Not found in source").

## What problem of ours it addresses

`images:.claude/hooks/Deny-Heredoc.ps1:80-91` denies any Bash command containing `<<`. The hook is
the only guard in a developer session, and it has three documented soft spots. A timeout fails
open (the standing blocker at `images:END_GOAL.md:55`). A malformed payload fails open
(`Deny-Heredoc.ps1:24-29`). And it did not arm in the session that wrote it
(`images:END_GOAL.md:182-187`). In the leash image the question does not arise:
`images:managed-settings.json:7` denies `Bash` outright.

## What it would replace or strengthen

If the rule holds, it becomes the gate and the hook becomes the reporting layer, the part that
explains why and points at `AGENTS.md`. If the rule does not hold, the hook stays the gate and this
file records why. The brief says "measure which", so the outcome is not decided here.

## Acceptance test

A matrix of at least these forms, each sent through the Bash tool in a session that has only the
rule (hook removed), then only the hook, then both:

| Form | Example shape |
|---|---|
| plain heredoc | `cat <<EOF` … `EOF` |
| quoted delimiter | `cat <<'EOF'` |
| tab-stripping | `cat <<-EOF` |
| herestring | `cat <<< "x"` |
| after `&&` | `cd x && cat <<EOF` |
| inside `$(...)` | `echo "$(cat <<EOF` … |
| via `bash -c` | `bash -c 'cat <<EOF'` |
| git commit | `git commit -F - <<EOF` |

Measure blocked or ran for each cell. The rule may retire the hook's gate role only if it blocks
every form the hook blocks. Otherwise the cells it misses are written into this file and the hook
stays.

## Risks

- Newline splitting may put `<<` and the body in different subcommands in a way that interacts with
  the `*` match in undocumented ways. That is why this is measured and not argued.
- A `<<` inside a quoted string, such as a commit message about heredocs, is a false positive. The
  hook has the same problem today.
- The `bash -c` row is expected to escape the rule, since the source says so. That row is the
  hook's permanent reason to exist.
