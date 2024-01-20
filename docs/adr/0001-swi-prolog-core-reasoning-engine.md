# ADR 0001: SWI-Prolog as Core Reasoning Engine

## Status
Accepted

## Context
Diagnosing cascading failures across hundreds of microservices requires traversing relational dependencies, evaluating complex temporal intervals, resolving non-deterministic hypothesis spaces, and evaluating negative constraints.
Traditional imperative languages (Go, Java, Python) require thousands of lines of boilerplate graph traversal and constraint checking loops, leading to rigid, bug-prone heuristic code.
We evaluated multiple platforms:
1. Pure imperative/functional languages (Go, Rust, OCaml)
2. Datalog / relational databases (Souffle, Datomic)
3. Full first-order logic engines (SWI-Prolog, ECLiPSe, GNU Prolog)

## Decision
We chose **SWI-Prolog 10** as the primary engine for Argus.
SWI-Prolog provides:
1. High-performance ISO Prolog engine with native multi-threading (`library(threads)`).
2. Embedded constraint solvers, specifically Constraint Logic Programming over Finite Domains (`library(clpfd)`).
3. First-class Definite Clause Grammars (DCG) for protocol parsing (W3C trace context, OpenMetrics).
4. Rich Foreign Language Interface (C-FLI) allowing seamless integration with C native code.
5. Dynamic clause indexing and meta-programming primitives (`clause/2`, `strip_module/3`) essential for writing custom abductive meta-interpreters.

## Consequences
- **Positive**: Core diagnostic and causal inference rules are written declaratively in concise first-order logic.
- **Positive**: Backtracking and unification automate complex multi-path hypothesis searches without manual state-space management.
- **Negative**: Foreign developers must understand relational logic programming paradigms.
- **Mitigation**: We provide clean HTTP REST and Python SDK wrappers so developers can use Argus without interacting with raw Prolog syntax.
