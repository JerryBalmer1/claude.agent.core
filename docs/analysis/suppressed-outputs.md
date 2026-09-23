# SUPPRESSED OUTPUTS — the numbers a higher score makes worse

The fifth file in the set, written on 2026-09-23 rather than with the other four. It is about the
outputs an agentic system produces that nobody collects, why the omission is structural rather
than conspiratorial, and what would have to be counted for any of them to become measurable.

**Every external claim carries its source inline, by number**, and the numbered list is at the
bottom. A sentence that is our own reasoning rather than a cited claim is marked `[analysis]`.
[`refusal.md`](refusal.md) is the companion: that file argues one of these outputs at length, and
this one places it among the others without restating it.

**This file also carries a correction.** The claim that cost of proof is unpublished was made in
this repository before the literature was read, and section 6 narrows it. That section is here
rather than in a commit message because the wide claim is in the tree.

---

## Four stages, not three

[analysis] The usual decomposition of a system is inputs, computation, outputs. For an agentic
system it hides the thing that matters, and the fix is to split the first stage and rename the
third.

**Inputs split into the task and the authority it runs under.** The task is what was asked. The
authority is the credentials it holds, the scope it may reach, and the rules in force at that
moment. A build agent gets both explicitly: the job definition names the task, and the runner's
token, the permissions block and the workflow file name the authority. An agentic agent gets the
task explicitly and the authority *implicitly* — it inherits an ambient session, a set of
credentials nobody enumerated at the point of use, and a rule set that exists as prose. The gap
between those two is not a difference of degree. It is the reason one of them can be audited from
its configuration and the other cannot.

**Computation is where the unit changes.** A build agent runs declared steps, and the step is the
unit of observation: it is named in a file before it runs, and the file is reviewable. An agentic
agent decides its steps at runtime, so no declared list exists to observe against, and the only
unit left is **the tool call**. That is why the chokepoint exists at all. It is not a design
preference — it is the last place where a unit of work is still nameable, because every layer
above it is chosen after the fact.

**Effects, not outputs.** What a system does is write files, start processes, reach the network,
and change other systems. Those are effects, and effects are what a gate acts on. Calling them
outputs merges them with the thing the fourth stage produces, which is a different kind of object.

**Outputs are evidence.** Artifacts, receipts, refusals, handoff records — the things that say what
happened. [analysis] Once the four stages are separated this way, the subject of this file has a
place to sit: everything below is a stage-four output, which is why none of it is visible to a
system that instruments stage three.

## Three outputs that get suppressed, and why it isn't a conspiracy

[analysis] Three outputs are systematically not collected, and in each case the reason is that the
number is bad for the party who would have to publish it.

**Refusals read as capability failures in a demo.** A system that declines looks like a system that
cannot. The distinction between *would not* and *could not* is invisible to anyone watching for
thirty seconds, and a demo is thirty seconds. Published abstention work bears on the direction of
travel rather than the presentation problem: AbstentionBench finds that reasoning fine-tuning can
*worsen* abstention, so the capability is not simply accumulating as models improve (source 17).
And answer-confidence scores do not substitute for it, because a confidence signal reads whether
the attempt succeeded, not whether it should have been made at all (source 18).

**Overhead invites a comparison with no upside in publishing.** A vendor who publishes a latency
number has handed every competitor a target and gained nothing, because the buyer was not going to
ask. The number is only ever a liability to the party who holds it.

**Abstention and handoff look like gaps rather than designed boundaries.** A run that stopped and
handed to a human reads as an incomplete run unless the record says the boundary was intentional,
and nothing in the standard shape of an agent product says that.

[analysis] **These are the only metrics where a higher number can mean a better system**, and that
is the whole of the problem. Every other number a dashboard carries is better when it is larger or
smaller in an obvious direction. These three are not, so the story does not sell; so the data is
not collected; so nobody can build on it. The causal chain runs in one direction and no step in it
requires anybody to act in bad faith.

## Nine further absences

[analysis] Beyond those three, nine outputs are absent from everything we have read. Each is stated
with what you would actually count.

- **The near-miss.** The gate held, barely. Count approaches to the same boundary from different
  angles within one run — a boundary touched once and a boundary touched from five directions are
  not the same event.
