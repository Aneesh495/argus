/*
 * Module: argus_rule_thread_exhaustion
 * Purpose: Detection and abductive diagnosis of thread pool and worker queue exhaustion.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_rule_thread_exhaustion, [
    diagnose_thread_exhaustion/4
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../engine/hypothesis').

/**
 * diagnose_thread_exhaustion(+Spans, +Metrics, +Logs, -Hypotheses)
 */
diagnose_thread_exhaustion(Spans, Metrics, Logs, Hypotheses) :-
    findall(Hyp, (
        (   detect_threads_from_metrics(Metrics, Hyp)
        ;   detect_threads_from_logs(Logs, Hyp)
        ;   detect_threads_from_spans(Spans, Hyp)
        )
    ), Raw),
    sort(Raw, Hypotheses).

detect_threads_from_metrics(Metrics, Hyp) :-
    member(metric(MetricName, Val, Labels, _), Metrics),
    (   sub_atom(MetricName, _, _, _, 'threadpool_active_threads'),
        member(service=Svc, Labels),
        Val >= 0.98 % 98% thread utilization
    ;   sub_atom(MetricName, _, _, _, 'jvm_threads_blocked_count'),
        member(service=Svc, Labels),
        Val > 100
    ),
    candidate_hypothesis(thread_pool_exhaustion, Svc, 0.4, [], H0),
    evidence_add(H0, "Worker thread pool reached 100% capacity", 4.0, Hyp).

detect_threads_from_logs(Logs, Hyp) :-
    member(log_record(_, Level, Svc, Msg, _, _, _), Logs),
    (Level = 'ERROR' ; Level = 'FATAL'),
    (   sub_atom(Msg, _, _, _, 'RejectedExecutionException')
    ;   sub_atom(Msg, _, _, _, 'Thread pool exhausted')
    ;   sub_atom(Msg, _, _, _, 'all threads are busy')
    ),
    candidate_hypothesis(thread_pool_exhaustion, Svc, 0.5, [], H0),
    evidence_add(H0, "Explicit task rejection logged due to full thread queue", 5.0, Hyp).

detect_threads_from_spans(Spans, Hyp) :-
    member(Span, Spans),
    span_service(Span, Svc),
    span_attribute_get(Span, 'thread.queue_wait_ms', QueueMs),
    atom_number_val(QueueMs, QNum),
    QNum > 2000, % over 2s waiting in executor queue
    candidate_hypothesis(thread_pool_exhaustion, Svc, 0.35, [], H0),
    evidence_add(H0, format_atom("Task queued for ~w ms before worker thread allocation", [QNum]), 3.8, Hyp).

format_atom(Format, Args, Atom) :-
    format(atom(Atom), Format, Args).

atom_number_val(Atom, Num) :-
    atom(Atom), !, atom_number(Atom, Num).
atom_number_val(Num, Num) :- number(Num).
