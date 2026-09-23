# INSTRUMENTATION — and the limits of self-report

[`suppressed-outputs.md`](suppressed-outputs.md) asks which outputs nobody collects. This file
asks the narrower question one layer in: which of them **this repository could collect**, and how
the answer splits by whether anybody can check it. **B22** in [`../BACKLOG.md`](../BACKLOG.md) is
the record shape that split argues for.

**Everything below is marked `[analysis]` — it is our reasoning throughout, and this file cites
nothing external.** Where it restates a rule that is already written down elsewhere in this tree,
it says where, and does not re-derive it.

---

## What core can count without cooperation

[analysis] These are countable from the repository and the run, by something the agent does not
control, and not one of them requires the agent to say anything:

- **Wall clock**, per run and per step.
- **File count and diff size**, which `git` already holds.
- **Check durations**, one per required check.
- **Chain length**, which `scripts/forensic.ps1 -Anchor` prints.
- **Gated call count** — the count a chokepoint keeps of what passed through it.

[analysis] The last is the only one that does not exist yet, and it is the one the rest hang off.
The other five are measurable today. These are **proof** in the narrow sense that matters here: a
second party with the same tree and the same clock arrives at the same number, and the agent's
account of the run is not an input to any of them.

## What core cannot see

[analysis] Tokens and context occupancy exist in the agent's session. They do not exist in the
repository, and no amount of instrumentation inside the tree reaches them — there is nothing here
to read. That is a boundary, not a permission somebody forgot to grant.

[analysis] So a token count written into a record here is not a measurement. **A number the agent
reports about itself is evidence of a claim, not evidence of a fact.** That is not an accusation
of dishonesty and does not need to be: the number is unverifiable in principle from this side of
the boundary, and unverifiable is a property of the arrangement rather than of the reporter.

[analysis] The consequence for the schema is a labelling obligation. **The record states which
class each field belongs to, in the record, rather than leaving a reader to infer it.** A reader
who must already know which fields core can see in order to read the record correctly will
eventually be a reader who does not know — and the two kinds of field look identical the moment
they are sitting in the same object.

## Why both go in the same record

[analysis] The obvious alternative is to keep only what can be verified and drop the rest. That
is wrong, and the reason is that the two classes are only worth anything together.

[analysis] **Self-reported beside independently counted is what makes disagreement visible.** A
self-reported step count next to a counted call count is a comparison; either number alone is a
number with nothing to be checked against. A record holding only the verified half cannot catch a
false report, because it does not contain one. A record holding only the self-reported half
cannot catch anything at all.

[analysis] This is the construction `docs/IDEAS.md` already describes for the chokepoint — a
bypassing call leaves the wrapper's receipt missing and the sentinel's receipt present, and the
**disagreement between two records** is the finding rather than the silence. Two records of one
event, written by two parties with different visibility, is the general shape. Instrumentation is
that shape applied to counting instead of to gating.

## Absence is the failure mode

[analysis] An agent that skips the wrapper produces no record. Not a wrong record — none. And no
record is indistinguishable from a clean run unless something makes the absence loud.

[analysis] This is where the argument stops being about numbers. Every field in the two sections
above assumes a record exists to hold it. The failure that matters is not a field carrying a bad
value; it is a run that went past without producing anything, which is precisely the state a
quiet system reports as fine.

[analysis] **The consequence, stated here so it cannot be softened later: a missing record
fails.** Not warns, not logs, not reconciles at the end of the week. The same rule already holds
one layer down — `scripts/Invoke-Preflight.ps1` keeps exit 2 apart from exit 0 exactly so that
*no answer* cannot be read as *no overlap* — and the reasoning transfers unchanged. **B23** is
the check this argument asks for, and this paragraph is why its second sentence is the
load-bearing one.

## Deterrence does not apply

[analysis] A check that exists to make the agent regret something is theatre here, and the reason
is mechanical rather than moral. **The agent is cleared between runs and carries no consequence
forward.** Nothing it meets at the end of one run is available to it at the start of the next, so
there is no gradient for a penalty to act along.

[analysis] [`refusal.md`](refusal.md) -> *"Refusal has to be cheap, or honest behaviour gets
selected out"* makes the general version of this argument: the cost of refusing is borne
immediately and locally, the cost of not refusing is borne later and by somebody else, and that
is a selection pressure rather than a character flaw. The instrumentation case is the same
argument with one term deleted. There is no *later* for a cleared agent, so the gradient does not
merely point the wrong way — it is absent, and a design built to push against it is pushing
against a mechanism that is not there.

[analysis] **What changes behaviour is the ungated path ceasing to exist.** Not a check, not a
score, not a record of having been caught. The check is for somebody else entirely: **it exists
to tell the operator that the gate was skipped.** That is a smaller claim than deterrence, and it
is the one that survives.

## Process reality

[analysis] One runtime fact, restated because it recurs and because every version of this
argument walks into it. **A `finally` block runs on Ctrl-C in PowerShell 7 and does not run on a
process kill.**

[analysis] So `finally` may *update* the envelope and must not be its only writer. A record whose
sole writer is a `finally` block is present exactly when nothing went badly wrong and absent
exactly when it did — which is the absence failure above, arriving through a language feature
instead of through an agent's choice.

[analysis] [`failure-envelope.md`](failure-envelope.md) -> *"Runtime reality, and why the
envelope is written first"* states the rule and its reason already: the envelope is committed
before the risky work, on the same grounds as writing the receipt before the commit it rides in.
It is restated here rather than cited and dropped, because it is the one rule in this file that
is broken by writing the obvious code, and because it has now been arrived at from three
directions rather than one.

## What would make this file wrong

[analysis] Three conditions, each killing a specific section rather than the file in general.

**If self-reported and independently counted figures never disagree across a real workload,
section 3 is overhead.** The entire argument for carrying both is that the comparison can fail.
If it never fails — over enough runs to mean something, not three — then the self-reported half
is an expensive way of storing what was already known, and the record should carry the counted
half alone.

**If skipped runs turn out to be detectable some cheaper way, section 4 is over-engineering.**
Making absence loud is not free: every run has to produce something, and every consumer has to
treat nothing as a failure. If one after-the-fact reconciliation catches the same cases, the
machinery is unnecessary, and what was argued as a requirement was a preference for strictness.

**If cost per merged change does not fall as the rules sharpen, the whole instrumentation
argument fails on its own terms.** This is the condition that takes the file with it. The premise
under every section above is that measuring a run makes the next run cheaper, by making the rules
better. If the measured cost of getting a change merged is flat or rising while the rules
accumulate, then the instrumentation is documenting its own overhead, and the honest reading is
that the rules are the cost rather than the cure.
