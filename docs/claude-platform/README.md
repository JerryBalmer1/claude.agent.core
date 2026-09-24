# docs/claude-platform/

A repo-local, dated, hash-pinned reference for Claude Code's extension surface: hooks, skills,
subagents and parallelism, plugins, memory and context, permissions and sandboxing, settings, the
CLI, and the built-in commands. It exists so that a session working in these repositories (Claude
in chat, Claude Code, or any other model) reads this tree rather than guessing from training data
or searching the web.

## The rule

**While `scripts/Test-PlatformDocs.ps1` reports clean, this tree beats training and beats
searching.** When a summary here and a model's memory disagree, the summary wins. It was written
from the page on the date it states, and the script has just proven that the page has not changed
since then. Memory can prove neither.

**A stale manifest means refetch before trusting.** If the script exits 1, the pages it lists have
changed upstream. Every summary that cites one of those pages is stale until someone re-reads the
page and updates the summary. If the script exits 2, it could not reach the pages, so it has proven
nothing either way. Treat exit 2 as stale, not as clean.

```powershell
pwsh -NoProfile -File scripts/Test-PlatformDocs.ps1
```

| Exit | Meaning | What to do |
|---|---|---|
| 0 | Every URL in the manifest serves the bytes its hash was taken over | Trust the tree |
| 1 | At least one URL changed or is gone. The script lists each one | Refetch, re-read, update the summaries that cite it, then update the manifest |
| 2 | The manifest could not be read, or a URL could not be fetched at all | Nothing is proven. Fix the network or the manifest and run again |

CI does not run the real fetch. `tests/PlatformDocs.Tests.ps1` runs the script with the network
mocked, so the `pester` check stays hermetic. The same test file also checks that every summary
has front matter and that every URL a summary cites is pinned. Checking against the live docs is a
manual step, the "Full" step, and it is run from a workstation.

## Contents

| File | Covers |
|---|---|
| [`hooks.md`](hooks.md) | Hook events, matchers, handler types, exit codes, JSON output, trust, `disableAllHooks` |
| [`skills.md`](skills.md) | Skill front matter, invocation control, `allowed-tools`, injection, `context: fork`, lifecycle, authoring practice |
| [`agents-and-parallelism.md`](agents-and-parallelism.md) | Subagents, agent teams, workflows, cross-session messaging, worktrees |
| [`plugins.md`](plugins.md) | Plugin layout, manifest, marketplaces, `claude plugin validate`, `claude plugin eval` |
| [`memory-and-context.md`](memory-and-context.md) | CLAUDE.md and AGENTS.md, `.claude/rules/`, the `.claude/` directory, context window, compaction, prompt caching |
| [`permissions-and-sandbox.md`](permissions-and-sandbox.md) | Rule syntax and precedence, permission modes, sandboxing |
| [`settings.md`](settings.md) | Settings precedence, file locations, and every key that touches hooks, skills, plugins or permissions |
| [`cli-and-headless.md`](cli-and-headless.md) | `-p`, `--init-only`, bare mode, the tools reference, the PowerShell tool, environment variables |
| [`commands-and-debugging.md`](commands-and-debugging.md) | Built-in slash commands, debugging a configuration, error reference |
| [`opportunities/`](opportunities/INDEX.md) | Proposals for features these repositories could use, one file each, none of them implemented |
| [`manifest.json`](manifest.json) | Every fetched URL, with its SHA-256, byte count and fetch date |

## How a summary is written

- Every summary starts with front matter that has three keys. `verified:` is the date the sources
  were read. `sources:` lists every URL the file relies on. `scope:` states what the file covers.
- The body is written in our own words, not copied from the source. Field names, flags, event
  names and short phrases whose exact wording matters are quoted as they appear.
- Every `##` and `###` section starts with a `Source:` line. It names the page, and the heading
  inside that page, that the section was written from.
- **A claim nobody can cite does not get written.** If something expected is missing from the
  source, it goes in a closing `## Not found in source` section and is not filled in from memory.
- Every URL cited anywhere in the tree is in `manifest.json`. `tests/PlatformDocs.Tests.ps1` fails
  if one is not.

## Where the pages come from

The index is `https://code.claude.com/docs/llms.txt`. Every page it lists is also served as raw
markdown at `https://code.claude.com/docs/en/<page>.md`. Only those raw `.md` URLs are fetched,
never the HTML pages, and each one is hashed over the raw response bytes. The one page from another
host is the Agent Skills best-practices page, fetched as raw markdown from `platform.claude.com`.
`llms.txt` is not linked from that index. `llms.txt` is pinned as well. When it drifts, it usually
means a page was added or renamed, and that is worth knowing even when no pinned page has changed.

## Refreshing

This refresh procedure is deliberate. The script only reports and never rewrites anything.

1. Run the script and note the URLs that drifted.
2. Fetch each one with `Invoke-WebRequest -UseBasicParsing` and keep the raw bytes.
3. Diff the new page against what the summary says, and update the summary. Bump its
   `verified:` date only when its content has been re-read.
4. Update that URL's `sha256`, `bytes` and `fetched` in `manifest.json`.
5. Run the script again. It must report clean before the change is committed.
