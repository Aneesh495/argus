# Causal Inference & Counterfactual Reasoning in Argus

## 1. The Causal Hierarchy in Distributed Systems

In *Causality: Models, Reasoning, and Inference*, Judea Pearl formalizes three distinct cognitive levels of causal query, known as the **Causal Hierarchy**:

```
+-------------------------------------------------------------------------------------------------+
| Level 3: Counterfactuals | What if we had acted differently?           | P(Y_x | x', y')       |
| Level 2: Interventions   | What will happen if we take action?         | P(Y | do(X = x))      |
| Level 1: Associations    | What does observing one event tell us?      | P(Y | X)              |
+-------------------------------------------------------------------------------------------------+
```

### Why Observability Tools Fail at Level 1
Modern telemetry systems (APMs, time-series dashboards, trace search engines) operate exclusively at **Level 1 (Association)**. They compute correlations:
$$\rho(\text{CPU\_utilization}, \; \text{p99\_latency})$$
$$P(\text{Timeout} \mid \text{Service} = \text{billing})$$

In a microservice mesh, Level 1 reasoning leads to catastrophic misdiagnoses:
- **Confounding**: An upstream service retrying aggressively causes downstream thread saturation. Looking at metrics, both appear simultaneously elevated. An engineer viewing CPU graphs cannot distinguish whether service $A$ crashed service $B$ or service $B$ hung service $A$.
- **Selection Bias**: In distributed traces, spans that timeout early are truncated, while slow retries accumulate high durations. Aggregating raw durations produces survivor bias in latency distributions.
- **Inability to Test Interventions**: Level 1 models cannot answer operational questions: "If we double the Postgres max connection pool from 50 to 100, will the API Gateway p99 return below 200 milliseconds?"

Argus elevates distributed systems diagnosis to **Level 2 (Interventions)** and **Level 3 (Counterfactuals)**.

---

## 2. Structural Causal Models (SCMs) in First-Order Logic

A **Structural Causal Model (SCM)** is formally defined as a 4-tuple:

$$\mathcal{M} = \langle U, V, F, P(U) \rangle$$

### 2.1 SCM Primitives
- **$U$ (Exogenous Variables)**: Background environmental factors determined outside the system boundaries (e.g., client incoming request arrival rate $\lambda$, network transit jitter $J$, JVM garbage collection pause triggers).
- **$V$ (Endogenous Variables)**: Internal platform variables determined by interactions within the system (e.g., queue length $Q$, connection pool in-use count $C$, service span latency $L$, response status code $S$).
- **$F$ (Structural Equations)**: A deterministic set of assignments expressing each endogenous variable $V_i$ as a function of its direct causal parents $PA(V_i)$ and exogenous factors $U_i$:
  $$v_i \leftarrow f_i(pa_i, u_i)$$
- **$P(U)$ (Exogenous Prior Distribution)**: Probability distribution over background noise variables.

### 2.2 SCM Representation in Argus (`prolog/engine/causal.pl`)
In Argus, structural equations are declared as first-order causal relations:

```prolog
% Causal equation for database span latency
structural_equation(db_latency, [connection_wait, query_exec_time], Latency) :-
    Latency is connection_wait + query_exec_time.

% Connection wait time depends on pool capacity and active concurrency
structural_equation(connection_wait, [pool_capacity, active_concurrency], WaitMs) :-
    (   active_concurrency > pool_capacity
    ->  ContentionFactor is active_concurrency - pool_capacity,
        WaitMs is ContentionFactor * 45.0
    ;   WaitMs is 0.0
    ).
```

Notice that these equations are directional assignments, not symmetric mathematical equations. Setting `db_latency` directly does not alter `pool_capacity`. Causality flows strictly in the direction of the structural arrows.

---

## 3. The `do(X = x)` Calculus and Interventional Surgery

To evaluate what occurs when an operator or automated control loop takes an action, Pearl defines the **do-operator**:

$$\text{do}(X = x)$$

The `do`-operator represents an **interventional graph surgery**:
1. All incoming arrows into variable $X$ are severed from the causal graph $G$.
2. The structural equation $X = f_X(PA(X), U_X)$ is deleted.
3. A fixed constant assignment $X \leftarrow x$ is inserted in its place.
4. Downstream variables continue to compute their values via their original structural equations, but evaluated under the forced value $x$.

```
         Pre-Intervention Graph                     Post-Intervention Graph: do(Pool = 200)

               [Traffic Rate]                                 [Traffic Rate]
                /          \                                         \
               v            v                                         v
       [Active Queries] -> [Pool Size]                 [Pool Size := 200]  [Active Queries]
               \            /                                         \    /
                v          v                                           v  v
              [Queue Wait Time]                              [Queue Wait Time]
                     |                                              |
                     v                                              v
               [Span Latency]                                 [Span Latency]
```

### Implementation in Prolog
In `prolog/engine/causal.pl`, an intervention is performed by overriding the target variable in the evaluation context:

