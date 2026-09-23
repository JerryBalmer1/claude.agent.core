# ANALYSIS — manifest

Five files. Four were written as one set on 2026-09-22; the fifth,
[`suppressed-outputs.md`](suppressed-outputs.md), was added on 2026-09-23 and carries a correction
to one of the four. They are analysis rather than record: nothing here
is a measurement of this repository, nothing here is enforced by anything, and nothing here is a
commitment. Measurements are findings and live in [`../FINDINGS.md`](../FINDINGS.md); rules with
teeth live in [`../DECISIONS.md`](../DECISIONS.md); unscheduled ideas live in
[`../IDEAS.md`](../IDEAS.md). This directory sits beside all three and claims none of their
authority.

**Two conventions hold across the set.** Every external claim carries its source inline, in the
sentence that makes the claim rather than in a footnote or a bibliography. And every sentence
that is our own reasoning rather than a cited claim is marked `[analysis]`, so a reader can tell
the two apart without checking. Forensic receipt **seq 13**, subject
`analysis-set-landscape-gaps-refusal`, records the first four; **seq 15**, subject
`suppressed-outputs-and-cost-correction`, records the fifth and the correction it makes.

---

## [`landscape.md`](landscape.md) — what is already occupied

Holds four positions this repository takes that somebody else already holds, each with its
source: enforcement-over-prompting as an established and funded category, fitness functions as
the published practice `docs/DECISIONS.md` applies to an agent, TEE-backed proof-of-guardrail as
a better-funded answer to the anchor problem, and the in-process coverage limit stated from
outside in the same terms `docs/IDEAS.md` uses from inside. It answers one question: **which of
our positions are shared, and with whom?** It deliberately does not cover what is unoccupied —
that is the next file — and it makes no market claim, no competitive assessment and no judgement
about the quality of any cited work. Read it before `gaps.md`: a gap claimed without it is a gap
in the author's reading.

## [`gaps.md`](gaps.md) — what is not occupied

Holds three bands. Adoption context at the top, cited and unglossed, against which the project's
scope is stated as governance and observability only. Measured gaps in the middle, including the
limit of this repository's own mechanism and the policy-version field the frozen forensic record
shape has no room for. The position at the bottom: existing comparisons move two variables at
once, and the unoccupied one is the same task expressed once as prose and once as an enforced
function, with the difference measured — carried together with the ablation ladder as protocol,
the falsification condition, the bypass-mode honesty problem, cost of proof, and the Azure DevOps
portability seam. It answers: **what is left, and what would it take to claim it?** It does not
cover data readiness, integration or change management, it takes no position on leadership, and
it does not cross the portability seam it names.

**This file is bottom-heavy on purpose — most important at the bottom, weight-bearing claim
last — and it says so in its own first line.** A future reader who reorders it into descending
importance will have moved the context a reader needs *before* the position underneath the
position itself, and the file will still read fluently while having lost its argument. Leave the
order alone.

## [`refusal.md`](refusal.md) — the record nobody keeps

Holds the case that a refusal is a record with structure rather than an event: who refused, what
was asked, which rule bound, that rule's version at that moment, and what happened next — with
the aftermath field argued as the one everyone skips and the one worth the most. Carries the
rephrase count as the single integer separating a wall from a turnstile, the argument that
refusal has to be cheap or honest behaviour is selected out, the metrics that lie, and the
liability surface of writing refusals down at all. It answers: **what has to be in the record
for a refusal to be worth keeping?** It deliberately does not cover whether any given refusal was
*correct* — that is **judgment** in [`../VOCABULARY.md`](../VOCABULARY.md)'s sense and out of
scope for v1 — and it proposes no schema change, because the forensic record shape is frozen by
**D003**.

## [`failure-envelope.md`](failure-envelope.md) — a refusal is an object, not an ending

Holds the mechanical companion to `refusal.md`: the refusal as a typed object that re-enters the
loop carrying its history, the exception hierarchy as the policy, the bounded do-until whose
ceiling produces a handoff record rather than a stack trace, retry shape as a free measurement of
whether that hierarchy is right, lineage as the chain one granularity down with parallel turning
the line into a tree, and the runtime facts — runspaces pass objects, child processes serialize
and can die before writing — that force the envelope to be committed before the risky work. It
answers: **what has to be true of a running process for the record in `refusal.md` to survive the
failure it describes?** It cites nothing external and is `[analysis]` throughout. It does not
specify an implementation, name a module, or propose a change to any existing loop.

## [`suppressed-outputs.md`](suppressed-outputs.md) — the numbers a higher score makes worse

Holds the four-stage decomposition that gives the rest of the file somewhere to sit — the task
split from the authority it runs under, the tool call as the unit of observation once steps stop
being declared in advance, and effects separated from the evidence produced about them — then the
three outputs that are systematically not collected and the structural reason each one is bad for
whoever would have to publish it, nine further absences each stated with what you would count, the
dependency argument that puts the provenance layer ahead of every diagnostic downstream of it, and
a twelve-row weight table whose last column says which rows this repository has actually measured.
It answers: **which outputs does nobody collect, and what would counting them look like?** Its
weights are a proposal with a stated rationale and are not a finding; it takes no position on
whether any of the twelve is worth what it would cost to collect, and it does not propose a record
shape — that is **B18**'s, and **D003** still freezes the eight keys.

**It is last in this list because it reads after the other four.**
[`refusal.md`](refusal.md) argues one of its twelve outputs at length and is not restated here,
[`failure-envelope.md`](failure-envelope.md) supplies the retry-ladder mechanics it counts, and its
sixth section **corrects** [`gaps.md`](gaps.md): gate latency is published, and the cost of a
gate's *evidence* is the part that is not. A reader who takes this file before `gaps.md` will meet
the correction before the claim it corrects.

---

## Terms used here that are not in the ontology

[`../VOCABULARY.md`](../VOCABULARY.md) is the root of the ontology and this set uses its terms in
its senses — **gate** (the enforcement sense unless a sentence says otherwise), **coverage**,
**provenance**, **judgment**, **control**, **handoff**, **anchor**, **chain**, **receipt**,
**guard**, **finding**.

Several load-bearing phrases in these five files are **not** VOCABULARY terms and are not
proposed as additions: *ablation ladder*, *failure envelope*, *refusal*, *rephrase count*,
*lineage*, *bypass mode*, *cost of proof*, *near-miss* and *instruction decay*. They are used as
prose. Recorded here rather than left to be noticed, because a phrase that recurs across five
files starts to read like a defined term
whether or not anyone defined it, and importing a guarantee this repository does not make is the
exact failure `docs/VOCABULARY.md` opens by warning about.
