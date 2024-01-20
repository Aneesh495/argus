# ADR 0005: Pearl's Structural Causal Models & Counterfactuals

## Status
Accepted

## Context
Standard APM and monitoring tools rely on statistical correlations (e.g., metric anomaly spikes, co-occurring error codes). These tools fail to differentiate correlation from causation, leading to alert storms and incorrect root-cause attribution.
Furthermore, operators cannot verify whether a proposed remediation will actually solve the issue without applying it to production.

## Decision
We adopted Judea Pearl's **Structural Causal Models (SCMs)** and **do-calculus** as the formal foundation for causality in Argus (`prolog/engine/causal.pl` and `prolog/engine/counterfactual.pl`).
1. **Structural Equations**: Endogenous telemetry variables are modeled as directional functional dependencies conditioned on parent variables and background exogenous factors $U$.
2. **Interventions**: The `do(X = x)` operator cuts all incoming edges to $X$, modeling active configuration changes and operational mitigations.
3. **Counterfactuals**: A 3-step algorithm (Abduction $\to$ Action $\to$ Prediction) computes what would have occurred during the incident had an alternative operational configuration been active.

## Consequences
- **Positive**: Eliminates confounding errors and false causal attributions.
- **Positive**: Enables mathematical verification of proposed remediation policies against historical incident data before live deployment.
- **Negative**: Requires structural equations to be calibrated against system mechanics.
- **Mitigation**: Pre-calibrated SCM specifications are bundled for all 12 canonical distributed systems failure modes in the Argus rules catalog.
