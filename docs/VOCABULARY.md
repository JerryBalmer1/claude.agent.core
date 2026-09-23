# VOCABULARY — claude.agent.core

The root of the ontology. Every term below is used in a specific sense in this repository, and
several of them are words an outside framework also uses for something adjacent but not
identical.

**Where a mapping to an outside vocabulary is approximate, it says approximate and it says where
it breaks.** An equivalence claimed and not held is worse than no mapping at all: it invites a
reader to import guarantees this repository does not make. The three that get asked about most —
receipt against SLSA attestation, control against a NIST control, guard against a fitness
function — are all approximate, and each entry names the seam.

One term per entry. Where a term is enforced, the entry points at
[`docs/DECISIONS.md`](DECISIONS.md) rather than restating the enforcement.

---

## receipt

A record of one thing an agent did, written to an append-only hash-chained file. Eight keys,
frozen; `self` is the sha256 of the record's own canonical payload and `prev` is the previous
record's `self`, which is what makes a forgery break at the next link rather than at its own.

This repository has **two** chains and they are deliberately separate: the ledger chain
(`.ledger/ledger.jsonl`, schema v1, keys `ts, attempt, validator, mode, model, sha256, prev,
self`) and the forensic chain (`.continuity/forensic.jsonl`, schema forensic-v1, keys `ts, seq,
actor, kind, subject, evidence, prev, self`). Both are frozen — see **D003**. A continuity entry
is not a receipt and is never forced into the receipt schema.

*Outside use, approximate.* An **SLSA attestation** is also a signed statement about how an
artifact came to be. It breaks in two places. An attestation is **signed** by a key, which makes
it evidence to a third party who trusts that key; a receipt here is `actor`-asserted with no
signature at all, so it is a place to be caught lying rather than proof (**anchor** below is what
carries it outside). And SLSA attests to a **build**, a thing with inputs and an output, whereas
a receipt here attests to an **action** that may produce nothing at all.

## ledger

Two things, and the collision is real. (1) The chain of receipts at `.ledger/ledger.jsonl`.
(2) The PowerShell module at `modules/ledger/` that writes and verifies it, plus the Python
compute engine at `modules/ledger/python/` that produces the things it records.

*Outside use.* Nothing to do with a financial ledger, a distributed ledger or a blockchain. There
is no consensus, no network, no second party, and a single writer with file access can rewrite
the whole file and recompute every hash. See **chain** for exactly what that costs.

## chain

The hash-linking of records: each record's `prev` holds the previous record's `self`, and `prev`
lives **inside** the hashed payload. Editing one record in the middle therefore invalidates every
record after it, not just the edited one.

**Tamper-evident, not tamper-proof.** Anyone with write access can rewrite the entire file and
recompute every hash. What a chain buys is that a **partial** edit is detectable and that a
**full** rewrite changes the tip. The tip is worth exactly what its **anchor** is worth.

## gate

Two senses in this repository, both live, neither wrong.

1. **The enforcement gate.** The point a permitted action must pass through, applied *before* the
   action rather than reported after. `README.md:20`. In core this is the second of the two
   in-scope primitives; the enforcing implementations live in the image and hook repositories
   rather than here.
2. **The human gate.** `AGENTS.md:6-11` — the first line of every agent reply, written so a human
   can act on it without scrolling. A gate on the agent's output rather than on its actions.

Say which one is meant when it is not obvious from the sentence.

## sentinel

The observer that watches for calls which did not arrive through the gate, so that a bypass shows
up as a **disagreement between two records** rather than as a silent absence.

**It does not exist in this repository.** `src/` holds nothing but `.gitkeep`. The design lives in
`docs/IDEAS.md` (the single entry point entry) and a hook by that name ships in
`claude.agent.images`. Written here so the word is not read as describing something core has.

## provenance

A tamper-evident record of what an agent did, verifiable **without trusting the agent that
produced it**. One of the two things in scope for this repository (`README.md:17-18`).

Provenance answers *where a record came from*. It never answers *whether the record is true* —
`docs/IDEAS.md` records "trusted origin, false content" as its own adversarial case for exactly
this reason. The posture to aim at is trusted provenance, still-verified content.

## gating

The other in-scope primitive: enforcement of what an agent is permitted to do, applied before it
acts rather than reported after (`README.md:20-21`). Distinct from **judgment**, which asks
whether what happened satisfied a rule; gating asks whether it may happen at all, and asks it
first.

## judgment

