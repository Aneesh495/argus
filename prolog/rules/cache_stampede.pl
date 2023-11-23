/*
 * Module: argus_rule_cache_stampede
 * Purpose: Detection and abductive diagnosis of hot-key cache stampedes and thundering herds.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_rule_cache_stampede, [
    diagnose_cache_stampede/4
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../engine/hypothesis').

/**
 * diagnose_cache_stampede(+Spans, +Metrics, +Logs, -Hypotheses)
 */
diagnose_cache_stampede(Spans, Metrics, Logs, Hypotheses) :-
    findall(Hyp, (
        (   detect_stampede_from_spans(Spans, Hyp)
        ;   detect_stampede_from_metrics(Metrics, Hyp)
        ;   detect_stampede_from_logs(Logs, Hyp)
        )
    ), Raw),
    sort(Raw, Hypotheses).

detect_stampede_from_spans(Spans, Hyp) :-
    % Cache miss followed by concurrent identical database queries
    findall(Key, (
        member(Span, Spans),
        span_attribute_get(Span, 'cache.hit', false),
        span_attribute_get(Span, 'cache.key', Key)
    ), MissedKeys),
    member(HotKey, MissedKeys),
    findall(DBSpan, (
        member(DBSpan, Spans),
        span_attribute_get(DBSpan, 'db.query_parameter', HotKey)
    ), HitSpans),
    length(HitSpans, HitCount),
    HitCount >= 5,
    member(Sample, HitSpans),
    span_service(Sample, Svc),
    candidate_hypothesis(cache_stampede, Svc, 0.4, [], H0),
    evidence_add(H0, format_atom("Key ~w expired causing ~w concurrent origin DB queries", [HotKey, HitCount]), 4.5, Hyp).

detect_stampede_from_metrics(Metrics, Hyp) :-
    member(metric(MetricName, Val, Labels, _), Metrics),
    sub_atom(MetricName, _, _, _, 'cache_misses_per_second'),
    member(service=Svc, Labels),
    Val > 1000,
    candidate_hypothesis(cache_stampede, Svc, 0.35, [], H0),
    evidence_add(H0, format_atom("Sudden cache miss spike: ~w misses/sec", [Val]), 3.8, Hyp).

detect_stampede_from_logs(Logs, Hyp) :-
    member(log_record(_, _, Svc, Msg, _, _, _), Logs),
    sub_atom(Msg, _, _, _, 'Thundering herd on cache key'),
    candidate_hypothesis(cache_stampede, Svc, 0.5, [], H0),
    evidence_add(H0, "Cache proxy reported thundering herd lock contention", 5.0, Hyp).

format_atom(Format, Args, Atom) :-
    format(atom(Atom), Format, Args).
