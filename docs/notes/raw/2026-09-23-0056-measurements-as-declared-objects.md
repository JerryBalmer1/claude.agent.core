---
date: 2026-09-23T00:56:59-07:00
slug: measurements-as-declared-objects
source: chat
status: raw
---

The census above was produced ad hoc by an agent. Repeated next
month it would be shaped differently, so two runs cannot be
compared. Proposal: a measurement is declared in config (name,
what it counts, which paths, what it emits), a script reads the
config and emits typed datapoints, the same shape every run. The
census, the per-file Pester table, chain length, verify wall
clock, check durations and diff size are the first candidates —
every one is already being reported by hand in every run.
Distinguishes a finding (a thing noticed once) from a datapoint
(the same measurement taken again). Datapoints are what B25's
recurrence counting and F91's cost-of-proof curve both need and
neither has. Not built. Trigger to build: the third run that
reports the same table by hand.