Deciding whether recorded actions satisfy a **control**, a standard or a policy. **Explicitly out
of scope for v1** (`README.md:25-26`): this repository records and constrains; it does not
evaluate. `docs/IDEAS.md` names it as the whole distance between evidence and compliance, and
notes that no receipt here is mapped to a named control.

## coverage

Proof that the gate was **in the path** for every call — not that a policy exists, and not that
the records present are unaltered.

This is the unmet claim, stated as such in `docs/IDEAS.md` under "What we do not have yet". A
chain proves the records it holds were not edited. It says nothing about records never written.
Coverage is the property that would close that, and nothing here has it yet.

## attribution

Which actor did a given thing, held across a handoff. In this repository attribution is the `who:`
trailer on a commit and `actor` in a forensic record — both **operator-asserted, not signatures**
(`AGENTS.md:28-31`). `git blame` says "Jerry Balmer" because the commits carry his git identity;
the trailer is the only field in the object that says an agent did the work.

Out of scope for v1 in its larger sense (`README.md:28-29`), and `docs/IDEAS.md` records why:
this chain is single-actor by construction, and holding attribution across one agent calling
another has to start in the record format rather than be retrofitted.

## consequence

What happens when judgment fails: notification, rollback, merge blocking, sign-off, ownership.
Out of scope for v1 (`README.md:28-29`).

`docs/IDEAS.md` states the test: *"Until a receipt changes an outcome, it is a record rather than
a control."* Nothing here acts on a receipt.

## policy

Two senses, kept apart on purpose.

1. **The generated document.** `docs/POLICY.md`, rendered from `config/repo.json` by
   `scripts/Generate-Policy.ps1`, with the `generated-match-config` check failing the build if the
   two disagree. It is a *rendering* of config, never a source.
2. **A policy schema** in the sense of `docs/IDEAS.md`: a declarative artifact a non-engineer can
   read, diff and approve, versioned as evidence. That does **not** exist. Enforcement here is
   code plus config, not a policy language.

*Outside use.* Not OPA, not Rego, not a policy engine. There is no evaluation step and no decision
object.

## control

In the compliance sense: a named requirement that evidence can be mapped to. Used here mostly to
say the mapping is **missing** — the "Why" section of every pull request asks which control the
change serves, and `docs/IDEAS.md` records that no receipt is mapped to a named control.

*Outside use, approximate.* A **NIST control** (say AU-2, audit events) is a specific requirement
in a published catalogue, with a defined assessment procedure and an authorising body. Nothing
here is assessed against a catalogue, nothing is attested by an assessor, and "control" in this
repository carries no catalogue identifier. The word is borrowed for its shape — a requirement
evidence is judged against — and not for its authority. Treat the mapping as a direction of
travel, not a claim.

## finding

A measurement taken at a date, written down because it disagreed with what was expected or
because it would otherwise be lost. `docs/FINDINGS.md` holds this repository's own, F74 onward;
F1–F73 belong to the source repository and live in
`docs/plans/2026-09-22-substrate-cutover/FINDINGS.md` and are never renumbered.

Also one of the five `kind` values a forensic record may carry
(`scripts/forensic.ps1:79`). The governing rule is `AGENTS.md:73-78`: where a document states an
expected value and the measurement disagrees, **the measurement wins** and the difference becomes
a finding.

A finding records what was true when somebody looked. A **decision** records what is true now.

## decision

A rule that is currently true of this repository and that something enforces. Registered in
`docs/DECISIONS.md` with a stable `D` number that is never reused, and one of the five forensic
`kind` values (`scripts/forensic.ps1:79`).

A decision leaves the register only when its enforcement is removed, and the removal gets a
finding citing the D-number. Nothing speculative belongs there — that is what `docs/IDEAS.md` is
for.

## repair

A forensic `kind` (`scripts/forensic.ps1:79`): a record that something broken was fixed, written
by the party that fixed it. The repair is recorded whether or not anyone would otherwise have
noticed the break.

## verification

A forensic `kind` (`scripts/forensic.ps1:79`): a record that something was checked and found to
hold. Distinct from a **guard**, which does the checking mechanically on every run; a verification
record is the assertion that a check was performed at a moment, by somebody, against a stated
tree.

## confession

A forensic `kind` (`scripts/forensic.ps1:79`): a record of the agent's own error, written by the
agent that made it. Seq 10 of this repository's chain, `measure-object-line-undercount`, is one.

The word is chosen over "incident" or "issue" deliberately. A system whose error record is written
by the erring party needs the record to be uncomfortable to write, or it will be written blandly
or not at all.

## anchor

