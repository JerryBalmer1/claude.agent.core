# A /state skill: every packet starts from measured state

| | |
|---|---|
| Feature | Skill with `shell: powershell` and `` !`...` `` command injection |
| Repo | images (core has no `state.ps1`) |
| Status | proposed |

## What the feature does

Source: https://code.claude.com/docs/en/skills.md § "Inject dynamic context"; https://code.claude.com/docs/en/skills.md § "How injected commands run"; https://code.claude.com/docs/en/skills.md § "When an injected command fails"

A skill body can contain `` !`command` `` lines and ```` ```! ```` fenced blocks. Claude Code runs
them when the skill is invoked and puts their output into the skill content before the model sees
it. `shell: powershell` sends them through the PowerShell tool. Paths should be anchored with
`${CLAUDE_SKILL_DIR}` or `${CLAUDE_PROJECT_DIR}`, because the working directory follows the
session's current `cd`. If any injected command fails, the whole invocation aborts and the model
never sees the skill content. Injected commands never prompt.

## What problem of ours it addresses

`images:scripts/state.ps1:1-22` exists because "every stale-state incident in this repo has come
from a human or an agent typing SHAs and PR numbers by hand". `images:FLOW.md:174-193` makes running
it the first action of a session. That is a rule the agent has to remember to follow. Core's parking rule
(`core:AGENTS.md`, "The parking rule") asks for state printed last. **Core has no `state.ps1`.** The
brief assumed it did, and it was measured absent.

## What it would replace or strengthen

A `/state` skill whose body is `` !`pwsh -NoProfile -File ${CLAUDE_PROJECT_DIR}/scripts/state.ps1` ``
puts measured state into context when the skill is invoked, instead of relying on the agent to go
and run it. The fail-closed injection rule helps here: if `state.ps1` fails, the skill produces no
state at all rather than a stale one.

## Acceptance test

1. In an images clone, invoke `/state`. Measure that the injected block equals a direct
   `pwsh -NoProfile -File scripts/state.ps1` run at the same commit, byte for byte after
   normalising line endings.
2. Rename `scripts/state.ps1` and invoke `/state`. Measure that the invocation aborts and no state
   block reaches the model.
3. `cd` into a subdirectory in the session, then invoke. The output must be the same as in 1.

## Risks

- `state.ps1` guards on the repository name, and whether it refuses in the current images clone was
  not measured (`core:docs/analysis/verification-inventory.md:103`, read-only). Test 1 settles it.
- Porting this to core needs a `state.ps1` there first. That is a separate decision.
- An injected command that asks for permission aborts outside auto mode
  (skills.md § "Permission checks on injected commands"). The skill needs a matching allow rule or
  `allowed-tools` entry. See [`skill-bundled-scripts.md`](skill-bundled-scripts.md).
