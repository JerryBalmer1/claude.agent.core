# disable-model-invocation on promote, commit and push skills

| | |
|---|---|
| Feature | Skill front matter `disable-model-invocation: true` |
| Repo | images, core |
| Status | proposed |

## What the feature does

Source: https://code.claude.com/docs/en/skills.md § "Control who invokes a skill"; https://code.claude.com/docs/en/skills.md § "Frontmatter reference"

With `disable-model-invocation: true`, a skill's description is taken out of the model's context
and only the user can invoke it. If the model calls the skill anyway, Claude Code blocks the call
and tells the model not to reproduce the steps some other way. The same flag also stops the skill
from being preloaded into subagents and, from v2.1.196, from running as a scheduled task's prompt.
`Skill(name)` deny rules and `skillOverrides` can govern skills from settings without editing them
(skills.md § "Restrict Claude's skill access").

## What problem of ours it addresses

The irreversible steps in these repos are run by hand from pasted templates today. Examples:
`images:AFTER-CLAUDE-COMMITS.md:37-86` (Template A, "push + open PR"), the promotion path in the
definition of done (`images:README.md:62-75`), and `images:scripts/snake.ps1 -Archive -Go -Pr <n>`
(`images:docs/plans/BACKLOG.md:61-65`). The rules around them are prose: "Do not commit unless
told. Do not push." BACKLOG B8 (`core:docs/BACKLOG.md:20`) records that the GitHub merge button
writes no `who:` trailer. **No `.claude/skills/` directory exists in any of the four repos**, so
none of this is packaged as a skill yet.

## What it would replace or strengthen

Packaging promote, commit and push as user-only skills turns "do not push unless told" from prose
into a block the platform enforces. Combined with a deny rule on the raw commands, the skill becomes
the only path.

## Acceptance test

Create `.claude/skills/push/SKILL.md` with `disable-model-invocation: true` in an images clone, then:

1. In a session, ask Claude to push. Measure that the `Skill` call is blocked and that no
   `git push` appears in the tool log for the rest of the turn.
2. Type `/push` as the user. Measure that it runs.
3. Measure that the skill's description is absent from the session's `/context` skill listing.

Pass means 1 and 3 hold with no push, and 2 pushes.

## Risks

- The skill block does not stop Claude from running `git push` directly. The skill has to be
  paired with a deny rule on the raw command, and a Bash deny rule is not a security boundary
  (see [`heredoc-deny-rule.md`](heredoc-deny-rule.md)).
- The exact text Claude Code sends the model when it blocks the call is not in the pinned source
  (see [`../skills.md`](../skills.md)), so this test measures the behaviour, not the message.
