# Position

Why this repository exists, stated once. Not a plan and not a promise about what is built;
see IDEAS.md for unscheduled work and README.md for current scope.

## Each transition abstracted something, then waited on a control plane

Physical servers to virtual machines abstracted the hardware. Virtual machines to containers
abstracted the operating system. Containers to agents abstracted the instructions: you stop
saying how and start saying what.

The pattern worth noticing is not that the unit got smaller. It is that each transition
produced a capability nobody could operate at scale until a control plane arrived.
Virtualization was a curiosity until something scheduled and accounted for it. Containers
were a developer toy until orchestration made them the unit of production. In both cases the
technology was ready years before the layer that made it governable.

## Agents have no scheduler

There is no layer that decides which agent runs, under whose authority, with which permitted
actions, and that proves afterwards what was done. That is not a missing feature of any
model. It is a missing layer, and it is made of policy, identity and provenance.

## What that implies about the next abstraction

If the progression holds, the layer above an agent does not abstract the task. It abstracts
intent: you state the outcome and the constraints it must hold, and the layer below decides
how. That is only meaningful if the constraints are enforceable and the enforcement is
provable. Stated outcomes with unenforced constraints are a prompt, not an abstraction.

## Where this repository sits

Provenance — a tamper-evident record of what an agent did — and gating — enforcement before
it acts. Those are the two primitives a control plane needs and cannot fake. Judgment,
attribution and consequence build on them. The guiding rule is that receipts are libraries
and judgments are containers: the record format must be reusable and language-neutral, while
the decisions made about a record belong to whoever is accountable for them.

The commodity layer here is reproducible by a competent team. The durable position is the
format and the schema, published, with a conformance suite that shows where other systems
trust a record they should not.
