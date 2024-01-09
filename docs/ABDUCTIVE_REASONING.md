# Abductive Logic Programming in Distributed Systems Diagnosis

## 1. Formal Theoretical Foundations

In mathematical logic and epistemology, inference is classically partitioned into deduction, induction, and abduction:

1. **Deduction (Prediction)**: Given general theory $T$ and known cause $C$, deduce observed effect $E$:
   $$T \cup \{C\} \vdash E$$
2. **Induction (Learning)**: Given multiple pairs of causes $C_i$ and effects $E_i$, synthesize general theory $T$:
   $$\forall i, \; T \cup \{C_i\} \models E_i$$
3. **Abduction (Diagnosis)**: Given general theory $T$ and observed symptom $E$, infer the most plausible underlying cause $C$:
   $$T \cup \{C\} \models E$$

Distributed systems incident analysis is fundamentally an **abductive problem**. When an on-call engineer observes an elevated 504 Gateway Timeout rate or a spike in p99 database query latency, the fault that produced the symptom is unobserved. The engineer's goal is to abduce the minimal set of platform faults that logically entails the telemetry anomalies without violating physical or structural invariants.

---

## 2. Abductive Logic Programming (ALP) Specification

In Argus, the diagnostic core is formalized as an Abductive Logic Programming triple:

$$\mathcal{T} = \langle T, \mathcal{A}, IC \rangle$$

### 2.1 The Components
- **Background Theory ($T$)**: A set of first-order Horn clauses defining how low-level system faults propagate through services, network hops, connection pools, and thread schedulers.
- **Abducible Predicates ($\mathcal{A}$)**: A designated set of open predicates representing primitive system faults that cannot be directly proven from the background theory, but may be hypothesized. In Argus, this includes:
  ```prolog
  fault(retry_storm, Service)
  fault(connection_pool, Service)
  fault(queue_saturation, Service)
  fault(gc_pause, Service)
  fault(thread_exhaustion, Service)
  fault(lock_contention, Service)
  fault(circuit_breaker, Service)
  fault(memory_pressure, Service)
  fault(cache_stampede, Service)
  fault(network_partition, Service)
  fault(disk_io_stall, Service)
  fault(distributed_txn, Service)
  ```
- **Integrity Constraints ($IC$)**: Negative clauses representing system states that are logically or physically impossible. Any candidate hypothesis $\Delta$ that entails an integrity constraint violation is immediately discarded:
  $$\forall ic \in IC, \quad T \cup \Delta \not\models \bot$$

### 2.2 The Abductive Problem
Given an observation set $O = \{o_1, o_2, \dots, o_k\}$ (such as error status codes, latency anomalies, queue lag metrics), find a minimal abductive explanation $\Delta \subseteq \mathcal{A}$ satisfying:
1. **Entailment**: $T \cup \Delta \models O$ (The abduced faults completely explain all symptoms).
2. **Consistency**: $T \cup \Delta \cup IC \not\models \bot$ (The abduced faults violate no integrity constraints).
3. **Minimality**: No proper subset $\Delta' \subset \Delta$ satisfies conditions 1 and 2.

---

## 3. The Argus Meta-Interpreter (`prolog/engine/abductive.pl`)

Argus implements a specialized Prolog meta-interpreter that weaves goal resolution with dynamic hypothesis accumulation and constraint verification:

```prolog
prove(Goal, DeltaIn, DeltaOut, CostIn, CostOut)
```

### 3.1 Inference Rules

#### Rule 1: Truth and Conjunction
```prolog
prove(true, Delta, Delta, Cost, Cost) :- !.

prove((G1, G2), Delta0, Delta2, Cost0, Cost2) :- !,
    prove(G1, Delta0, Delta1, Cost0, Cost1),
    prove(G2, Delta1, Delta2, Cost1, Cost2).
```

#### Rule 2: Built-in Predicates
Arithmetic comparisons and platform built-ins evaluate directly without altering the abduced hypothesis set $\Delta$:
```prolog
prove(Builtin, Delta, Delta, Cost, Cost) :-
    predicate_property(Builtin, built_in), !,
    call(Builtin).
```

#### Rule 3: Abducible Resolution
When the current subgoal $G$ unifies with an abducible predicate $A \in \mathcal{A}$:
- **Case 3a: Already Abduced**: If $A$ is already present in $\Delta_{in}$, succeed immediately with zero additional cost.
- **Case 3b: New Abducible**: If $A$ is not yet assumed:
  1. Retrieve intrinsic cost $c(A)$ from the fault prior distribution.
  2. Increment accumulated cost: $\text{Cost}_{out} = \text{Cost}_{in} + c(A)$.
  3. Verify that accumulated cost does not exceed the current branch-and-bound bound.
  4. Temporarily assume $\Delta' = \Delta_{in} \cup \{A\}$.
  5. Check all active integrity constraints against $\Delta'$.
  6. Return $\Delta_{out} = \Delta'$.

