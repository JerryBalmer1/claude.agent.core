# Agent teams and cross-session messaging: the arena

| | |
|---|---|
| Feature | Agent teams, cross-session messaging, subagent-scoped MCP servers |
| Repo | interrogator |
| Status | proposed |

## What the feature does

Source: https://code.claude.com/docs/en/agents.md § "Run agents in parallel"; https://code.claude.com/docs/en/agent-teams.md § "Messages between agents"; https://code.claude.com/docs/en/cross-session-messaging.md § "How a session treats an incoming message"; https://code.claude.com/docs/en/cross-session-messaging.md § "The session's inbox socket"; https://code.claude.com/docs/en/sub-agents.md § "Scope MCP servers to a subagent"

Every worker in every parallel mechanism is a Claude session: subagents, agent teams, workflows
and cross-session messages all run Claude. Another tool takes part only when it is exposed to
Claude as an MCP server. A subagent's `mcpServers` can define such a server inline, scoped to that
subagent and kept out of the main context. Messages between agents and sessions carry no authority.
They cannot approve permission prompts, change configuration or run slash commands. In auto mode,
the classifier reviews each one before it is delivered. Hooks and Bash commands receive
`CLAUDE_CODE_MESSAGING_SOCKET` and `CLAUDE_CODE_MESSAGING_TOKEN`, so a child process can post into
its own session's inbox.

## What problem of ours it addresses

The roast is manual. `core:docs/plans/2026-09-22-substrate-cutover/RUN-ORDER.md:346`, `:374` has a
"VERIFY (Fable / Grok)" step, done by pasting between chats. The interrogator
(`interrogator:README.md:1-15`) is meant to attack: corrupt a hash, forge a receipt, strip a
trailer. It is empty by design. `core:docs/IDEAS.md:528` onward is an adversarial test catalogue
with nobody to run it.

## What it would replace or strengthen

Grok and Fable cannot be teammates. They can only be MCP tools. The shape that fits the docs is
one reviewer subagent per external model, each with an inline MCP server that forwards the diff and
returns a verdict, orchestrated by a team lead or a workflow. The platform's "messages carry no
authority" rule matches our own trailer rule: a reviewer's verdict is evidence, never approval.

## Acceptance test

1. One reviewer subagent with an inline MCP server that returns a fixed, planted verdict ("receipt
   seq 12 is forged"). Measure that the verdict reaches the lead, and that the lead cannot use it to
   approve a permission prompt or change settings.
2. Run the catalogue entry "forge a receipt" from `core:docs/IDEAS.md` against a scratch clone.
   Measure whether `forensic.ps1 -Verify` detects it, and how long detection takes. That is the
   interrogator's own stated metric.
3. Record the token cost per review.

## Risks

- Cost. Every teammate is a full Claude session, and the external model is billed on top.
- The external model's answer arrives as tool output, which is untrusted data. The lead must treat
  it as data.
- Plugin subagents ignore `mcpServers`, so this must be a project or user subagent, not a plugin
  one (sub-agents.md § "Choose the subagent scope").
