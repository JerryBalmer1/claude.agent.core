# The sentinel's timeout fails open, and the documented way out

| | |
|---|---|
| Feature | Hook timeout semantics; Agent SDK callback hooks |
| Repo | images |
| Status | proposed (beyond the seed list) |

## What the feature does

Source: https://code.claude.com/docs/en/hooks.md § "Timeouts"; https://code.claude.com/docs/en/hooks-guide.md § "Hooks and permission modes"

Claude Code cancels a `command`, `http` or `mcp_tool` hook that reaches its timeout and discards
its output. On `PreToolUse`, a timed-out command hook **does not block**. The call continues
through the normal permission flow, and the source says not to count on a stalled hook as a gate.
**An Agent SDK callback hook that exceeds its timeout does block the tool call.** Separately, deny
rules from settings are evaluated whatever a hook returns. A hook can tighten permissions and
cannot loosen them.

## What problem of ours it addresses

"Command-hook timeout fails open" is a standing blocker, listed on every run
(`images:END_GOAL.md:55`, `images:AGENTS.md:160-162`). The sentinel
(`images:hooks/sentinel.ps1`) is registered as a command hook with a 15-second timeout
(`images:managed-settings.json:13-26`). It fails closed with exit 2 on its own internal error, but a
timeout never reaches that code. The pinned docs confirm the blocker exactly and add one fact the
record does not have: the other hook family behaves the opposite way.

## What it would replace or strengthen

Two options, recorded without choosing between them:

1. Keep the command hook, and rely on the managed deny floor (`images:managed-settings.json:6-11`)
   as the part that fails closed. That floor already denies `Bash`, `Shell(*)`, `Edit(*)` and
   `Write(*)`, so a sentinel timeout on those tools changes nothing. The exposure is the tools the
   floor does not deny. Enumerate them.
2. Run the leash through the Agent SDK with the sentinel as a callback hook, where a timeout blocks.
   That is a larger change to how the leash image launches.

## Acceptance test

1. Give a copy of the sentinel an artificial 20-second sleep in Enforce mode. Call each tool the
   leash exposes and measure which calls run. The expected result is that only tools outside the
   deny floor run. Any tool that runs is the measured size of the hole.
2. For option 2, the same test through an SDK callback with a 15-second timeout. Measure that every
   call is blocked.
3. Write the tool list from test 1 into this file. If it is empty, the standing blocker can be
   downgraded, with this test cited as the evidence.

## Risks

- Option 2 changes the leash's launch path and the entrypoint's tool check
  (`images:END_GOAL.md:569-573`). It is not a hook change.
- Test 1 needs a sentinel copy that sleeps. That copy must never ship, so it lives in a test
  fixture.
