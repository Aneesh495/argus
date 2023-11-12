/*
 * Module: argus_rule_queue_saturation
 * Purpose: Detection and abductive diagnosis of async message queue consumer lag and stalls.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_rule_queue_saturation, [
    diagnose_queue_saturation/4
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../engine/hypothesis').

/**
 * diagnose_queue_saturation(+Spans, +Metrics, +Logs, -Hypotheses)
 */
diagnose_queue_saturation(Spans, Metrics, Logs, Hypotheses) :-
    findall(Hyp, (
        (   detect_queue_from_spans(Spans, Hyp)
        ;   detect_queue_from_metrics(Metrics, Hyp)
        ;   detect_queue_from_logs(Logs, Hyp)
        )
    ), Raw),
    sort(Raw, Hypotheses).

detect_queue_from_spans(Spans, Hyp) :-
    member(Span, Spans),
    span_service(Span, Svc),
    span_attribute_get(Span, 'messaging.system', Broker),
    span_attribute_get(Span, 'messaging.queue_lag_ms', LagMs),
    atom_number_val(LagMs, LagNum),
    LagNum > 5000, % lag exceeds 5 seconds
    candidate_hypothesis(queue_saturation, Svc, 0.35, [], H0),
    evidence_add(H0, format_atom("Consumer lag on broker ~w exceeded ~w ms", [Broker, LagNum]), 4.0, Hyp).

detect_queue_from_metrics(Metrics, Hyp) :-
    member(metric(MetricName, Val, Labels, _), Metrics),
    (   sub_atom(MetricName, _, _, _, 'kafka_consumer_lag_records'),
        member(consumergroup=Group, Labels),
        Val > 1000
    ;   sub_atom(MetricName, _, _, _, 'rabbitmq_queue_messages_unacknowledged'),
        member(service=Group, Labels),
        Val > 500
    ),
    candidate_hypothesis(queue_saturation, Group, 0.4, [], H0),
    evidence_add(H0, format_atom("Unprocessed message backlog reached ~w records", [Val]), 3.5, Hyp).

detect_queue_from_logs(Logs, Hyp) :-
    member(log_record(_, _, Svc, Msg, _, _, _), Logs),
    (   sub_atom(Msg, _, _, _, 'CommitFailedException')
    ;   sub_atom(Msg, _, _, _, 'Consumer coordinator rebalance in progress')
    ;   sub_atom(Msg, _, _, _, 'Max poll interval exceeded')
    ),
    candidate_hypothesis(queue_saturation, Svc, 0.45, [], H0),
    evidence_add(H0, "Consumer group rebalance triggered by processing timeout", 4.2, Hyp).

format_atom(Format, Args, Atom) :-
    format(atom(Atom), Format, Args).

atom_number_val(Atom, Num) :-
    atom(Atom), !, atom_number(Atom, Num).
atom_number_val(Num, Num) :- number(Num).
