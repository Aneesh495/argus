/*
 * Module: argus_diagnose
 * Purpose: Master diagnostic coordinator combining all specialized distributed failure rules.
 * Runs abductive hypothesis generation across traces, metrics, and logs.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_diagnose, [
    diagnose_incident/4,
    diagnose_incident_with_explanation/5
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../topology/builder').
:- use_module('../engine/hypothesis').
:- use_module('../engine/explanation').

:- use_module('retry_storm').
:- use_module('connection_pool').
:- use_module('queue_saturation').
:- use_module('gc_pause').
:- use_module('thread_exhaustion').
:- use_module('lock_contention').
:- use_module('circuit_breaker').
:- use_module('memory_pressure').
:- use_module('cache_stampede').
:- use_module('network_partition').
:- use_module('disk_io_stall').
:- use_module('distributed_txn').

/**
 * diagnose_incident(+Spans, +Metrics, +Logs, -RankedHypotheses)
 * Aggregates hypotheses from all domain rules and ranks them by Bayesian posterior confidence.
 */
diagnose_incident(Spans, Metrics, Logs, Ranked) :-
    diagnose_retry_storm(Spans, Metrics, Logs, H1),
    diagnose_connection_pool(Spans, Metrics, Logs, H2),
    diagnose_queue_saturation(Spans, Metrics, Logs, H3),
    diagnose_gc_pause(Spans, Metrics, Logs, H4),
    diagnose_thread_exhaustion(Spans, Metrics, Logs, H5),
    diagnose_lock_contention(Spans, Metrics, Logs, H6),
    diagnose_circuit_breaker(Spans, Metrics, Logs, H7),
    diagnose_memory_pressure(Spans, Metrics, Logs, H8),
    diagnose_cache_stampede(Spans, Metrics, Logs, H9),
    diagnose_network_partition(Spans, Metrics, Logs, H10),
    diagnose_disk_io_stall(Spans, Metrics, Logs, H11),
    diagnose_distributed_txn(Spans, Metrics, Logs, H12),
    
    append([H1, H2, H3, H4, H5, H6, H7, H8, H9, H10, H11, H12], AllHypotheses),
    rank_hypotheses(AllHypotheses, Ranked).

/**
 * diagnose_incident_with_explanation(+Spans, +Metrics, +Logs, -RankedHypotheses, -Explanation)
 * Diagnoses incident and constructs detailed root cause explanation with propagation path.
 */
diagnose_incident_with_explanation(Spans, Metrics, Logs, Ranked, Explanation) :-
    diagnose_incident(Spans, Metrics, Logs, Ranked),
    build_service_topology(Spans, TopologyEdges),
    (   Ranked = [ranked(_, Conf, cand_hyp(Fault, Svc, _, EvList))|_]
    ->  explain_propagation_chain(TopologyEdges, Svc, [Chain|_]),
        explanation_create(Fault, Svc, Conf, Chain, EvList, Explanation)
    ;   explanation_create(unknown_anomaly, 'none', 0.0, [], [], Explanation)
    ).