```prolog
prove(Abducible, Delta0, Delta0, Cost, Cost) :-
    is_abducible(Abducible),
    member(Abducible, Delta0), !.

prove(Abducible, Delta0, [Abducible|Delta0], Cost0, Cost1) :-
    is_abducible(Abducible),
    abducible_cost(Abducible, UnitCost),
    Cost1 is Cost0 + UnitCost,
    check_integrity_constraints([Abducible|Delta0]).
```

#### Rule 4: Normal Clause Unfolding
When $G$ is a derived rule in background theory $T$, unfold $G$ against matching clauses in the knowledge base:
```prolog
prove(Goal, Delta0, Delta1, Cost0, Cost1) :-
    clause(Goal, Body),
    prove(Body, Delta0, Delta1, Cost0, Cost1).
```

---

## 4. Integrity Constraints and Pruning

Integrity constraints prevent the abductive engine from hallucinating contradictory or impossible root causes.

### Example 1: Contradictory Network States
A service cannot simultaneously be experiencing complete packet loss partition and active TLS connection pool starvation on the same network interface:
```prolog
integrity_constraint(Delta) :-
    member(fault(network_partition, Svc), Delta),
    member(fault(connection_pool, Svc), Delta), !,
    fail.
```

### Example 2: Cold-Start vs. Long-Running Contention
A thread pool exhaustion caused by a long-running deadlock cannot co-occur with a fresh container initialization crash-loop:
```prolog
integrity_constraint(Delta) :-
    member(fault(container_cold_boot, Svc), Delta),
    member(fault(thread_exhaustion, Svc), Delta), !,
    fail.
```

Whenever a candidate abducible is considered, the engine checks all relevant integrity constraints. If any constraint fails, the engine prunes the branch immediately via backtracking, preventing useless search down invalid subtrees.

---

## 5. Occam's Razor and Branch-and-Bound Minimality

In real-world incidents, an outage could theoretically be explained by an absurd hypothesis: "15 independent microservices all suffered simultaneous cosmic ray bit-flips at the exact same microsecond." 

To avoid degenerate explanations, Argus enforces **Occam's Razor** (the principle of parsimony) using branch-and-bound optimization.

### 5.1 Cost Function
Each abducible $A \in \mathcal{A}$ has an assigned failure cost $c(A)$, inversely proportional to its prior log-likelihood:
$$c(A) = -\ln P(A)$$

Common failure modes (e.g., Redis cache misses or HTTP retry amplification) carry lower cost, while rare Byzantine failures carry higher cost.

The total hypothesis cost is additive:
$$\text{Cost}(\Delta) = \sum_{A \in \Delta} c(A)$$

### 5.2 Branch-and-Bound Execution
The search maintains an upper bound $\mathcal{B}$, initialized to $\infty$.
1. Upon discovering a valid explanation $\Delta_1$ satisfying $T \cup \Delta_1 \models O$ with $\text{Cost}(\Delta_1) = K_1$:
   - Update bound $\mathcal{B} \leftarrow K_1$.
2. As subsequent search branches expand:
   - If accumulated cost $\text{Cost}_{in} \ge \mathcal{B}$, terminate the branch immediately (alpha pruning).
3. The search terminates when all branches are pruned or explored, guaranteeing discovery of the global minimum cost explanation $\Delta^*$.

---

## 6. Bayesian Posterior Confidence Scoring (`prolog/engine/hypothesis.pl`)

Once the minimal abductive explanation $\Delta$ is identified, Argus computes a calibrated posterior confidence score $P(\Delta \mid O)$ via Bayes' Theorem:

$$P(\Delta \mid O) = \frac{P(O \mid \Delta) \cdot P(\Delta)}{\sum_{\Delta' \in \text{Candidates}} P(O \mid \Delta') \cdot P(\Delta')}$$

Where:
- $P(\Delta)$ is the prior probability of the fault combination.
- $P(O \mid \Delta)$ is the likelihood of observing the specific telemetry signatures (spans, metric deviations, error log counts) given the presence of fault $\Delta$.
- Evidence scoring rewards explanations whose causal propagation path covers all observed anomalies while leaving zero unmodeled symptoms.
