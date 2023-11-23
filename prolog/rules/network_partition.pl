/*
 * Module: argus_rule_network_partition
 * Purpose: Detection and abductive diagnosis of asymmetric network partitions and quorum loss.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_rule_network_partition, [
    diagnose_network_partition/4
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../engine/hypothesis').

/**
 * diagnose_network_partition(+Spans, +Metrics, +Logs, -Hypotheses)
 */
diagnose_network_partition(Spans, Metrics, Logs, Hypotheses) :-
    findall(Hyp, (
        (   detect_partition_from_logs(Logs, Hyp)
        ;   detect_partition_from_metrics(Metrics, Hyp)
        ;   detect_partition_from_spans(Spans, Hyp)
        )
    ), Raw),
    sort(Raw, Hypotheses).

detect_partition_from_logs(Logs, Hyp) :-
    member(log_record(_, _, Svc, Msg, _, _, _), Logs),
    (   sub_atom(Msg, _, _, _, 'Raft election timeout')
    ;   sub_atom(Msg, _, _, _, 'Lost majority quorum')
    ;   sub_atom(Msg, _, _, _, 'Split brain detected')
    ),
    candidate_hypothesis(network_partition, Svc, 0.45, [], H0),
    evidence_add(H0, "Consensus group logged loss of majority quorum or leader election loop", 5.0, Hyp).

detect_partition_from_metrics(Metrics, Hyp) :-
    member(metric(MetricName, Val, Labels, _), Metrics),
    sub_atom(MetricName, _, _, _, 'etcd_server_has_leader'),
    member(service=Svc, Labels),
    Val =:= 0,
    candidate_hypothesis(network_partition, Svc, 0.45, [], H0),
    evidence_add(H0, "Cluster leader lost and unreachable across consensus nodes", 4.8, Hyp).

detect_partition_from_spans(Spans, Hyp) :-
    member(Span, Spans),
    span_service(Span, Svc),
    span_attribute_get(Span, 'error.type', 'NoRouteToHostException'),
    candidate_hypothesis(network_partition, Svc, 0.35, [], H0),
    evidence_add(H0, "Direct network unreachable fault encountered during inter-service RPC", 4.2, Hyp).
