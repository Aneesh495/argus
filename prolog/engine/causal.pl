/*
 * Module: argus_causal
 * Purpose: Structural Causal Models (SCMs) and Judea Pearl's do-calculus.
 * Evaluates causal graph surgeries, interventions do(X=x), and Average Causal Effects (ACE).
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_causal, [
    scm_create/4,
    scm_intervene/3,
    scm_evaluate/3,
    scm_causal_effect/5,
    scm_variable_get/3
]).

:- use_module(library(lists)).

/**
 * scm_create(+Variables, +Equations, +ExogenousDist, -SCM)
 * Constructs a Structural Causal Model:
 * scm(Variables, Equations, ExogenousDist)
 * Equations is a list of eq(Var, Expression).
 */
scm_create(Variables, Equations, Exogenous, scm(Variables, Equations, Exogenous)).

/**
 * scm_intervene(+SCMIn, +Interventions, -SCMOut)
 * Implements Pearl's do-calculus operator: do(X = Constant).
 * Cuts incoming structural dependencies to X and replaces them with an invariant constant.
 */
scm_intervene(scm(Vars, Equations, Exog), Interventions, scm(Vars, NewEquations, Exog)) :-
    foldl(apply_single_intervention, Interventions, Equations, NewEquations).

apply_single_intervention(do(Var, Value), EqsIn, [eq(Var, const(Value))|Filtered]) :-
    delete_equation(Var, EqsIn, Filtered).

delete_equation(Var, [eq(Var, _)|Rest], Rest) :- !.
delete_equation(Var, [H|Rest], [H|Filtered]) :-
    delete_equation(Var, Rest, Filtered).
delete_equation(_, [], []).

/**
 * scm_evaluate(+SCM, +ExogenousValues, -EndogenousState)
 * Forward evaluates structural equations in topological order to determine equilibrium state.
 */
scm_evaluate(scm(Vars, Equations, _), ExogVals, State) :-
    eval_equations(Vars, Equations, ExogVals, [], State).

eval_equations([], _, _, State, State).
eval_equations([V|RestVars], Equations, ExogVals, AccState, FinalState) :-
    (   member(eq(V, Expr), Equations)
    ->  eval_expr(Expr, AccState, ExogVals, Val),
        NewState = [V=Val|AccState]
    ;   member(V=ExVal, ExogVals)
    ->  NewState = [V=ExVal|AccState]
    ;   NewState = [V=0|AccState]
    ),
    eval_equations(RestVars, Equations, ExogVals, NewState, FinalState).

eval_expr(const(Val), _, _, Val) :- !.
eval_expr(var(V), State, Exog, Val) :-
    !,
    (   member(V=Val, State)
    ;   member(V=Val, Exog)
    ;   Val = 0
    ), !.
eval_expr(add(E1, E2), State, Exog, Val) :-
    !,
    eval_expr(E1, State, Exog, V1),
    eval_expr(E2, State, Exog, V2),
    Val is V1 + V2.
eval_expr(mult(E1, E2), State, Exog, Val) :-
    !,
    eval_expr(E1, State, Exog, V1),
    eval_expr(E2, State, Exog, V2),
    Val is V1 * V2.
eval_expr(min(E1, E2), State, Exog, Val) :-
    !,
    eval_expr(E1, State, Exog, V1),
    eval_expr(E2, State, Exog, V2),
    Val is min(V1, V2).
eval_expr(max(E1, E2), State, Exog, Val) :-
    !,
    eval_expr(E1, State, Exog, V1),
    eval_expr(E2, State, Exog, V2),
    Val is max(V1, V2).
eval_expr(step(Cond, ETrue, EFalse), State, Exog, Val) :-
    !,
    (   eval_cond(Cond, State, Exog)
    ->  eval_expr(ETrue, State, Exog, Val)
    ;   eval_expr(EFalse, State, Exog, Val)
    ).
eval_expr(Val, _, _, Val) :- number(Val), !.

eval_cond(gt(E1, E2), State, Exog) :-
    eval_expr(E1, State, Exog, V1),
    eval_expr(E2, State, Exog, V2),
    V1 > V2.
eval_cond(lt(E1, E2), State, Exog) :-
    eval_expr(E1, State, Exog, V1),
    eval_expr(E2, State, Exog, V2),
    V1 < V2.

scm_variable_get(State, Var, Val) :-
    member(Var=Val, State), !.

/**
 * scm_causal_effect(+SCM, +Intervention1, +Intervention0, +OutcomeVar, -CausalEffect)
 * Computes Average Causal Effect (ACE): Outcome(do(Int1)) - Outcome(do(Int0)).
 */
scm_causal_effect(SCM, Int1, Int0, OutcomeVar, Effect) :-
    scm_intervene(SCM, [Int1], SCM1),
    scm_intervene(SCM, [Int0], SCM0),
    scm_evaluate(SCM1, [], State1),
    scm_evaluate(SCM0, [], State0),
    scm_variable_get(State1, OutcomeVar, Y1),
    scm_variable_get(State0, OutcomeVar, Y0),
    Effect is Y1 - Y0.