- **Decision provenance under uncertainty.** What the agent nearly did instead. Count the
  alternatives that were live at the branch point and discarded, not the one that was taken.
- **Work correctly skipped.** Count steps not executed *with a reason attached*. Without the
  reason it is indistinguishable from work forgotten, which is why it is never counted at all.
- **Disagreement between runs.** Count the variance across repeated runs of one task. Variance is a
  measure of how underspecified the task was, and it is currently discarded as flakiness.
- **Cost of the retry ladder.** Count what attempts 1..N-1 consumed — tokens, wall clock, calls.
  Only attempt N is reported, and it is the cheapest one.
- **Instruction decay.** Seed a rule, then sample compliance with it at intervals through a long
  run. Count the interval at which compliance falls, not whether it held at the end.
- **Which rule bound.** Five rules could have fired; one did; four are untested. Count rule
  coverage — the same shape as the dead-node count in `docs/IDEAS.md` -> *"Ontology derived from
  who will act on it"*, and the same shape as **coverage** in
  [`../VOCABULARY.md`](../VOCABULARY.md).
- **Human override latency.** Count how long a handoff sat before a human touched it, and what they
  did. A boundary that is always overridden after four seconds is not a boundary.
- **Where the guarantee stopped.** Count the edge cases the system does not cover. Nobody writes
  this down, because writing it down makes it quotable.

[analysis] **The thread is that all nine are absences.** Every one is a count of something that did
not happen, did not fire, was not reached or was not done. Event-based observability is built to
record events, and an absence is not an event — so the tooling cannot see any of them, and the
territory is open for exactly that reason rather than because it is hard.

## The dependency structure

[analysis] The reconciliation of what a policy *claims* against what it *enforces* is the work that
sits permanently in the gap. It is too small to hire for — nobody staffs a role for it — and too
irregular to script, because the claim is prose and the enforcement is code and the mapping
changes every time either moves. Work with those two properties does not get done by anyone.

[analysis] **And it is worthless without a record of what actually ran.** A reconciliation against
an unreliable account of execution reconciles nothing. So the provenance layer is not one of
several things to build; it is the precondition for the rest, and every diagnostic above depends on
it. Whoever builds it owns everything downstream of it, which is an argument about order of work
rather than about market position.

## Measurement definitions and proposed weights

**The weights below are a proposal with a stated rationale. They are not a finding, nothing is
enforced by them, and no number in the weight column was measured.** The rationale is one rule:
weight rises with how much the number changes a trust decision, and falls with how much judgment it
takes to collect — where **judgment** is in the [`../VOCABULARY.md`](../VOCABULARY.md) sense that
`README.md` puts out of scope for v1.

| Output | What is counted | Unit | Proposed weight | Measured in-tree? |
|---|---|---|---|---|
| Refusals | refusals, each with its aftermath field | count per 1000 calls | 15 | **yes** — F90, one instance |
| Cost of proof | gate wall clock, receipt bytes, verify time | ms and bytes | 15 | **yes** — F91, one point |
| Abstention and handoff | runs ended at a declared boundary | count per 1000 runs | 10 | no |
| Which rule bound | rules that fired / rules that could have | ratio | 10 | no |
| The near-miss | approaches to one boundary from distinct angles | count per run | 8 | no |
| Cost of the retry ladder | tokens and wall clock in attempts 1..N-1 | tokens, ms | 8 | no |
| Disagreement between runs | variance across repeats of one task | dimensionless | 8 | no |
| Instruction decay | interval at which compliance with a seeded rule falls | calls, or ms | 7 | no |
| Where the guarantee stopped | named uncovered edges | count | 7 | no |
| Decision provenance | live alternatives discarded at a branch point | count per branch | 5 | no |
| Human override latency | time a handoff sat, and the action taken | ms, plus a label | 4 | no |
| Work correctly skipped | steps not executed with a reason attached | count per run | 3 | no |

[analysis] The two rows marked **yes** are marked yes at their honest strength, which is one
instance and one point. Everything else is a definition without a measurement, and the column
exists so that the difference cannot be read past.

## Correction — cost of proof is partly published

**Gate latency is reported, and this repository said it was not.** The claim appears in
[`gaps.md`](gaps.md) -> *"Bottom — the weight-bearing claim"* as *"Gate overhead is unpublished,
here and everywhere"*, and it is too wide. What the literature reports:

