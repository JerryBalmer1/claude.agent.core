# Path-scoped rules for images' Dockerfiles

| | |
|---|---|
| Feature | `.claude/rules/*.md` with `paths:` front matter |
| Repo | images |
| Status | proposed |

## What the feature does

Source: https://code.claude.com/docs/en/memory.md § "Path-specific rules"; https://code.claude.com/docs/en/context-window.md § "What survives compaction"

A rule file in `.claude/rules/` with a `paths:` list loads only when Claude reads a file that
matches one of the globs. `paths` is the only front matter field read. If the YAML does not parse,
the rule loads for every file, silently, and `claude --debug` shows the error. A glob that cannot be
read matches nothing. Path-scoped rules are dropped at compaction and come back only when a
matching file is read again. The source shows extension and directory globs only. It gives no
example for a file with no extension, such as `Dockerfile`.

## What problem of ours it addresses

The Dockerfile rules in images are scattered comments, not law:

- pin by digest and keep the pins identical to the developer image (`images:Dockerfile:1-13`);
- install Claude Code under `/opt/claude-code` (`:60-67`);
- managed settings are mode 0555 (`:82-84`);
- never `ENV GITHUB_TOKEN=` (`images:docs/skills/secret-hygiene.md:81`);
- never call `docker build` directly, only `Invoke-Build` (`images:AGENTS.md:108`).

`images:AGENTS.md` has no Dockerfile section. And the fast CI gate does not build the image
(`images:scripts/ci/Invoke-Tests.ps1:62-68`, FINDING-M13), so a pull request that breaks the
Dockerfile goes green there.

## What it would replace or strengthen

A `.claude/rules/dockerfiles.md` with `paths: ["**/Dockerfile", "images/**/Dockerfile"]` collects
those rules and loads them exactly when a Dockerfile is opened. That keeps them out of every other
session's context. It strengthens the comments and does not replace `images:tests/Image.Tests.ps1:38-67`,
which is the check that holds.

## Acceptance test

With `InstructionsLoaded` logging on (see [`instructionsloaded-receipt.md`](instructionsloaded-receipt.md)):

1. Read `Dockerfile`. Measure a load line for `dockerfiles.md` with `trigger_file_path` equal to
   the Dockerfile. This settles whether an extensionless glob matches, which the source does not.
2. Read `README.md` only. Measure no load line.
3. Break the YAML on purpose. Measure that `claude --debug` reports it and that the rule then loads
   for `README.md`, which is the documented silent fallback.

## Risks

- The rules load on **read**, not on write. Whether an Edit of an unread Dockerfile triggers them
  is not stated (see [`../memory-and-context.md`](../memory-and-context.md), "Not found in source").
- A rule that must survive compaction should not be path-scoped. These rules are advisory context,
  and the tests stay the gate.
