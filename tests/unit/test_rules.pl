/*
 * Unit tests for Argus failure mode rules and master diagnostic coordinator.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(test_rules, [
    run_rules_tests/0
]).

:- use_module(library(plunit)).
:- use_module('../../prolog/core/types').
:- use_module('../../prolog/engine/hypothesis').
:- use_module('../../prolog/engine/explanation').
:- use_module('../../prolog/rules/retry_storm').
:- use_module('../../prolog/rules/connection_pool').
:- use_module('../../prolog/rules/queue_saturation').
:- use_module('../../prolog/rules/gc_pause').
:- use_module('../../prolog/rules/thread_exhaustion').
:- use_module('../../prolog/rules/lock_contention').
:- use_module('../../prolog/rules/circuit_breaker').
:- use_module('../../prolog/rules/memory_pressure').
:- use_module('../../prolog/rules/cache_stampede').
:- use_module('../../prolog/rules/network_partition').
:- use_module('../../prolog/rules/disk_io_stall').
:- use_module('../../prolog/rules/distributed_txn').
:- use_module('../../prolog/rules/diagnose').

run_rules_tests :-
    run_tests([rules_retry, rules_pool, rules_gc, rules_lock, rules_master]).

:- begin_tests(rules_retry).

test(retry_storm_detection) :-
    span_create('t1', 'p1', '', 'gateway', 'checkout', 0, 1000, 2, [], Root),
    % 3 repeated calls to payment-service charge endpoint with errors
    span_create('t1', 'c1', 'p1', 'payment-service', 'charge', 50, 200, 2, [], C1),
    span_create('t1', 'c2', 'p1', 'payment-service', 'charge', 250, 450, 2, [], C2),
    span_create('t1', 'c3', 'p1', 'payment-service', 'charge', 500, 900, 2, [], C3),
    Spans = [Root, C1, C2, C3],
    
    diagnose_retry_storm(Spans, [], [], Hypotheses),
    length(Hypotheses, 1),
    Hypotheses = [Hyp],
    Hyp = cand_hyp(retry_storm, 'gateway', _, EvList),
    length(EvList, 3),
    !.

:- end_tests(rules_retry).

:- begin_tests(rules_pool).

test(connection_pool_starvation_detection) :-
    % Query took 100,000 us (100 ms), but 85,000 us was spent waiting for a pool connection!
    span_create('t1', 's1', 'root', 'order-db', 'SELECT * FROM orders', 0, 100000, 1,
                ['pool.wait_time_ms'=85], S),
    diagnose_connection_pool([S], [], [], Hypotheses),
    Hypotheses = [cand_hyp(connection_pool_starvation, 'order-db', _, _)],
    !.

:- end_tests(rules_pool).

:- begin_tests(rules_gc).

test(gc_pause_from_metrics) :-
    Metrics = [metric('jvm_gc_pause_seconds_sum', 2.5, [service='auth-service'], 1670000000)],
    diagnose_gc_pause([], Metrics, [], Hypotheses),
    Hypotheses = [cand_hyp(gc_pause, 'auth-service', _, _)],
    !.

:- end_tests(rules_gc).

:- begin_tests(rules_lock).

test(deadlock_from_logs) :-
    Logs = [log_record(1670000000, 'ERROR', 'postgres-db', 'deadlock detected: Process 42 waits for ShareLock', 't1', 's1', [])],
    diagnose_lock_contention([], [], Logs, Hypotheses),
    Hypotheses = [cand_hyp(database_lock_contention, 'postgres-db', _, _)],
    !.

:- end_tests(rules_lock).

:- begin_tests(rules_master).

test(master_diagnose_and_explanation_synthesis) :-
    span_create('t1', 'gw', '', 'api-gateway', 'handleRequest', 0, 150000, 2, [], GW),
    span_create('t1', 'ord', 'gw', 'order-svc', 'submitOrder', 1000, 140000, 2, [], Ord),
    span_create('t1', 'db', 'ord', 'order-db', 'INSERT orders', 2000, 130000, 2,
                ['pool.wait_time_ms'=110], DB), % 110ms waiting for DB connection
    Spans = [GW, Ord, DB],
    Metrics = [metric('pool_active_connections', 1.0, [service='order-db'], 1670000000)],
    Logs = [log_record(1670000000, 'ERROR', 'order-db', 'ConnectionPoolTimeoutException', 't1', 'db', [])],
    
    diagnose_incident_with_explanation(Spans, Metrics, Logs, Ranked, Explanation),
    Ranked = [ranked(1, Conf, TopHyp)|_],
    TopHyp = cand_hyp(connection_pool_starvation, 'order-db', _, _),
    Conf > 0.90,
    Explanation = explanation(connection_pool_starvation, 'order-db', Conf, _, _),
    explanation_to_text(Explanation, Text),
    sub_atom(Text, _, _, _, 'ARGUS ROOT CAUSE DIAGNOSIS'),
    sub_atom(Text, _, _, _, 'order-db'),
    !.

:- end_tests(rules_master).
