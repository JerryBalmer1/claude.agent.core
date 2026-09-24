# REFUSAL — the record nobody keeps

Equal in priority to [`gaps.md`](gaps.md), and separate from it because a gap in the market and
a gap in a record shape are different kinds of thing. This file is about what happens when a
**gate** in the enforcement sense says no, and about the fact that almost nothing in the field
is built to hold that answer.

**Everything below is marked `[analysis]` by default — it is our reasoning, not a cited claim.**
The one external citation is in the last section and carries its source inline.

---

## Why refusals go uncounted

[analysis] Vendors count actions taken. Calls served, tasks completed, tokens spent, time saved
— every one of those is a number a dashboard already has a column for, because every one of them
is a thing that happened. A refusal is a thing that did not happen, and nothing in the standard
shape of an agent product has a place to put it.

The consequence runs in one direction and it is not subtle. Refusals are uncounted, so nothing
is built for them; nothing is built for them, so a gate that stops binding produces no signal
that it stopped; and a gate that produces no signal when it stops binding is indistinguishable
from a gate that is working. This is the same shape as **coverage** in
[`../VOCABULARY.md`](../VOCABULARY.md) and the same shape as the *honest denial with no trace*
entry in the adversarial catalogue in `docs/IDEAS.md`.

[analysis] The parallel worth drawing is technical debt. Debt was invisible for the same
structural reason — it was the absence of work rather than the presence of it, so no report had
a column for it — and it stayed invisible until somebody gave it a name, a unit and a place in
the record. It did not become measurable because anyone discovered a new measurement. It became
measurable because it became a thing you could write down. Refusal is at the stage debt was at
before the name.

## What a refusal record has to hold

[analysis] A refusal is not an event with a timestamp. It is a record with structure, and there
are five fields:

- **who refused** — the enforcement point, not the agent. A refusal the agent reports about
  itself is self-report, and `docs/IDEAS.md` is explicit that self-report is the thing not to
  trust.
- **what was asked** — the call as it arrived, before any normalisation that might launder it.
- **which rule bound** — the specific rule, not the fact that some rule did.
- **that rule's version at that moment** — the field [`gaps.md`](gaps.md) records as
  compliance-grade and as the one **D003**'s frozen eight keys have no room for. Without it, a
  refusal cannot be re-evaluated against the rule that actually produced it, only against
  whatever the rule says today.
- **what happened next** — the aftermath.

[analysis] **The aftermath field is the one everyone skips and it is the most valuable.** It has
three values that matter: the refusal was *overridden*, it was *rephrased around*, or it was
*accepted*. A refusal record without it says a boundary was touched. A refusal record with it
says whether the boundary held. Those are different claims, and only the second one is worth
anything to somebody deciding whether to trust the system.

## The rephrase count is the signal

[analysis] A refusal followed by reformulation, followed by another refusal, followed by another
reformulation, until something finally passes, is a boundary that failed under pressure. It is
also, in every standard tool available today, recorded as a successful block followed by a
successful action. Both records are individually true. Together they describe the opposite of
what happened.

[analysis] The rephrase count is what separates them, and it is one integer. Nothing else in
this file is as cheap. A boundary that is crossed on the first ask and a boundary that is crossed
on the ninth are different boundaries, and a system that cannot tell them apart is reporting the
same number for a wall and a turnstile.

## Refusal has to be cheap, or honest behaviour gets selected out

[analysis] If declining kills the run, humans and agents both route around the gate, and they
route around it for the same reason: the cost of refusing is borne immediately and locally, and
the cost of not refusing is borne later and by somebody else. That is a selection pressure, not
a character flaw, and it will beat any amount of documentation about how the gate should be
used.

[analysis] The affordable outcome is already named in [`../VOCABULARY.md`](../VOCABULARY.md) as
**handoff**: a record of the transfer of responsibility at a named boundary — the call ended
here, the agent continued on its own from this point, for this stated reason. A refusal that
returns a handoff record naming where the guarantee stopped is a run that *succeeded by
declining*. The work is not abandoned and the boundary is not crossed silently; what changes is
which party is answerable for what came after, and the record says where that changed.

`docs/IDEAS.md` attaches the necessary constraint to the same idea and it applies here
unchanged: the hatch must have its own declared cases or it becomes the allow-all rule at the
bottom of the table.

## Metrics, and the ones that lie

[analysis] **Refusal rate is a boundary map, not a defect count.** Treating it as a defect count
produces a target to drive to zero, and the cheapest way to drive it to zero is to stop refusing.

- **Rising refusals concentrated on one surface** mean the declared parameter sets do not cover
  a real case. That is a finding about the rule table, not about the caller, and it is the same
  signal `docs/IDEAS.md` describes when it says a constantly-used escape hatch means the
  parameter sets are wrong.
- **Zero refusals ever is the alarming reading**, not the clean one. A gate that has never
  refused anything has either never been tested against a real boundary or has stopped being in
  the path, and nothing in the refusal record itself can tell those two apart.
- **The number that matters is refusals that were right.** A system that refuses everything
  scores perfectly on refusal rate and is useless. Correctness of refusal is a **judgment**
  question in the [`../VOCABULARY.md`](../VOCABULARY.md) sense, which `README.md` puts out of
  scope for v1 — so the honest position is that the only metric that matters is the one this
  repository cannot currently compute, and the record shape should be built so that somebody
  later can.

## The liability surface, stated plainly

[analysis] Every logged refusal is a record that somebody asked. The refusal itself is evidence
the system worked; the question is evidence the question was posed, by a named actor, at a
timestamp, inside an organisation that keeps records for longer than it would like to.

Enterprises may not want that written down. That is not a hypothetical objection to be argued
away — it is a predictable reason a refusal log gets configured off, and configuring it off
produces exactly the invisible-boundary failure the rest of this file is about.

**The reluctance is itself a finding.** A buyer who wants enforcement but not the record of what
was refused wants the gate's effect without the gate's evidence, and that preference tells you
more about what is actually being purchased than any stated requirement will.

## What a chain can and cannot say about a refusal that is missing

A hash chain makes tampering or omission detectable only when the verifier has a trusted
checkpoint, and a missing record is not proof of absence — incomplete ranges must be marked, not
assumed (dev.to/zira125).

[analysis] Both clauses bite here. The trusted checkpoint is the **anchor** in
[`../VOCABULARY.md`](../VOCABULARY.md), which is worth exactly what its independence from the
writer is worth. And the second clause is the reason refusal records cannot be verified the way
receipts are: a refusal that was never written leaves a chain that verifies green, and a
verifier that reports green on an incomplete range has reported the absence of evidence as
evidence of absence. `tests/Skeleton.Tests.ps1` already asserts the cheapest instance of this —
the chain must be non-empty, because an absent chain verifies green — and that assertion is a
floor, not a solution.
