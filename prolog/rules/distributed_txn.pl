/*
 * Module: argus_rule_distributed_txn
 * Purpose: Detection and abductive diagnosis of two-phase commit (2PC) and saga transaction stalls.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_rule_distributed_txn, [
    diagnose_distributed_txn/4
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../engine/hypothesis').

/**
 * diagnose_distributed_txn(+Spans, +Metrics, +Logs, -Hypotheses)
 */
diagnose_distributed_txn(Spans, Metrics, Logs, Hypotheses) :-
    findall(Hyp, (
        (   detect_txn_from_spans(Spans, Hyp)
        ;   detect_txn_from_logs(Logs, Hyp)
        ;   detect_txn_from_metrics(Metrics, Hyp)
        )
    ), Raw),
    sort(Raw, Hypotheses).

detect_txn_from_spans(Spans, Hyp) :-
    member(Span, Spans),
    span_service(Span, Svc),
    (   span_attribute_get(Span, 'saga.status', 'COMPENSATING_ABORT')
    ;   span_attribute_get(Span, '2pc.phase', 'PREPARE_TIMEOUT')
    ),
    candidate_hypothesis(distributed_transaction_timeout, Svc, 0.4, [], H0),
    evidence_add(H0, "Distributed transaction coordinator aborted during participant prepare phase", 4.5, Hyp).

detect_txn_from_logs(Logs, Hyp) :-
    member(log_record(_, Level, Svc, Msg, _, _, _), Logs),
    (Level = 'ERROR' ; Level = 'FATAL'),
    (   sub_atom(Msg, _, _, _, '2PC participant timeout')
    ;   sub_atom(Msg, _, _, _, 'Saga compensation failed')
    ;   sub_atom(Msg, _, _, _, 'HeuristicHazardException')
    ),
    candidate_hypothesis(distributed_transaction_timeout, Svc, 0.5, [], H0),
    evidence_add(H0, "Heuristic mixed transaction state logged across distributed branches", 5.0, Hyp).

detect_txn_from_metrics(Metrics, Hyp) :-
    member(metric(MetricName, Val, Labels, _), Metrics),
    sub_atom(MetricName, _, _, _, 'distributed_txns_aborted_total'),
    member(service=Svc, Labels),
    Val > 10,
    candidate_hypothesis(distributed_transaction_timeout, Svc, 0.35, [], H0),
    evidence_add(H0, format_atom("Surge in distributed transaction aborts: ~w", [Val]), 3.8, Hyp).

format_atom(Format, Args, Atom) :-
    format(atom(Atom), Format, Args).
