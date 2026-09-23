# FAILURE ENVELOPE — a refusal is an object, not an ending

The mechanical companion to [`refusal.md`](refusal.md). That file argues a refusal has to be
recorded; this one is about what the thing being recorded actually *is* in a running process,
and what has to be true of the runtime for the record to survive the failure it describes.

**Everything below is marked `[analysis]` — it is our reasoning throughout, and this file cites
nothing external.**

---

## The typed object

[analysis] A refusal or an error is a typed object that re-enters the loop carrying its history.
It is not a terminal state and it is not a string.

The difference is the history. A terminal state has one useful property — that it happened — and
a caller can do exactly one thing with it, which is stop. An object that carries what was asked,
which rule bound, and what the previous attempts were is something a caller can *act on*: narrow
the request, escalate, or hand off. The loop that receives it can make a decision, and every
decision it makes is recoverable from the object rather than reconstructed from a log somebody
reads later.

[analysis] Stated as a rule the rest of this file depends on: anything that collapses the object
back into a string — a message, an exit code, a formatted line — has thrown away the part that
made the loop possible, and it has usually thrown it away at the exact moment it mattered.

## The exception hierarchy is the policy

[analysis] The hierarchy is not plumbing. It is the policy, expressed as types, and the rule it
encodes is: **catch at the level that knows what to do.**

- A **parameter-set validation failure is recoverable.** Something was asked in a shape that is
  not expressible. The right response is not a retry with the same shape and it is not a stack
  trace; it is to return the allowed shape, so the caller's next attempt is informed rather than
  a guess. A validation error that says only *invalid* has converted a solvable problem into a
  guessing game and then charged for the guesses.
- An **authority violation should not loop at all.** Something was asked that the caller is not
  permitted to ask. Retrying is not an approach to that; retrying *is* the attack. A hierarchy
  that lets an authority violation fall into the same catch block as a validation failure has
  made the two indistinguishable at the only place the difference is actionable.

[analysis] This is why the hierarchy has to be designed before the loop is written. A loop
written against a flat error type will grow string matching on messages, and string matching on
messages is a policy nobody reviewed, written in the place least likely to be read.

## The bounded do-until

[analysis] Every retry loop gets an iteration ceiling, and hitting the ceiling is a defined
outcome rather than an exhaustion.

**Hitting it produces a handoff record with all attempts attached, not a stack trace.** The
artifact is a sentence of the form *could not express this within its authority after N
attempts*, with the N attempts carried alongside it. That record is useful to three different
readers: the caller, who learns the request is not expressible; whoever maintains the rule table,
who learns where it does not cover a real case; and an auditor, who gets a bounded, complete
account of a failure rather than the last frame of it.

[analysis] A stack trace at the ceiling is the wrong artifact for a specific reason. It describes
where the *code* was when the budget ran out, which is the least interesting fact available. The
interesting facts are what was attempted, in what order, and how the attempts differed.

## Retry shape as a test of our own hierarchy

[analysis] Once the attempts are attached, their shape is a measurement of whether the hierarchy
above is right, and it is cheap to compute.

- **Near-duplicate attempts mean thrashing.** The caller is not learning anything from the error,
  which means the error is not telling it anything — a validation failure that failed to return
  the allowed shape, or an authority violation being retried because it was catchable at the
  wrong level.
- **Narrowing attempts mean converging.** Each error taught the caller something and the
  hierarchy is doing its job.

[analysis] The comparison is over the attempts already in the record, so it costs nothing extra
to collect and it makes a structural property of the error design observable at runtime instead
of arguable in review.

## The ugly case

[analysis] An agent looping until the phrasing passes is the rephrase problem from
[`refusal.md`](refusal.md), automated. It is worse than the human version in exactly one respect
and it is the respect that matters: it is fast, so a boundary that a person would have crossed
three times an hour gets crossed thirty times a minute, and every crossing is individually
legitimate.

Three things are required and none of them is optional.

1. **Bound it.** The ceiling above is what makes the loop finite.
2. **Log every attempt.** Not the successful one — every one. The attempt history is the only
   evidence that a pass was a pass under pressure.
3. **Never let a pass on iteration 27 look identical to a pass on iteration 1.** If the record of
   success is the same object in both cases, the system has thrown away the single fact that
   distinguishes a rule that held from a rule that was worn down, and it has thrown it away at
   the moment of success, when nobody is looking for a problem.

## Lineage

[analysis] Spawned instances carry parent identity. That is the same structure as the **chain**
in [`../VOCABULARY.md`](../VOCABULARY.md) — each record's `prev` holding the previous record's
`self` — one granularity down, which means the verifier logic may be reusable rather than
rewritten. Worth checking before anything is designed, because a second hand-written verifier is
a second place the walk can be subtly wrong.

[analysis] **Parallel execution breaks linear ordering, and that is the part to design rather
than discover.** A `seq` that is monotonic and gapless is a claim about a single line of work.
Two children running at once have no honest total order between them. What survives is a parent
hash plus a branch identifier: a tree rather than a line. The merge point then records which
branch won, which lost, and why.

[analysis] **If only winners get receipts, we have rebuilt the blindness this file exists to
name.** A losing branch is a refusal in a different costume — work that was attempted and did
not become the outcome — and dropping it reproduces, one layer down, exactly the
count-only-what-happened failure [`refusal.md`](refusal.md) is about.

## Runtime reality, and why the envelope is written first

[analysis] The runtime is not neutral about any of this and the two cases differ in a way that
decides the design.

- **Runspaces share a process and pass objects intact.** The typed object survives the boundary
  as an object, with its history attached.
- **Child processes serialize.** What crosses is a projection of the object, and an unhandled
  exception can kill the process before anything at all is written — no record, no attempts, no
  envelope.

[analysis] **Therefore the envelope is committed before the risky work, not after it.** This is
the same rule as writing the receipt before the commit it rides in: a record written after the
thing it records is a record that is missing exactly when the thing went wrong, which is the only
time anybody needs it. An envelope opened first and closed afterwards leaves an open envelope
when the process dies, and an open envelope is a finding. An envelope written afterwards leaves
nothing, and nothing is indistinguishable from nothing having happened.

[analysis] **Flag the top-level catch that swallows everything into one generic bucket.** It is
the most common shape in the wild and it defeats every section above simultaneously: the
hierarchy is collapsed so nothing catches at the level that knows what to do, the attempt history
is discarded so retry shape cannot be computed, and the envelope that does get written arrives
saying nothing beyond the fact that something failed. A generic catch is not a safety net. It is
a shredder with a log line.
