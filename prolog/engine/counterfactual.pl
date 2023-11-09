/*
 * Module: argus_counterfactual
 * Purpose: Pearl's 3-step counterfactual reasoning engine (Abduction, Action, Prediction).
 * Evaluates what-if policy queries on observed incident telemetry.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_counterfactual, [
    counterfactual_query/5,
    abduce_exogenous_noise/3,
    evaluate_counterfactual_world/4
]).

:- use_module(library(lists)).
:- use_module('causal').

/**
 * counterfactual_query(+SCM, +ObservedEvidence, +Intervention, +TargetVar, -CounterfactualValue)
 * Executes Judea Pearl's three-step counterfactual evaluation:
 * Step 1: Abduce exogenous noise variables U consistent with ObservedEvidence.
 * Step 2: Perform causal surgery do(Intervention) on SCM equations.
 * Step 3: Forward predict TargetVar in the modified submodel using abduced noise U.
 */
counterfactual_query(SCM, ObservedEvidence, Intervention, TargetVar, CounterfactualVal) :-
    % Step 1: Abduction
    abduce_exogenous_noise(SCM, ObservedEvidence, NoiseU),
    % Step 2: Action (Intervention surgery)
    scm_intervene(SCM, [Intervention], SCM_Intervened),
    % Step 3: Prediction
    scm_evaluate(SCM_Intervened, NoiseU, CounterfactualState),
    scm_variable_get(CounterfactualState, TargetVar, CounterfactualVal).

/**
 * abduce_exogenous_noise(+SCM, +ObservedEvidence, -NoiseU)
 * Computes background noise terms that reconcile observed state with structural equations.
 */
abduce_exogenous_noise(scm(Vars, Equations, ExogSpec), Observed, NoiseU) :-
    findall(UVar=UVal, (
        member(UVar, ExogSpec),
        (   member(UVar=ObsVal, Observed)
        ->  UVal = ObsVal
        ;   derive_noise_term(UVar, Vars, Equations, Observed, DerivedVal)
        ->  UVal = DerivedVal
        ;   UVal = 0
        )
    ), NoiseU).

derive_noise_term(UVar, _, Equations, Observed, Noise) :-
    member(eq(TargetVar, add(Expr, var(UVar))), Equations),
    member(TargetVar=ObsTarget, Observed),
    eval_deterministic_part(Expr, Observed, DetVal),
    Noise is ObsTarget - DetVal.

eval_deterministic_part(const(V), _, V) :- !.
eval_deterministic_part(var(V), State, Val) :-
    member(V=Val, State), !.
eval_deterministic_part(mult(E1, E2), State, Val) :-
    eval_deterministic_part(E1, State, V1),
    eval_deterministic_part(E2, State, V2),
    Val is V1 * V2.
eval_deterministic_part(V, _, V) :- number(V), !.

/**
 * evaluate_counterfactual_world(+SCM, +Interventions, +NoiseU, -WorldState)
 */
evaluate_counterfactual_world(SCM, Interventions, NoiseU, State) :-
    scm_intervene(SCM, Interventions, ModSCM),
    scm_evaluate(ModSCM, NoiseU, State).
