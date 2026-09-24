# claude plugin eval with a CI threshold, next to the compliance runner

| | |
|---|---|
| Feature | `claude plugin eval --threshold` |
| Repo | tools (empty today), images |
| Status | proposed |

## What the feature does

Source: https://code.claude.com/docs/en/plugin-evals.md § "Run evals in CI"; https://code.claude.com/docs/en/plugin-evals.md § "Grader types"; https://code.claude.com/docs/en/plugin-evals.md § "How runs are isolated"; https://code.claude.com/docs/en/plugin-evals.md § "Grant tools"; https://code.claude.com/docs/en/plugin-evals.md § "Choose and weight graders"

`claude plugin eval` runs the cases in a plugin's eval suite, with and without the plugin, and
grades the results. `--threshold` defaults to 1.0, and any case below it makes the run exit 1. Exit
2 means a partial run. `--json` writes a versioned report. Graders include `tool_used` (with
`min`/`max`, so "never called" is expressible), `tool_order`, and `regex` with `not_contains` over
the last message, the trace, or file contents. There are no custom-code graders. Runs are isolated:
user settings, hooks, CLAUDE.md, the project's `.claude/` and other plugins do not load, and managed
settings do. Tools that were not granted are removed entirely, not prompted for.

## What problem of ours it addresses

The compliance runner, a harness that checks whether an agent obeyed its rules, exists only as a
concept. The concept lives in `claude.agent.docs` (for example `tools/role.md:16`), outside the four
repos this tree serves, and is assigned to `claude.agent.tools`, which has no commits (measured).
Our rules are not yet packaged as skills (see [`skill-invocation-leash.md`](skill-invocation-leash.md)).

## Where it overlaps the compliance runner, and where it does not

| Question | plugin eval | compliance runner |
|---|---|---|
| Did the agent avoid a forbidden tool? | yes, `tool_used` max 0 | yes |
| Did X happen before Y? | yes, `tool_order` | yes |
| Non-zero exit for CI? | yes, `--threshold` | intended |
| Does the agent obey **this repo's** AGENTS.md and settings? | **no**, project config is isolated out unless it ships inside the plugin | the whole point |
| Can it see an attempt that was denied? | **no**, ungranted tools are removed, not denied | should |
| Checks written in PowerShell? | **no**, no custom-code graders | yes |
| With/without comparison | built in | not designed |

## Acceptance test

1. Package one rule as a plugin skill, for example "PowerShell only, no heredoc". Write three eval
   cases whose `regex` grader asserts `<<` is absent from the trace.
2. Run `claude plugin eval --threshold 1.0 --json` twice. Measure the exit code and
   `aggregates.casesPassed` on both runs, and measure the with/without difference.
3. Record in this file which rows of the table above were confirmed by the run, and which were not.

## Risks

- Cost. Every case is a model run, and `llm`/`baseline` graders are model-judged.
- Usage-limit errors mid-suite do not set `partial`, so later cases score near zero and look like
  regressions (plugin-evals.md § "Runs fail with a usage-limit or rate-limit error partway through").
- A passing suite says nothing about plugin safety (plugin-evals.md § "What a run can access").
