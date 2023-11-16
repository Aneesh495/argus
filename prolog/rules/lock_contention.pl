/*
 * Module: argus_rule_lock_contention
 * Purpose: Detection and abductive diagnosis of database lock contention and deadlocks.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_rule_lock_contention, [
    diagnose_lock_contention/4
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../engine/hypothesis').

/**
 * diagnose_lock_contention(+Spans, +Metrics, +Logs, -Hypotheses)
 */
diagnose_lock_contention(Spans, Metrics, Logs, Hypotheses) :-
    findall(Hyp, (
        (   detect_lock_from_spans(Spans, Hyp)
        ;   detect_lock_from_metrics(Metrics, Hyp)
        ;   detect_lock_from_logs(Logs, Hyp)
        )
    ), Raw),
    sort(Raw, Hypotheses).

detect_lock_from_spans(Spans, Hyp) :-
    member(Span, Spans),
    span_service(Span, Svc),
    (   span_attribute_get(Span, 'db.lock_wait_ms', LockMs),
        atom_number_val(LockMs, LockNum),
        LockNum > 3000
    ;   span_attribute_get(Span, 'error.message', Msg),
        (sub_atom(Msg, _, _, _, 'deadlock') ; sub_atom(Msg, _, _, _, 'Lock wait timeout'))
    ),
    candidate_hypothesis(database_lock_contention, Svc, 0.4, [], H0),
    evidence_add(H0, "Database query blocked on conflicting row/table lock", 4.2, Hyp).

detect_lock_from_metrics(Metrics, Hyp) :-
    member(metric(MetricName, Val, Labels, _), Metrics),
    (   sub_atom(MetricName, _, _, _, 'pg_stat_activity_waiting_locks'),
        member(service=Svc, Labels),
        Val > 10
    ;   sub_atom(MetricName, _, _, _, 'mysql_innodb_row_lock_waits'),
        member(service=Svc, Labels),
        Val > 50
    ),
    candidate_hypothesis(database_lock_contention, Svc, 0.4, [], H0),
    evidence_add(H0, format_atom("High concurrent lock waiting threads: ~w", [Val]), 3.8, Hyp).

detect_lock_from_logs(Logs, Hyp) :-
    member(log_record(_, Level, Svc, Msg, _, _, _), Logs),
    (Level = 'ERROR' ; Level = 'WARN'),
    (   sub_atom(Msg, _, _, _, 'deadlock detected')
    ;   sub_atom(Msg, _, _, _, 'LockWaitTimeoutException')
    ;   sub_atom(Msg, _, _, _, 'SerializationFailure')
    ),
    candidate_hypothesis(database_lock_contention, Svc, 0.5, [], H0),
    evidence_add(H0, "Database engine logged formal deadlock cycle", 5.0, Hyp).

format_atom(Format, Args, Atom) :-
    format(atom(Atom), Format, Args).

atom_number_val(Atom, Num) :-
    atom(Atom), !, atom_number(Atom, Num).
atom_number_val(Num, Num) :- number(Num).