The tip of a chain, placed somewhere **no agent with write access can reach**. `scripts/forensic.ps1
-Anchor` prints one line — record count, git HEAD, tip hash — and that line is worth something only
once it exists outside the repository: screenshotted, pasted into a chat, quoted in a commit
message elsewhere.

Inside the repository the anchor is just a file, and a file the writer can rewrite. This is the
single sharpest edge in the whole design: the chain's value collapses to the anchor's
independence. `claude.agent.images` anchors `915be889…` inside the very repository it attests
(F82), which is a witness witnessing itself — recorded in `docs/PRE-PUBLIC.md` as unresolved.

## pin

A recorded expected value — a sha, a blob hash, a version, a commit — that something later
recomputes and compares. `modules/ledger/tests/fixtures/copied-blobs.psd1` pins ten copied blobs
by git blob sha; `.github/workflows/ci.yml:96` pins an action to a commit sha rather than a tag,
because a tag is a name its owner can repoint and a pinned toolchain that floats is not a pin.

**A pin is a claim with an expiry date attached to somebody else's behaviour.** Retiring one is a
decision (**D002**), not a cleanup: the absence of a pin is as much a statement as its presence.

## guard

A check that runs mechanically and goes red when a stated rule is broken —
`scripts/ci/Test-*.ps1`, the six required checks, `push-guard`, `trailer-guard`.

A guard is only worth its falsification test: a check that cannot go red reports identically to
one that passes.

*Outside use, approximate.* An architectural **fitness function** is also an automated,
continuously-run test of a structural property. It breaks on scope and on intent: a fitness
function measures a *characteristic* of an architecture, usually continuous and trending
(coupling, cycle time, response time), and is expected to be tuned as the architecture evolves. A
guard here is **binary and adversarial** — it exists to make one specific defect impossible to
land, it has a planted-defect test proving it can fail, and tuning it is a change to the law
rather than to a threshold.

## falsification test

A test whose job is to prove the guard can go **red**: plant the defect the guard exists to catch,
assert the guard fails, remove the defect, assert it passes.

`tests/Runtimes.Tests.ps1:103-109` is the canonical one — *"The planted defect. If this ever goes
green the check has stopped checking."* Without it, a guard that silently stopped checking is
indistinguishable from a repository that has nothing to catch. `docs/IDEAS.md` extends the point
to case counts: a test that cannot fail reports identically to a test that passes, and the only
observable that separates them is how many cases ran.

## birth commit

The one commit in this repository's life that is not a merge: a root commit with no parents,
carrying the working tree copied from `claude.agent.substrate@e40ba414` and none of its history
(F74). Everything after it arrives through `feature/* -> develop -> main` and is a merge.

Fidelity to the source is recorded **at the birth commit** and does not need re-asserting at every
HEAD — the reasoning behind **D002**. `push-guard` is red on the birth commit by design, because
it asserts two parents and a root commit has none; the red is left standing rather than
special-cased.

## preflight

`scripts/Invoke-Preflight.ps1` — run **before** starting work, it reports whether any open pull
request already touches the paths about to be edited. It answers one question: is somebody else
holding this file.

Its exit codes are the whole design. `0` means clear, `1` means an overlap was found, and **`2`
means no answer was obtained** — the `gh` call failed, or returned nothing, or returned something
that was not the JSON it asked for. Exit 2 is never to be read as "no overlap"; the script says so
in its own output.

## handoff

The recorded transfer of responsibility at a named boundary: the wrapper's call ended here, the
agent continued on its own from this point, for this stated reason.

A design term from `docs/IDEAS.md`, not yet built. The argument for it is that an escape hatch
which is *recorded* is strictly better than one which is denied and then routed around, in both
directions: off-wrapper work becomes visible, and the frequency of handoffs becomes a measurement
of whether the declared surface is wrong. The hatch must have its own declared cases or it becomes
the allow-all rule at the bottom of the table.

Distinct from the **parking rule** (`AGENTS.md:54-64`), which is the handoff between *sessions*:
clone on `develop`, clean, fast-forwarded, and the state printed verbatim as the last block of the
final message.

## window

The interval from a wrapped call's invocation to its return, during which the wrapper knows what
is supposed to be happening. Anything the agent does inside that window which did not arrive
through the wrapper is **anomalous by definition** rather than by judgement.

A design term from `docs/IDEAS.md`, not yet built, and the strongest part of that design: it turns
coverage from something reconstructed afterwards into a live disagreement between two records.
Nothing here decides whether an action was *reasonable* — only whether it fell inside a declared
window and arrived through a declared surface. Two mechanical facts, neither self-reported.
