/*
 * Module: argus_critical_path
 * Purpose: Critical path analysis, slack time calculation, and latency bottleneck isolation.
 * Decomposes trace latency into active compute time vs asynchronous waiting delay.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_critical_path, [
    compute_critical_path/3,
    span_self_time/3,
    trace_bottlenecks/3,
    span_slack_time/4
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../core/graph').
:- use_module('../core/interval').
:- use_module('builder').

/**
 * compute_critical_path(+Spans, -CriticalSpanIds, -TotalCriticalDurationUs)
 * Computes the longest sequential dependency path from root to leaf in the trace.
 */
compute_critical_path(Spans, Path, TotalDuration) :-
    trace_root_spans(Spans, [Root|_]),
    span_id(Root, RootId),
    trace_leaf_spans(Spans, Leaves),
    build_span_dag(Spans, Edges),
    (   Edges == []
    ->  Path = [RootId],
        span_duration_us(Root, TotalDuration)
    ;   findall(Dur-P, (
            member(Leaf, Leaves),
            span_id(Leaf, LeafId),
            dag_critical_path(Edges, RootId, LeafId, P, Dur)
        ), CandidatePaths),
        (   CandidatePaths \= []
        ->  sort(1, @>=, CandidatePaths, [TotalDuration-Path|_])
        ;   Path = [RootId],
            span_duration_us(Root, TotalDuration)
        )
    ).

/**
 * span_self_time(+Spans, +Span, -SelfTimeUs)
 * Self time is span wall-clock duration minus the union of all child span intervals.
 */
span_self_time(Spans, Span, SelfTimeUs) :-
    span_id(Span, SId),
    span_duration_us(Span, TotalDuration),
    span_children(Spans, SId, Children),
    (   Children == []
    ->  SelfTimeUs = TotalDuration
    ;   findall(iv(S, E), (
            member(C, Children),
            span_start_us(C, S),
            span_end_us(C, E)
        ), ChildIntervals),
        span_start_us(Span, Start),
        span_end_us(Span, End),
        interval_delay_decomposition(iv(Start, End), ChildIntervals, _Queuing, ChildExec),
        % Self time is total parent duration minus active child execution
        SelfTimeUs is max(0, TotalDuration - ChildExec)
    ).

/**
 * span_slack_time(+Spans, +Span, +RootSpan, -SlackUs)
 * Computes how much Span's latency can increase before delaying the overall trace completion.
 */
span_slack_time(Spans, Span, RootSpan, SlackUs) :-
    span_end_us(RootSpan, RootEnd),
    span_end_us(Span, SpanEnd),
    span_id(Span, SId),
    span_children(Spans, SId, Children),
    (   Children == []
    ->  SlackUs is max(0, RootEnd - SpanEnd)
    ;   findall(CStart, (member(C, Children), span_start_us(C, CStart)), Starts),
        min_list(Starts, EarliestChildStart),
        SlackUs is max(0, EarliestChildStart - SpanEnd)
    ).

/**
 * trace_bottlenecks(+Spans, +TopN, -Bottlenecks)
 * Identifies and ranks top N spans contributing highest self-time or error status.
 */
trace_bottlenecks(Spans, TopN, Bottlenecks) :-
    findall(RankKey-Span, (
        member(Span, Spans),
        span_self_time(Spans, Span, SelfUs),
        (span_is_error(Span) -> ErrorPenalty = 10000000 ; ErrorPenalty = 0),
        Score is SelfUs + ErrorPenalty,
        RankKey is -Score
    ), ScoredSpans),
    sort(1, @=<, ScoredSpans, Sorted),
    take_first_n(TopN, Sorted, TopEntries),
    findall(bottleneck(SId, Svc, Name, SelfUs, IsErr), (
        member(_NegScore-Span, TopEntries),
        span_id(Span, SId),
        span_service(Span, Svc),
        span_name(Span, Name),
        span_self_time(Spans, Span, SelfUs),
        (span_is_error(Span) -> IsErr = true ; IsErr = false)
    ), Bottlenecks).

take_first_n(0, _, []) :- !.
take_first_n(_, [], []) :- !.
take_first_n(N, [H|T], [H|Rest]) :-
    N > 0,
    N1 is N - 1,
    take_first_n(N1, T, Rest).
