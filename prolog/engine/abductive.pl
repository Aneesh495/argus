/*
 * Module: argus_abductive
 * Purpose: Abductive Logic Programming (ALP) meta-interpreter with integrity constraints.
 * Given observations O and background rules B, finds minimal consistent hypotheses Delta
 * explaining all symptoms without violating integrity constraints.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_abductive, [
    abduce/3,
    abduce_all/3,
    abduce_minimal/4,
    register_abducible/2,
    register_ic/1,
    clear_abductive_kb/0
]).

:- use_module(library(lists)).

:- dynamic abducible_spec/2.
:- dynamic integrity_constraint/1.

:- meta_predicate abduce(:, +, -).
:- meta_predicate abduce_all(:, +, -).
:- meta_predicate abduce_minimal(:, +, -, -).

/**
 * register_abducible(+Functor, +PriorCost)
 * Registers an abducible predicate pattern with associated Occam penalty cost.
 */
register_abducible(Functor, Cost) :-
    assertz(abducible_spec(Functor, Cost)).

/**
 * register_ic(+ConstraintClause)
 * Registers an integrity constraint: ic(Condition) which must not be satisfied.
 */
register_ic(Condition) :-
    assertz(integrity_constraint(Condition)).

clear_abductive_kb :-
    retractall(abducible_spec(_, _)),
    retractall(integrity_constraint(_)).

/**
 * abduce(+Observation, +DeltaIn, -DeltaOut)
 * Proves Observation against background theory, abducing hypotheses into Delta.
 */
abduce(M:Goal, DeltaIn, DeltaOut) :-
    abduce_m(Goal, M, DeltaIn, DeltaOut).

abduce_m(GoalRaw, M, DeltaIn, DeltaOut) :-
    strip_module(GoalRaw, Mod, Goal),
    (   Goal == true
    ->  DeltaOut = DeltaIn
    ;   Goal = (A, B)
    ->  abduce_m(A, M, DeltaIn, DeltaMid),
        abduce_m(B, M, DeltaMid, DeltaOut)
    ;   member(hypothesis(Goal, _), DeltaIn)
    ->  DeltaOut = DeltaIn
    ;   is_abducible(Goal, Cost)
    ->  NewDelta = [hypothesis(Goal, Cost)|DeltaIn],
        check_integrity_constraints(NewDelta),
        DeltaOut = NewDelta
    ;   (   clause(Mod:Goal, Body)
        ;   clause(M:Goal, Body)
        ;   clause(user:Goal, Body)
        ),
        abduce_m(Body, M, DeltaIn, DeltaOut)
    ).

/**
 * abduce_all(+Observation, +DeltaIn, -Solutions)
 * Collects all valid abductive explanations.
 */
abduce_all(M:Observation, DeltaIn, Solutions) :-
    findall(Delta, (abduce_m(Observation, M, DeltaIn, RawDelta), sort(RawDelta, Delta)), Unsorted),
    sort(Unsorted, Solutions).

/**
 * abduce_minimal(+Observation, +DeltaIn, -BestExplanation, -TotalCost)
 * Finds the minimum-cost (most parsimonious) explanation using branch-and-bound.
 */
abduce_minimal(M:Observation, DeltaIn, BestExplanation, MinCost) :-
    abduce_all(M:Observation, DeltaIn, Solutions),
    Solutions \= [],
    score_solutions(Solutions, Scored),
    sort(1, @=<, Scored, [MinCost-BestExplanation|_]).

score_solutions([], []).
score_solutions([Delta|Rest], [Cost-Delta|ScoredRest]) :-
    compute_delta_cost(Delta, 0, Cost),
    score_solutions(Rest, ScoredRest).

compute_delta_cost([], Cost, Cost).
compute_delta_cost([hypothesis(_, C)|T], Acc, Total) :-
    NewAcc is Acc + C,
    compute_delta_cost(T, NewAcc, Total).

is_abducible(Goal, Cost) :-
    functor(Goal, Name, Arity),
    abducible_spec(Name/Arity, Cost).

check_integrity_constraints(Delta) :-
    \+ (
        integrity_constraint(IC),
        ic_violated(IC, Delta)
    ).

ic_violated(ic(Conditions), Delta) :-
    eval_conditions(Conditions, Delta).

eval_conditions(true, _) :- !.
eval_conditions((A, B), Delta) :-
    !,
    eval_conditions(A, Delta),
    eval_conditions(B, Delta).
eval_conditions(hyp(H), Delta) :-
    !,
    member(hypothesis(H, _), Delta).
eval_conditions(Goal, Delta) :-
    clause(Goal, Body),
    eval_conditions(Body, Delta).
