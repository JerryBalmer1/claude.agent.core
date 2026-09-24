# Opportunities

Claude Code features that these repositories could use. There is one file per feature. **None of
them is implemented.** Each file says what the feature does, with citations to the pinned pages in
[`../manifest.json`](../manifest.json). It also points at the real file or finding in core, images,
tools or interrogator that the feature would serve, gives a measurable acceptance test, and lists
the risks. `tests/PlatformDocs.Tests.ps1` fails if a file has no acceptance test, cites an unpinned
URL, or is missing from this table.

| Slug | Feature | Repo | Status |
|---|---|---|---|
| [configchange-guard](configchange-guard.md) | `ConfigChange` hook and `Edit` deny rules guarding `.claude/settings.json` and `.claude/hooks/` | images | proposed |
| [stop-suite-clean](stop-suite-clean.md) | `Stop` hook running `Assert-SuiteClean`, so the turn cannot end red (clause (b)) | images | proposed |
| [taskcompleted-receipt](taskcompleted-receipt.md) | `TaskCompleted` hook: no task is done without a receipt | core | proposed |
| [skill-invocation-leash](skill-invocation-leash.md) | `disable-model-invocation: true` on promote, commit and push skills | images, core | proposed |
| [state-skill](state-skill.md) | `/state` skill with `shell: powershell` and `` !`state.ps1` `` injection | images | proposed |
| [skill-bundled-scripts](skill-bundled-scripts.md) | `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/x.ps1 *)`, and the workspace-trust hole | images | proposed |
| [heredoc-deny-rule](heredoc-deny-rule.md) | `Bash(*<<*)` deny rule as the hard control; the hook as reporter | images | proposed, pending measurement |
| [instructionsloaded-receipt](instructionsloaded-receipt.md) | `InstructionsLoaded` receipt for which instructions loaded, and the AGENTS.md blind spot | core, images | proposed |
| [plugin-eval-ci](plugin-eval-ci.md) | `claude plugin eval --threshold` beside the compliance runner | tools, images | proposed |
| [hook-stdout-json](hook-stdout-json.md) | Hook stdout JSON rule, an output-side site of the array-unroll recurrence class | images | proposed |
| [additionalcontext-factual](additionalcontext-factual.md) | `additionalContext`: factual statements, 10,000-character cap | images, core | proposed |
| [dockerfile-path-rules](dockerfile-path-rules.md) | `.claude/rules/*.md` with `paths:` for images' Dockerfile rules | images | proposed |
| [setup-init-only](setup-init-only.md) | `--init-only` and `Setup` hooks for one-time prep | images | proposed, low priority |
| [arena-agent-teams](arena-agent-teams.md) | Agent teams, cross-session messaging, MCP-scoped reviewers: the arena | interrogator | proposed |
| [precompact-receipt](precompact-receipt.md) | `PreCompact`/`PostCompact` receipt before context is summarised | core | proposed |
| [config-live-probe](config-live-probe.md) | `claude doctor` plus a `-p` canary: is the config actually live? | images | proposed |
| [sentinel-timeout](sentinel-timeout.md) | The sentinel's timeout fails open, and SDK callback hooks do not | images | proposed |
| [refusal-record-stream](refusal-record-stream.md) | `permission_denied` events as an independent source for B18 refusal records | core | proposed |

The last three are beyond the seed list. Each one was added because a pinned page speaks directly
to a record in these repositories:

- **config-live-probe.** The settings page contradicts `images:END_GOAL.md:182-187` on whether a
  `.claude/` folder created mid-session arms.
- **sentinel-timeout.** The hooks page confirms the standing blocker "command-hook timeout fails
  open" and names the hook family that does not fail open.
- **refusal-record-stream.** Headless mode emits a denial list that could supply BACKLOG B18
  refusal records from a count rather than from an agent's own report.
