# GAPS — what is not occupied

**Bottom-heavy on purpose: most important at the bottom, weight-bearing claim last.** Do not
reorder this file into descending importance. The top section is context a reader needs before
the bottom one means anything, and the bottom one is the only part of this file that is a
position rather than a report.

**Every external claim carries its source inline.** A sentence that is our own reasoning rather
than a cited claim is marked `[analysis]`. The companion file is [`landscape.md`](landscape.md),
which covers what *is* occupied; a gap claimed without that file is a gap in the author's
reading.

---

## Top — the adoption context

IDC puts it at 88 percent of AI pilots failing to reach production, clustering on governance,
data-readiness and observability gaps rather than on model quality (gogloby.com). The barriers
named are poor-quality data, legacy systems, weak governance, unclear objectives and limited
organisational readiness — not the models (Business Standard). Deloitte attributes 70 percent of
the problems to people and process and 10 percent to algorithms; RAND finds 84 percent of
failures leadership-driven (neomanex.com). User adoption failure is called the most overlooked
driver of pilot stalls (agentmarketcap.ai).

**The scope, stated honestly against those numbers.** This project addresses governance and
observability only. It does not address data readiness, it does not address integration, and it
does not address change management.

[analysis] What it targets is narrower than any of the figures above and is stated that way
deliberately: what stops a *working* pilot from being permitted into production. That is a slice
of the 88 percent and not the whole of it, and the figures are at the top of this file rather
than in a pitch precisely because they size the context down rather than up.

The citations above are recorded as published. This file takes no position on leadership and
offers none of the numbers as a verdict on one — the citations are the argument, and a gloss on
them would be this file substituting its own opinion for the evidence it is here to carry.

## Middle — the measured gaps

Only five percent of data leaders say AI output is traceable 100 percent of the time
(Dataiku/Harris Poll, 800-plus leaders, via dataiku.com).

*"The most common misapplication is treating policy presence as proof of enforcement"*
(nhimg.org). [analysis] That is the second item in `docs/IDEAS.md`'s inventory of what the
market is blocked on — *nobody can prove enforcement was on* — restated by somebody outside this
repository, and it is the buyer-facing name for **coverage** in
[`../VOCABULARY.md`](../VOCABULARY.md).

*"Policies might exist, but the actual actions often happen without real-time controls... after
an incident, teams cannot reliably reconstruct what happened, why or with whose authority"*
(IBM). [analysis] The three questions in that sentence — what, why, whose authority — map onto
three different layers here, and only the first is in scope. `README.md` puts **judgment** and
**attribution** out of scope for v1, so *why* and *with whose authority* are not answered by
anything in this repository and are not claimed to be.

**The limit of our own mechanism, stated rather than implied:** *"The hash chain proves that the
record exists and has not been changed. It does not prove the reasoning was sound, complete,
specific, or consistent. Tamper-evidence is a necessary property of an audit trail. It is not a
sufficient property of governance evidence"* (chrishood.com).

[analysis] Tied to the layer taxonomy, that sentence is the boundary between two
[`../VOCABULARY.md`](../VOCABULARY.md) entries and nothing more subtle than that: **provenance**
is not **judgment**. Provenance answers where a record came from. Judgment asks whether what it
records satisfied a **control**, and is out of scope for v1. A reader who takes tamper-evidence
for governance evidence has skipped a layer, and the quotation is the cleanest available
statement of which layer.

A compliance-grade trail is additionally required to record which policy version was in effect
at decision time (mightybot.ai). [analysis] This repository cannot do that today and the reason
is structural rather than an oversight: the forensic record shape is frozen at eight keys by
**D003** — `ts, seq, actor, kind, subject, evidence, prev, self` — and none of them is a policy
version. A ninth key invalidates every `self` already written. The seam is named here and not
solved; [`refusal.md`](refusal.md) names the same field again from the other direction, because
a refusal record that does not say which version of the rule bound it is a refusal nobody can
re-evaluate later.

## Bottom — the weight-bearing claim

[analysis] Existing comparisons set a rule-enforcing system against an agent with no
intervention at all, and a comparison shaped that way *"cannot separate what a targeted rule
says from the fact that it interrupts the agent at a decision point"* (arXiv 2609.26048, FIRE).
Two variables move at once and the result is attributed to the one the authors were interested
in.

[analysis] **The unoccupied position is the same task expressed twice — once as prose, once as
an enforced function — with the difference measured.** Both arms interrupt at the same decision
point; only the expression differs. That is the comparison nobody is running, and it is the only
one that isolates what the expression is worth.

[analysis] **The ablation ladder is the protocol.** Hand the same task context at level N, then
at N-1, then at N-2, and find where correctness breaks. Two constraints come with it, and
neither is optional. The file shape must be uniform at every level or the ladder measures
inconsistency in the material instead of distance between levels. And results are per-domain:
the output is a map of where abstraction holds, not a score. A single number across domains
would average a place the abstraction holds against a place it does not, and report neither.

[analysis] **The falsification condition, stated so the claim can lose.** If the gap between
prose and enforced execution does not close as the vocabulary tightens, the ontology is not
doing work. [`../VOCABULARY.md`](../VOCABULARY.md) is the thing on trial in that sentence and it
is worth saying which way the verdict could go: a tightening vocabulary that changes nothing
measurable is a document, not a mechanism. This is the same standard
[`../VOCABULARY.md`](../VOCABULARY.md) sets for a **guard** — a check that cannot go red reports
identically to one that passes — applied to an ontology instead of to a check.

[analysis] **The honesty problem, which the protocol creates for itself.** Once the wrapper is
the only callable surface an agent has, the prose path may not be runnable at all, and a harness
cannot measure an arm it cannot execute. So the harness needs a deliberate bypass mode — and
that mode is itself a gate that must be gated and receipted, or the measurement apparatus is the
hole in the thing it measures. `docs/IDEAS.md` already makes the equivalent point about its own
injection harness: a test double reachable from the runtime is an attack surface, not a test.

[analysis] **Cost of proof.** Gate *latency* is published — seven sources report it, and
[`suppressed-outputs.md`](suppressed-outputs.md) → *"Correction — cost of proof is partly
published"* lists them with their numbers. What is unpublished, there and here, is the cost of the
**evidence** a gate leaves behind: receipt size per action, and verify time as a function of chain
length. That is the narrow claim, and it replaces the wider one this file carried until
2026-09-23 — *"gate overhead is unpublished, here and everywhere"* — which was made before the
literature was read. A gate expensive enough to notice gets switched off, and a gate that gets
switched off produces exactly the silent-gap failure the adversarial catalogue in `docs/IDEAS.md`
is about. That makes overhead a security property rather than a performance footnote, and it makes
the ablation ladder above expensive to run without knowing the number first.

[analysis] **Portability, named as a seam and left unsolved.** Everything here is GitHub-shaped:
the six required checks are job keys in a GitHub Actions workflow, `branch-flow` reads a pull
request's head and base, `pr-body-links` builds permalinks against `github.com`, and
`generated-match-config` asserts that a generated document matches `config/repo.json`. Azure
DevOps has branch policies, and it has no equivalent generated artifact for
`generated-match-config` to assert against. That is the seam. This file does not cross it.
