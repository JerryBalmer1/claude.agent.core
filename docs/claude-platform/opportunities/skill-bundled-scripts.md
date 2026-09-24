# allowed-tools for bundled scripts, and the trust hole it opens

| | |
|---|---|
| Feature | Skill `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/x.ps1 *)` |
| Repo | images; finding candidate for the compliance runner (tools, empty today) |
| Status | proposed |

## What the feature does

Source: https://code.claude.com/docs/en/skills.md § "Pre-approve tools for a skill"; https://code.claude.com/docs/en/skills.md § "Available string substitutions"; https://code.claude.com/docs/en/skills.md § "Permission checks on injected commands"

`allowed-tools` pre-approves the listed tools while the skill is active, so they run without a
prompt. It restricts nothing: every other tool stays callable. The grant clears on the next user
message. `${CLAUDE_SKILL_DIR}` and `${CLAUDE_PROJECT_DIR}` are substituted inside `allowed-tools`
rules, so one bundled script can be approved by exact path. Deny and ask rules still override the
grant. **Workspace trust does not gate it.** A checked-in project skill's grant applies even under
`-p` in a folder that was never trusted. The source says to review the `allowed-tools` of checked-in
skills before running Claude Code in a repository.

## What problem of ours it addresses

Two concrete uses. `state-skill.md` needs `state.ps1` to run without a prompt. Any skill that wraps
`images:scripts/snake.ps1` would need the same. The images session already registers a PowerShell
command hook the same way (`images:.claude/settings.json:4-19`).

The hole is the second point. Anyone who can land a `SKILL.md` in the repository can pre-approve
commands for every later `-p` run. The images leash is safe because `images:managed-settings.json:6-11`
denies `Bash` and `Shell(*)`, and deny wins. A developer session has no such floor.

## What it would replace or strengthen

It replaces a blanket `Bash(pwsh *)` allow, which `images:END_GOAL.md:569-573` records as defeating
the sentinel. The replacement is one exact script path per skill.

## Acceptance test

1. With a skill granting `Bash(${CLAUDE_SKILL_DIR}/scripts/probe.ps1 *)`, invoke it and measure no
   prompt for `probe.ps1`. Measure that a prompt, or a deny, still appears for `pwsh -c "echo hi"`.
2. Run the same repository under `claude -p` in a never-trusted folder. Measure that the grant still
   applies. That confirms the hole on our version.
3. Add a deny rule matching `probe.ps1`. Measure that it wins over the grant.
4. Record test 2's result as a finding for the compliance runner: "a checked-in `allowed-tools`
   grant applies without workspace trust".

## Risks

- The compliance runner does not exist yet. It is assigned to `claude.agent.tools`, which has no
  commits (measured), so the finding has nowhere to land except core's `docs/FINDINGS.md`.
- Grants are per turn and clear on the next user message, so a test that spans turns will see the
  prompt come back. That is correct behaviour, not a failure.
