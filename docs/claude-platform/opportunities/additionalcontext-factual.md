# additionalContext: state facts, not orders

| | |
|---|---|
| Feature | Hook `additionalContext` guidance and cap |
| Repo | images, core |
| Status | proposed |

## What the feature does

Source: https://code.claude.com/docs/en/hooks.md § "Add context for Claude"; https://code.claude.com/docs/en/hooks.md § "JSON output"

A hook can inject text into Claude's context through `additionalContext`. The source advises
phrasing that text as factual statements, not imperatives. Out-of-band text that reads like a
command can trigger Claude's prompt-injection defences, and Claude then shows it to the user instead
of using it. `additionalContext`, `systemMessage`, `initialUserMessage` and plain stdout are capped at
10,000 characters. Over the cap, the text goes to a file and Claude gets the path plus a preview of
up to 2,000 characters, and is not asked to read the file.

## What problem of ours it addresses

Several proposals in this directory inject state:
[`state-skill.md`](state-skill.md) (the output of `state.ps1`),
[`precompact-receipt.md`](precompact-receipt.md) (re-injection after compaction), and
[`instructionsloaded-receipt.md`](instructionsloaded-receipt.md). The house style of our deny text
is imperative. `images:.claude/hooks/Deny-Heredoc.ps1:87` says "PowerShell only - see AGENTS.md. …
Use the PowerShell tool". That is a `permissionDecisionReason`, not `additionalContext`, so the
guidance does not bind it today. It will bind the first state-injecting hook written in the same voice.

## What it would replace or strengthen

It sets a style rule for injected text before the first injecting hook is written. "Branch is
`develop`, 0 ahead, tree clean, chain tip seq 17" rather than "You MUST run state.ps1 first".

## Acceptance test

For any hook added under these proposals:

1. A Pester test asserts the injected string is 10,000 characters or fewer for the largest
   realistic input. For `state.ps1`, that is a repository with 50 open branches.
2. A lint asserts that no line of injected text starts with an imperative from a fixed list
   (`You must`, `Always`, `Never`, `Do not`, `Run`, `Stop`).
3. One live session per hook: measure that the injected facts show up in Claude's next reply as
   used context and are not quoted back to the user as suspicious.

## Risks

- The imperative list is crude. It catches style, not intent.
- Test 3 depends on model behaviour and must be recorded with the model and version it ran on.
