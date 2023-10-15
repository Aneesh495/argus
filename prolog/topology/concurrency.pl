/*
 * Module: argus_concurrency
 * Purpose: Analyzes concurrent execution fan-out, fork-join synchronizations, and tail latency risk.
 * Implements statistical tail latency amplification formulas and parallel branch identification.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_concurrency, [
    find_concurrent_spans/2,
    fanout_degree/3,
    fork_join_patterns/2,
    tail_latency_amplification_risk/3
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../core/interval').
:- use_module('builder').

/**
 * find_concurrent_spans(+Spans, -ConcurrentPairs)
 * Finds all pairs of spans that execute overlapping wall-clock intervals.
 */
find_concurrent_spans(Spans, Pairs) :-
    findall(pair(S1Id, S2Id), (
        member(S1, Spans),
        member(S2, Spans),
        span_id(S1, S1Id),
        span_id(S2, S2Id),
        S1Id @< S2Id,
        span_start_us(S1, Start1),
        span_end_us(S1, End1),
        span_start_us(S2, Start2),
        span_end_us(S2, End2),
        interval_concurrency(iv(Start1, End1), iv(Start2, End2))
    ), Pairs).

/**
 * fanout_degree(+Spans, +ParentId, -Degree)
 * Counts the number of direct child calls launched by ParentId.
 */
fanout_degree(Spans, ParentId, Degree) :-
    span_children(Spans, ParentId, Children),
    length(Children, Degree).

/**
 * fork_join_patterns(+Spans, -ForkJoinList)
 * Identifies parents with fanout degree >= 2 where children execute concurrently.
 */
fork_join_patterns(Spans, Patterns) :-
    findall(fork_join(ParentId, ParentService, Fanout, ChildrenIds), (
        member(Parent, Spans),
        span_id(Parent, ParentId),
        span_service(Parent, ParentService),
        span_children(Spans, ParentId, Children),
        length(Children, Fanout),
        Fanout >= 2,
        findall(CId, (member(C, Children), span_id(C, CId)), ChildrenIds),
        children_have_concurrency(Children)
    ), Patterns).

children_have_concurrency(Children) :-
    member(C1, Children),
    member(C2, Children),
    C1 \== C2,
    span_start_us(C1, S1),
    span_end_us(C1, E1),
    span_start_us(C2, S2),
    span_end_us(C2, E2),
    interval_concurrency(iv(S1, E1), iv(S2, E2)),
    !.

/**
 * tail_latency_amplification_risk(+FanoutN, +TailPercentile, -AmplifiedRisk)
 * Computes probability that at least one parallel branch experiences a tail delay:
 * AmplifiedRisk = 1 - (1 - (1 - TailPercentile/100))^FanoutN.
 * For example, with Fanout = 10 and 95th percentile (TailPercentile = 95),
 * P(single <= p95) = 0.95.
 * P(all <= p95) = 0.95^10 = 0.5987.
 * AmplifiedRisk = 1 - 0.5987 = 0.4013 (40.1%).
 */
tail_latency_amplification_risk(FanoutN, TailPercentile, AmplifiedRisk) :-
    FanoutN > 0,
    TailProb is (100.0 - TailPercentile) / 100.0,
    SuccessProb is 1.0 - TailProb,
    AllSuccessProb is SuccessProb ** FanoutN,
    AmplifiedRisk is 1.0 - AllSuccessProb.
