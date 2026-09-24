# LANDSCAPE — what is already occupied

What other people have already built, published or funded in the space this repository works
in. It exists so that no position here gets defended as new when it is not, and so that a
reader arriving from outside can tell at a glance which of our positions are shared and which
are ours alone.

**Every external claim below carries its source inline.** A sentence that is our own reasoning
rather than a cited claim is marked `[analysis]`. Nothing in this file is a measurement of this
repository — measurements are findings and live in [`../FINDINGS.md`](../FINDINGS.md).

The companion file is [`gaps.md`](gaps.md), which covers what is *not* occupied. Read this one
first: a gap claimed without knowing the landscape is a gap in the author's reading.

---

## Enforcement over prompting is a crowded, established position

The distinction the **gating** primitive rests on — that an instruction and a constraint are
different kinds of thing — is stated plainly and publicly elsewhere: *"A prompt is a suggestion
to the model. A policy is an enforceable rule"* (thebackenddevelopers.substack.com, 2026).

It is also a funded category rather than an argument still being had. Gartner published its
first Market Guide for Guardian Agents in February 2026, and runtime enforcement is now treated
as a distinct budget line (accuroai.co).

[analysis] That is the useful half. A category with a Gartner guide behind it has buyers who
already accept the premise, which removes the need to argue it and removes any claim to have
originated it. `README.md` names gating as one of two in-scope primitives; it does not name it
as a new one, and after this file it cannot. The word **policy** is the one to watch here:
[`../VOCABULARY.md`](../VOCABULARY.md) keeps two senses apart, and the sense in the quotation
above is the second — a declarative artifact — which is the sense this repository does not have.

## Fitness functions are an established practice, not our invention

[`../DECISIONS.md`](../DECISIONS.md) exists because a rule nobody checks is a preference, and
every entry in it names the thing that would go red if the rule were broken. That pairing — the
written decision beside the mechanism that assures it — is published architectural practice:
*"A decision record documents the decision, while a fitness function assures the decision"*
(architecture-decision-record GitHub). Richards and Ford go further and recommend a Compliance
section in each architecture decision record specifying whether the decision can be verified by
an automated fitness function (per synchronium.github.io's summary of *Fundamentals of Software
Architecture*, ch. 19).

**Stated plainly: `docs/DECISIONS.md` is an application of that practice to an agent, not a new
idea.** The D-number register, the *Enforced by* table, the rule that an entry leaves only when
its enforcement is removed — all of it is the Compliance-section recommendation with a stable
identifier bolted on.

[analysis] What is ours is narrower than the shape and worth saying only because it is narrow:
the subject of the decision is an agent's permitted behaviour rather than an architecture's
structural characteristics, and [`../VOCABULARY.md`](../VOCABULARY.md) already records why that
makes **guard** an approximate mapping onto a fitness function rather than an equal one. A
fitness function measures a characteristic and is tuned as the architecture evolves; a guard
here is binary, adversarial, and carries a falsification test. The entry names the seam. This
file only records that the surrounding practice is somebody else's.

## Proof-of-guardrail exists and is better funded

There is published work that puts an agent and its guardrail inside a Trusted Execution
Environment and produces a TEE-signed attestation verifiable offline (arXiv 2603.05786). A
follow-up paper draws the limit itself: *"Proof-of-Guardrail does not itself enforce policy"*
(arXiv 2603.20953v1).

[analysis] Both halves land on this repository. The first is the **anchor** problem solved with
hardware — [`../VOCABULARY.md`](../VOCABULARY.md) calls the anchor "the single sharpest edge in
the whole design", because inside the repository it is just a file the writer can rewrite, and
its independence is bought by a human pasting a line into a chat. A TEE signature buys the same
independence from a manufacturer instead, which is a stronger purchase from a better-funded
shop. The second half is the seam between **provenance** and **gating**, drawn by somebody else
in one sentence: an attestation that the guardrail ran is a record, not a constraint. That is
the same distinction `README.md` draws when it puts **judgment** out of scope, and the same one
[`../IDEAS.md`](../IDEAS.md) draws when it says that until a receipt changes an outcome it is a
record rather than a control.

## The in-process limit is known, and we share it

A policy engine that lives inside the agent's own process boundary shares memory, identity and
execution context with the thing it constrains; if the agent spawns a child process or runs
generated code outside the instrumented path, *"the policy engine reports enforcement held while
it did not"* (armosec.io).

[analysis] That sentence is **coverage** — the unmet claim in
[`../VOCABULARY.md`](../VOCABULARY.md) — written from outside, by somebody with no stake in this
repository's design. [`../IDEAS.md`](../IDEAS.md) records the same limit from inside the design,
in the weaknesses of the single-entry-point entry: a wrapper that shells out re-opens everything
it closed.

**The shelving is recorded here because this is the same wall.** `docs/IDEAS.md` already puts
"any ambition to make this unbypassable against a hostile agent inside its own container" out of
scope, on the grounds that it is a research problem with a large literature and no clean answer
and that pursuing it would consume the project. The armosec sentence describes that wall from
the other side. Neither the shelving nor the citation changes what remains defensible, which
`docs/IDEAS.md` already narrowed to a claim about an agent that is not actively attacking the
runtime, with bypass attempts detectable after the fact.

[analysis] The consequence for this file is a boundary rather than a task. Nothing in the
landscape above is a gap to be filled by us, and three of the four entries are places where
somebody else's published work is the reason a claim here has to stay small.
