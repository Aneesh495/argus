# ADR 0003: Allen's Interval Algebra over CLP(FD)

## Status
Accepted

## Context
Distributed traces consist of spans with start and end timestamps. Determining whether two spans were truly concurrent, whether a downstream operation delayed an upstream caller, or whether operations intersected requires evaluating temporal interval relations.
Relying on floating point timestamp comparisons across unsynchronized clocks produces subtle race conditions and ordering errors.

## Decision
We implemented James Allen's 13 interval relations (`before`, `meets`, `overlaps`, `starts`, `during`, `finishes`, `equals`, and their inverses) in `prolog/core/interval.pl` using Constraint Logic Programming over Finite Domains (`library(clpfd)`).
Spans are represented as closed integer microsecond domains:
```prolog
Start #< End,
Duration #= End - Start.
```

## Consequences
- **Positive**: Temporal constraints are evaluated bidirectionally, allowing deductive propagation of missing timestamps.
- **Positive**: Strict mathematical guarantees on concurrency and overlap detection.
- **Negative**: CLP(FD) domain variables require labeling if concrete values must be enumerated.
- **Mitigation**: Spans in telemetry typically arrive with bound timestamps; CLP(FD) operates as an efficient constraint verifier and interval propagator.