- Governance overhead per operation, rescalable as 29.94 ms / T, with an explicit false-block
  versus false-pass tradeoff and HALT versus ESCALATE refusal modes (source 19).
- Proof-of-Guardrail inside a TEE, at roughly 34% average latency overhead (source 20).
- AgentWall, at 0.198 ms average policy decision and p95 0.745 ms (source 21).
- VIGIL, at 4.38 s per trace, of which 92.5% is a single cacheable LLM compile call (source 22).
- ActPlane, at 1.9%–8.4% overhead across 32 to 100 OS-level rules (source 23).
- An LLM-as-judge monitor at about 15.3 s mean, against a solver-backed monitor at 0.44 ms
  (source 24).
- Rule filters under 10 ms and ML classifiers at 50–200 ms, with layered budgets (source 25).

**What is not reported anywhere in those sources is receipt size per action, or verify time as a
function of chain length.** [analysis] That is the narrow claim and it is the defensible one: the
per-call latency of a gate has numbers in the literature; the cost of the *evidence* a gate leaves
behind does not. F91 is one point on the second question and the first question is not ours.

[analysis] This section exists because the wide claim appeared here first, and correcting it in
place would leave no record that it had been made. `docs/IDEAS.md` -> *"Cost of proof"* and
`docs/PRE-PUBLIC.md` -> *"Open questions with no owner"* still carry the wide phrasing; they are
named here and not edited, because this commit's scope is `docs/analysis/`.

## What would make this file wrong

[analysis] Three conditions, each of which kills a specific section rather than the file in
general.

**If the nine absences turn out to be logged by any mainstream tool, section 3 is a literature
failure.** Not a subtle one — the section claims a territory is empty, and one product's schema
carrying those fields would mean the reading behind it was inadequate rather than the argument
being wrong.

**If weighting them changes no decision in practice, section 5 is decoration.** The test is
whether a team that computes the twelve numbers and a team that does not ever act differently. If
the weights only ever reorder a report, the table is a presentation device with a rationale
attached, and should be deleted rather than defended.

**If receipt cost scales worse than linearly with chain length, the dependency argument in section
4 inverts.** Section 4 says the provenance layer is the precondition for everything else. A
provenance layer with superlinear verification cost is the component that gets switched off first
under load — and then it is not the foundation, it is the liability, and the correct order of work
is the opposite of the one argued here. BACKLOG **B17** is the harness that would settle it, and
F91 is the single point it would extend.

---

## Sources

Numbered 17–25. [analysis] The four files written on 2026-09-22 carry their citations inline and
unnumbered, so these numbers are assigned here rather than continuing a register that exists on
disk; 1–16 are those inline citations, counted in reading order. URLs are recorded as supplied and
have not been fetched from this tree — `docs/PRE-PUBLIC.md` carries the line that says every one of
them is verified before publication.

This section is apparatus. The weight-bearing section is the one above it.

17. https://emergentmind.com/articles/abstentionbench — AbstentionBench; reasoning fine-tuning can
    worsen abstention.
18. https://arxiv.org/html/2607.08456 — answer-confidence reads whether the attempt succeeded, not
    whether it should have been made.
19. https://arxiv.org/pdf/2606.20615 — governance overhead per operation, rescalable as
    29.94 ms / T; false-block versus false-pass tradeoff; HALT versus ESCALATE refusal modes.
20. https://arxiv.org/html/2603.05786v2 — Proof-of-Guardrail in a TEE, ~34% average latency
    overhead.
21. https://arxiv.org/pdf/2605.16265 — AgentWall, 0.198 ms average policy decision, p95 0.745 ms.
22. https://arxiv.org/pdf/2606.26524 — VIGIL, 4.38 s per trace, 92.5% of it one cacheable LLM
    compile call.
23. https://arxiv.org/pdf/2606.25189 — ActPlane, 1.9%–8.4% overhead at 32–100 OS-level rules.
24. https://arxiv.org/pdf/2605.29251 — LLM-as-judge ~15.3 s mean vs solver-backed monitor 0.44 ms.
25. https://blaxel.ai/blog/guardrails-for-ai-agents — rule filters under 10 ms, ML classifiers
    50–200 ms; layered budgets.
