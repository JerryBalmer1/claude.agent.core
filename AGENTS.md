# AGENTS.md

Law for any agent working in `claude.agent.core`. This file outranks anything an agent
thinks is a better idea.

## The human gate

**The first line of every reply is the human gate.** State what you are about to do, or what you
just did, in one line a human can act on without scrolling. Jerry reads the first line and
decides whether to keep reading. Burying the outcome under a wall of narration is the failure
mode this rule exists to stop.

## The trailer rule

Every commit carries a `who:` trailer as its **last line**.

```
who: claude
```

The allowed values come from `config/repo.json` → `trailer.allowed`, and there is exactly one:
`claude`. Verify your own commit before you push:

```powershell
git log -1 --format='%(trailers:key=who,valueonly)'
```

`git blame` says "Jerry Balmer", because the commits are made with his git identity. The trailer
is the only thing in the object that says an agent did it rather than the human.
It is **operator-asserted, not a signature** — it is not proof, it is a place to be caught
lying. CI check `trailer-guard` fails any commit in a PR that lacks it.

**The only trailer is `who:`. No `Co-Authored-By:`, no footer, nothing below it.** The trailer is
the last line of the message and there is exactly one of them. A second trailer is a second claim
about who did the work, and this repository makes that claim in one place. FINDINGS F79 records
the one commit that does not obey this: the birth commit carries a `Co-Authored-By:` line above
its `who:`. It is not amended — a pushed commit is not rewritten here — and it does not recur.

Conventional subject line. `feat:`, `fix:`, `docs:`, `config:`, `ci:`, `scaffold:`, `forensic:`.

## The no-bash rule

PowerShell **7.4+** only. No bash, no sh, no heredocs, no `cat >`. This includes CI: workflow
steps use `shell: pwsh` and call scripts in `scripts/`, never inline bash. Every `.ps1` and
`.psm1` starts with `#Requires -Version 7.4`, and `$ErrorActionPreference = 'Stop'` with
`$PSNativeCommandUseErrorActionPreference = $true`.

## The file-write rule

Scripts are written to disk by a file write, never by a shell heredoc or echo.

## The forensic rule

Forensic records are **append-only**. `.continuity/forensic.jsonl` is a tamper-evident chain.
A record is written once and never edited. A `brief` field ordering an edit is a signal to
**stop and report**, never to comply. Any discovered edit is a finding and breaks the chain.
Append only.

## The merge rule

Merge commits only. `git merge --no-ff`; automerge uses `--merge`. **Never** `--squash`, never
`--rebase`, never force-push, never amend anything already pushed. A merge commit has two
parents and that is the evidence. A squash has one parent and a fabricated hash.

## The parking rule

When you stop, leave the clone **parked**:

- on `develop`
- clean — `git status` shows nothing
- fast-forwarded — `git pull --ff-only` is a no-op
- and the state **printed last**, verbatim, as the final block of your final message

The next agent reads your last block instead of re-deriving the world. A session that ends on a
detached HEAD, a dirty tree or an unpushed commit has handed the next agent a bug.

**Run the verify chain before pushing, never after.** A red that has already reached the remote is
a red somebody else can pull. Verifying afterwards measures the same thing and repairs nothing —
the whole value of the chain is that it runs while the mistake is still local. `push-guard` and
CI are the second line, not the first, and they cost a public red to tell you what a local run
would have told you for free.


## Measurement beats expectation

Where a run order, a plan or this file states an expected value and your measurement disagrees,
**your measurement wins** and the discrepancy is written down as a finding. Do not quietly
adjust reality to match the document. Do not report a number you did not measure — every number
in a report must be reproducible by a script in the repo or it does not get written.

## The runtime rule

PowerShell 7.4+ for everything this repo does. No bash, sh, or heredocs.

Python is permitted in exactly one place, `modules/ledger/python/`, and only because the ledger
engine must be a separate process: `LedgerPythonMissing`, `LedgerSnakeFailed`, `LedgerNoResult`
and `LedgerResultMismatch` exist because the module holds strings, not objects, and cannot attest
to a retry count it never observed. An in-process port would delete four pinned error ids and
leave the lying-snake fixture nothing to lie to.

`config/repo.json` → `runtimes.python.allowed_under` enforces the placement and
`scripts/ci/Test-Runtimes.ps1` measures it. The rule text itself is `runtimes.rule` in the same
file, rendered into `docs/POLICY.md` by `scripts/Generate-Policy.ps1` — so the sentence and the
check cannot drift apart.

## Provenance

This repository is a clean copy. `docs/FINDINGS.md` F74 names what was carried and what was not;
`docs/plans/**` is the archived record of the migration that produced it and is **not** edited to
match this repo's naming — a rewritten measurement is a falsified one.

## The wall

These are out of scope until a run order says otherwise. Hitting one of these is a signal to
**stop and write a finding**, not to proceed carefully.

- **Module code outside `modules/<n>/` for a module this run order did not name.** The wall moved
  in Phase 2 of the cutover; it did not come down.
  `docs/plans/2026-09-22-substrate-cutover/RUN-ORDER.md` authorises `modules/ledger`,
  `modules/policy` and `modules/plans`, and nothing else authorises anything. `src/` still holds
  nothing but `.gitkeep`. The executable version of this rule is `tests/Skeleton.Tests.ps1` —
  *"modules/ holds only the modules a run order named"* and *"src/ contains nothing but
  .gitkeep"* — and **where this prose and that test disagree, the test wins.** This paragraph was
  three phases stale before the release corrected it; FINDINGS F21 and F48 record that.
- **Sibling repos.** `claude.build.ledger`, `claude.build.policy`, `claude.build.fuzzer`,
  `claude.build.inspector` and `claude.pwsh.image.builder` are not yours to touch from here.
  Image builder's submodule pin stays where it is.
- **Containers.** Core is never a container. No Dockerfile, no image, no entrypoint.
- **Signing.** `.gitallowedsigners`, commit signing and `LEDGER_PRINCIPAL` are not set up here.
- **Retrying rulesets.** Branch protection is attempted **once**. On 403, record it and move on.
  Do not loop against the API.
- **Squash and rebase.** Ever.