```prolog
evaluate_scm(Var, Interventions, Context, Value) :-
    member(do(Var = Val), Interventions), !,
    Value = Val.

evaluate_scm(Var, Interventions, Context, Value) :-
    structural_equation(Var, Parents, Equation),
    maplist(evaluate_scm_parent(Interventions, Context), Parents, ParentVals),
    bind_equation_vars(Parents, ParentVals, Equation),
    Value is Equation.
```

This guarantees that an intervention cleanly cuts any confounding pathways, preventing spurious non-causal associations from polluting downstream predictions.

---

## 4. Counterfactual Evaluation: The 3-Step Algorithm

A counterfactual statement concerns what *would have happened* in a specific historical instance had a variable taken a different value, contrary to the fact of what actually occurred.

### Formal Formulation
Given:
- Factual evidence $E = e$ observed during an incident (e.g., span duration was 4500ms, connection pool size was 10, database query timed out).
- Proposed alternative intervention: $\text{do}(X = x')$ (e.g., connection pool size had been 100).
- Query: What would span latency $Y$ have been under this alternate reality?
  $$Y_{X = x'}(u) \quad \text{where} \quad u \sim P(U \mid E = e)$$

Argus implements Pearl's canonical 3-step counterfactual algorithm in `prolog/engine/counterfactual.pl`:

```
   Step 1: ABDUCTION           Step 2: ACTION              Step 3: PREDICTION
   Given Evidence E = e        Apply Surgery do(X = x')    Compute Counterfactual
   Infer Background U          Modify Structural Equations Forward in Modified SCM
   
   +----------------+          +-------------------+       +--------------------+
   | Historical     |          | Sever incoming    |       | Evaluate Y using   |
   | Telemetry      |  ----->  | edges into X;     | ----> | inferred U under   |
   | Evidence (e)   |          | force X := x'     |       | modified equations |
   +----------------+          +-------------------+       +--------------------+
```

### 4.1 Step 1: Abduction
Using the observed telemetry evidence $E = e$, solve the inverse structural equations to uniquely determine or constrain the background exogenous noise terms $U$:
$$U \leftarrow \{u \in \mathcal{U} \mid F(u) = e\}$$
In distributed systems, $U$ typically captures unmeasured exogenous variables such as disk write head seek latency, external cloud provider network hop congestion, or memory allocation contention during that specific request window.

### 4.2 Step 2: Action
Apply the surgical intervention $\text{do}(X = x')$ to the structural causal model $\mathcal{M}$, replacing the structural equation for $X$ with the constant $x'$ to yield the intervened model $\mathcal{M}_{x'}$.

### 4.3 Step 3: Prediction
Using the specific exogenous variables $U$ inferred in Step 1, compute the downstream variable of interest $Y$ by forward evaluating the structural equations in $\mathcal{M}_{x'}$:
$$Y^* = F_{\mathcal{M}_{x'}}(U)$$

---

## 5. Concrete Incident Walkthrough: Connection Pool Collapse

Consider Incident 02 from the Argus Incident Zoo:
- **Service**: `orders`
- **Dependency**: `order_db`
- **Observed Evidence ($E$)**:
  - `orders` span latency: $4250\text{ ms}$
  - `order_db` pool size: $10$
  - Active incoming concurrency: $45$
  - Client timeout threshold: $3000\text{ ms}$
  - HTTP Status: `504 Gateway Timeout`

### Running the Counterfactual Query in Argus
```prolog
?- counterfactual_query(
       % 1. Observed Evidence
       [pool_capacity = 10, active_concurrency = 45, latency = 4250],
       % 2. Proposed Intervention
       do(pool_capacity = 60),
       % 3. Target Variable
       latency,
       % 4. Predicted Result
       CounterfactualLatency).
```

### Internal Execution
1. **Abduction**:
   The engine computes the exogenous database execution noise $U_{\text{exec}}$:
   $$\text{Observed Latency} = 4250\text{ ms}$$
   $$\text{Contention Factor} = 45 - 10 = 35$$
   $$\text{Queue Wait} = 35 \times 45\text{ ms} = 1575\text{ ms}$$
   $$U_{\text{exec}} = 4250\text{ ms} - 1575\text{ ms} = 2675\text{ ms}$$

2. **Action**:
   The engine cuts the connection pool equation and sets $\text{do}(\text{pool\_capacity} = 60)$.

3. **Prediction**:
   Under pool capacity 60 with active concurrency 45:
   $$\text{Active Concurrency} \le \text{Pool Capacity} \implies \text{Queue Wait} = 0\text{ ms}$$
   $$\text{Counterfactual Latency} = \text{Queue Wait} + U_{\text{exec}} = 0 + 2675\text{ ms} = 2675\text{ ms}$$

### Automated Invariant Evaluation
Argus evaluates whether the counterfactual satisfies system SLAs:
$$2675\text{ ms} < 3000\text{ ms (Client Timeout)}$$

Result: **Remediation Validated**. Sizing the connection pool to 60 is mathematically proven to eliminate the 504 Gateway Timeout for this request profile.
