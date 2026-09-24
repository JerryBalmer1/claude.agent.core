# --init-only and the Setup event for one-time runner prep

| | |
|---|---|
| Feature | `claude --init-only`, `-p --init`, `Setup` hooks |
| Repo | images |
| Status | proposed, low priority |

## What the feature does

Source: https://code.claude.com/docs/en/cli-reference.md § "CLI flags"; https://code.claude.com/docs/en/hooks.md § "Setup"; https://code.claude.com/docs/en/env-vars.md § "Variables"

`claude --init-only` runs Setup and SessionStart hooks and exits without starting a conversation.
`-p --init` and `-p --maintenance` run Setup hooks with the `init` or `maintenance` matcher before
the session. Setup hooks cannot block, since exit code, stderr and JSON are ignored. Only `command`
and `mcp_tool` handlers are supported. A Setup hook can write `CLAUDE_ENV_FILE` so that later Bash
commands inherit variables. `CLAUDE_CODE_PLUGIN_SEED_DIR` points at a read-only, pre-populated
plugin directory for images.

## What problem of ours it addresses

Runner prep today is PowerShell run by CI, not by Claude Code. Pester is installed at a pinned
version (`core:scripts/ci/Invoke-Tests.ps1:54-66`, `images:scripts/ci/Invoke-Tests.ps1:47-59`).
InvokeBuild is installed at a pin (`images:scripts/ci/Invoke-InContainer.ps1:47-49`). And there is a
local `Bootstrap` task (`images:build/tasks/Core.build.ps1:18-68`). **No workflow in core or images
runs Claude Code at all**, so on CI runners there is nothing for a Setup hook to prepare.

The one place Claude Code does start in our tree is the leash image, and that is where this fits.
The image's entrypoint could run `claude --init-only` at build time to warm plugins and settings, so
the first real session starts from a known state.

## What it would replace or strengthen

It could replace ad-hoc warm-up in the image entrypoint. It replaces nothing in CI.

## Acceptance test

1. In the leash image, run `claude --init-only` with a Setup hook that writes a marker file and a
   `CLAUDE_ENV_FILE` line. Measure exit 0, the marker present, and no conversation started (no
   session transcript created).
2. Start a real session afterwards. Measure that the variable is visible to a Bash command.
3. Measure the wall clock of the first session with and without the warm-up.

## Risks

- The Setup payload and exit code of `--init-only` are not in the pinned source
  (see [`../cli-and-headless.md`](../cli-and-headless.md), "Not found in source"). Test 1 measures
  them.
- Low value until Claude Code runs somewhere automated. Listed because the brief seeded it, and
  ranked last.
