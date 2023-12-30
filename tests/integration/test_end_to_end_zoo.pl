/*
 * Integration tests for the Argus Incident Zoo:
 * Evaluates end-to-end diagnosis and remediation against curated real-world incident scenarios.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(test_end_to_end_zoo, [
    run_zoo_integration_tests/0
]).

:- use_module(library(plunit)).
:- use_module(library(http/json)).
:- use_module('../../prolog/argus').

run_zoo_integration_tests :-
    run_tests([incident_zoo]).

:- begin_tests(incident_zoo).

test(incident_01_retry_storm) :-
    test_incident('01_retry_storm_cascade', retry_storm, 'api-gateway').

test(incident_02_connection_pool) :-
    test_incident('02_connection_pool_starvation', connection_pool_starvation, 'inventory-db').

test(incident_03_kafka_lag) :-
    test_incident('03_kafka_consumer_lag', queue_saturation, 'order-consumer').

test(incident_04_gc_pause) :-
    test_incident('04_gc_pause_heartbeat_timeout', gc_pause, 'auth-service').

test(incident_05_thread_exhaustion) :-
    test_incident('05_thread_pool_exhaustion', thread_pool_exhaustion, 'search-service').

test(incident_06_postgres_deadlock) :-
    test_incident('06_postgres_lock_deadlock', database_lock_contention, 'postgres-db').

test(incident_07_circuit_breaker) :-
    test_incident('07_circuit_breaker_flutter', circuit_breaker_flapping, 'recommendation-service').

test(incident_08_cfs_throttling) :-
    test_incident('08_cfs_cpu_quota_throttling', cgroup_resource_throttling, 'image-processing-service').

test(incident_09_cache_stampede) :-
    test_incident('09_cache_stampede_thundering_herd', cache_stampede, 'catalog-db').

test(incident_10_raft_partition) :-
    test_incident('10_asymmetric_partition_raft', network_partition, 'consensus-etcd').

:- end_tests(incident_zoo).

test_incident(IncidentId, ExpectedFault, ExpectedService) :-
    format(atom(TraceFile), "data/zoo/~w/trace.json", [IncidentId]),
    format(atom(MetricsFile), "data/zoo/~w/metrics.prom", [IncidentId]),
    format(atom(LogsFile), "data/zoo/~w/logs.jsonl", [IncidentId]),
    
    argus_full_pipeline(TraceFile, MetricsFile, LogsFile, Explanation, RemediationActions),
    Explanation = explanation(DiagnosedFault, DiagnosedSvc, Confidence, _, _),
    
    DiagnosedFault = ExpectedFault,
    DiagnosedSvc = ExpectedService,
    Confidence > 0.70,
    RemediationActions \= [],
    !.
