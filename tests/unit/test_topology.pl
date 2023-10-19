/*
 * Unit tests for Argus topology modules:
 * Builder, Critical Path, Clock Skew, and Concurrency Analysis.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(test_topology, [
    run_topology_tests/0
]).

:- use_module(library(plunit)).
:- use_module('../../prolog/core/types').
:- use_module('../../prolog/topology/builder').
:- use_module('../../prolog/topology/critical_path').
:- use_module('../../prolog/topology/clock_skew').
:- use_module('../../prolog/topology/concurrency').

run_topology_tests :-
    run_tests([builder, critical_path, clock_skew, concurrency]).

:- begin_tests(builder).

test(span_dag_and_topology_construction) :-
    span_create('t1', 's_root', '', 'gateway', 'GET /checkout', 0, 1000, 1, [], Root),
    span_create('t1', 's_auth', 's_root', 'auth-service', 'validateToken', 50, 200, 1, [], Auth),
    span_create('t1', 's_pay', 's_root', 'payment-service', 'charge', 250, 900, 1, [], Pay),
    Spans = [Root, Auth, Pay],
    
    build_span_dag(Spans, Edges),
    length(Edges, 2),
    member(edge('s_root', 's_auth', 150), Edges),
    member(edge('s_root', 's_pay', 650), Edges),
    
    build_service_topology(Spans, SvcEdges),
    length(SvcEdges, 2),
    member(service_edge('gateway', 'auth-service', rpc, Lat1, 1), SvcEdges),
    Lat1 =:= 150,
    member(service_edge('gateway', 'payment-service', rpc, Lat2, 1), SvcEdges),
    Lat2 =:= 650,
    !.

:- end_tests(builder).

:- begin_tests(critical_path).

test(critical_path_and_self_time) :-
    % Root runs 0 to 1000 us (total 1000)
    % Child 1 (fast): 100 to 300 us (200 us)
    % Child 2 (slow, critical): 250 to 950 us (700 us)
    span_create('t1', 's_root', '', 'gateway', 'handleReq', 0, 1000, 1, [], Root),
    span_create('t1', 's_c1', 's_root', 'fast-svc', 'fastCall', 100, 300, 1, [], C1),
    span_create('t1', 's_c2', 's_root', 'slow-svc', 'slowCall', 250, 950, 1, [], C2),
    Spans = [Root, C1, C2],
    
    compute_critical_path(Spans, Path, TotalDur),
    Path = ['s_root', 's_c2'],
    TotalDur =:= 700,
    
    span_self_time(Spans, C2, C2Self),
    C2Self =:= 700,
    
    trace_bottlenecks(Spans, 2, Bottlenecks),
    length(Bottlenecks, 2),
    Bottlenecks = [bottleneck('s_c2', 'slow-svc', 'slowCall', 700, false)|_].

:- end_tests(critical_path).

:- begin_tests(clock_skew).

test(clock_skew_detection_and_correction) :-
    % Parent starts at 100 us
    % Child starts at 80 us (starts 20 us before parent due to clock skew!)
    span_create('t1', 'p1', '', 'svc_a', 'call_b', 100, 300, 1, [], Parent),
    span_create('t1', 'c1', 'p1', 'svc_b', 'do_work', 80, 240, 1, [], Child), % duration 160
    Spans = [Parent, Child],
    
    detect_clock_skews(Spans, Anomalies),
    Anomalies = [skew('p1', 'c1', 20)],
    
    correct_clock_skews(Spans, CorrectedSpans),
    member(CorrectedChild, CorrectedSpans),
    span_id(CorrectedChild, 'c1'),
    span_start_us(CorrectedChild, NewStart),
    NewStart =:= 101, % shifted forward to ParentStart + 1
    span_duration_us(CorrectedChild, Dur),
    Dur =:= 160. % duration preserved exactly!

:- end_tests(clock_skew).

:- begin_tests(concurrency).

test(concurrency_and_tail_risk) :-
    % Two concurrent children: c1 (100..500) and c2 (200..600)
    span_create('t1', 'p1', '', 'aggregator', 'fanout', 0, 700, 1, [], Parent),
    span_create('t1', 'c1', 'p1', 'worker1', 'work', 100, 500, 1, [], C1),
    span_create('t1', 'c2', 'p1', 'worker2', 'work', 200, 600, 1, [], C2),
    Spans = [Parent, C1, C2],
    
    find_concurrent_spans(Spans, Pairs),
    member(pair('c1', 'c2'), Pairs),
    
    fork_join_patterns(Spans, Patterns),
    length(Patterns, 1),
    Patterns = [fork_join('p1', 'aggregator', 2, ['c1', 'c2'])],
    
    tail_latency_amplification_risk(10, 95.0, Risk),
    % Risk should be approx 0.4012 (40.1%)
    Risk > 0.40, Risk < 0.41,
    !.

:- end_tests(concurrency).
