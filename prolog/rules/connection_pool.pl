/*
 * Module: argus_rule_connection_pool
 * Purpose: Detection and abductive diagnosis of connection pool starvation and exhaustion.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_rule_connection_pool, [
    diagnose_connection_pool/4
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../engine/hypothesis').

/**
 * diagnose_connection_pool(+Spans, +Metrics, +Logs, -Hypotheses)
 */
diagnose_connection_pool(Spans, Metrics, Logs, Hypotheses) :-
    findall(Hyp, (
        (   detect_pool_from_spans(Spans, Hyp)
        ;   detect_pool_from_metrics(Metrics, Hyp)
        ;   detect_pool_from_logs(Logs, Hyp)
        )
    ), RawHypotheses),
    sort(RawHypotheses, Hypotheses).

detect_pool_from_spans(Spans, Hyp) :-
    member(Span, Spans),
    span_service(Span, Svc),
    (   span_attribute_get(Span, 'pool.wait_time_ms', WaitMs),
        atom_number_val(WaitMs, WaitNum),
        span_duration_us(Span, DurUs),
        WaitUs is WaitNum * 1000,
        WaitUs >= 0.7 * DurUs,
        WaitUs > 50000 % over 50ms waiting for connection
    ;   span_attribute_get(Span, 'error.message', Msg),
        sub_atom(Msg, _, _, _, 'ConnectionPoolTimeout')
    ),
    candidate_hypothesis(connection_pool_starvation, Svc, 0.4, [], H0),
    evidence_add(H0, "Connection acquisition wait time dominated query latency (>70%)", 4.0, H1),
    evidence_add(H1, "Connection pool queue saturation detected", 2.5, Hyp).

detect_pool_from_metrics(Metrics, Hyp) :-
    member(metric(MetricName, Val, Labels, _), Metrics),
    (   sub_atom(MetricName, _, _, _, 'pool_active_connections'),
        member(service=Svc, Labels),
        Val >= 0.95 % pool utilization >= 95%
    ;   sub_atom(MetricName, _, _, _, 'db_connections_exhausted'),
        member(service=Svc, Labels),
        Val > 0
    ),
    candidate_hypothesis(connection_pool_starvation, Svc, 0.4, [], H0),
    evidence_add(H0, "Pool active connections pinned near 100% capacity", 3.8, Hyp).

detect_pool_from_logs(Logs, Hyp) :-
    member(log_record(_, Level, Svc, Msg, _, _, _), Logs),
    (Level = 'ERROR' ; Level = 'WARN'),
    (   sub_atom(Msg, _, _, _, 'Timeout waiting for connection from pool')
    ;   sub_atom(Msg, _, _, _, 'ConnectionPoolTimeoutException')
    ;   sub_atom(Msg, _, _, _, 'HikariPool - Connection is not available')
    ),
    candidate_hypothesis(connection_pool_starvation, Svc, 0.45, [], H0),
    evidence_add(H0, "Explicit pool exhaustion exception logged in service runtime", 5.0, Hyp).

atom_number_val(Atom, Num) :-
    atom(Atom), !, atom_number(Atom, Num).
atom_number_val(Num, Num) :- number(Num).
