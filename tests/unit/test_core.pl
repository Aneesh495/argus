/*
 * Unit tests for Argus core modules (types, error, graph, interval, stats).
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(test_core, [
    run_core_tests/0
]).

:- use_module(library(plunit)).
:- use_module('../../prolog/core/types').
:- use_module('../../prolog/core/error').
:- use_module('../../prolog/core/graph').
:- use_module('../../prolog/core/interval').
:- use_module('../../prolog/core/stats').

run_core_tests :-
    run_tests([types, error, graph, interval, stats]).

:- begin_tests(types).

test(span_lifecycle) :-
    span_create('t1', 's1', 'root', 'auth', 'verify', 1000, 3500, 1, [user='alice'], S),
    span_trace_id(S, 't1'),
    span_id(S, 's1'),
    span_parent_id(S, 'root'),
    span_service(S, 'auth'),
    span_duration_us(S, 2500),
    \+ span_is_root(S),
    \+ span_is_error(S),
    span_attribute_get(S, user, 'alice').

test(span_root_and_error) :-
    span_create('t2', 's0', '', 'gateway', 'proxy', 0, 500, 2, [], RootErrSpan),
    span_is_root(RootErrSpan),
    span_is_error(RootErrSpan),
    span_duration_us(RootErrSpan, 500).

:- end_tests(types).

:- begin_tests(error).

test(error_raising_and_catching) :-
    catch_argus_error(
        raise_argus_error(trace_parse_failure, 'Invalid header', [line=42]),
        [Cat, Msg, Ctx, Res]>>(Res = caught(Cat, Msg, Ctx)),
        Result
    ),
    Result = caught(trace_parse_failure, 'Invalid header', [line=42]).

test(assertion_pass) :-
    argus_assert(1 =:= 1, 'Math still works').

:- end_tests(error).

:- begin_tests(graph).

test(dag_toposort_linear) :-
    Edges = [edge(a, b, 10), edge(b, c, 20), edge(c, d, 30)],
    dag_topological_sort(Edges, Sorted),
    Sorted = [a, b, c, d].

test(dag_cycle_detection) :-
    CyclicEdges = [edge(a, b, 1), edge(b, c, 1), edge(c, a, 1)],
    dag_has_cycle(CyclicEdges, Cycle),
    Cycle \= [].

test(dag_critical_path) :-
    % Diamond graph: a -> b (10) -> d (5); a -> c (50) -> d (5)
    Edges = [edge(a, b, 10), edge(b, d, 5), edge(a, c, 50), edge(c, d, 5)],
    dag_critical_path(Edges, a, d, Path, TotalWeight),
    Path = [a, c, d],
    TotalWeight =:= 55.

test(tarjan_scc) :-
    Edges = [edge(1, 2, 1), edge(2, 3, 1), edge(3, 1, 1), edge(3, 4, 1), edge(4, 5, 1)],
    tarjan_scc(Edges, Components),
    member(SCC, Components),
    sort(SCC, [1, 2, 3]),
    !.

:- end_tests(graph).

:- begin_tests(interval).

test(allens_interval_relations) :-
    interval_create(10, 20, I1),
    interval_create(30, 40, I2),
    interval_relation(I1, I2, before),
    interval_relation(I2, I1, after),
    
    interval_create(20, 30, I_meet),
    interval_relation(I1, I_meet, meets),
    
    interval_create(15, 25, I_overlap),
    interval_relation(I1, I_overlap, overlaps),
    
    interval_create(12, 18, I_during),
    interval_relation(I_during, I1, during),
    
    interval_create(10, 20, I_same),
    interval_relation(I1, I_same, equals).

test(concurrency_and_intersection) :-
    interval_create(100, 200, I1),
    interval_create(150, 300, I2),
    interval_concurrency(I1, I2),
    interval_intersection(I1, I2, iv(150, 200)),
    interval_duration(iv(150, 200), 50).

test(delay_decomposition) :-
    % Parent span runs 0 to 1000 us (total 1000 us)
    % Child 1 runs 100 to 400 us (300 us)
    % Child 2 runs 300 to 700 us (concurrent with Child 1, merged 100 to 700 is 600 us)
    interval_create(0, 1000, Parent),
    Children = [iv(100, 400), iv(300, 700)],
    interval_delay_decomposition(Parent, Children, QueuingDelay, ExecutionDelay),
    ExecutionDelay =:= 600,
    QueuingDelay =:= 400.

:- end_tests(interval).

:- begin_tests(stats).

test(percentile_computation) :-
    Vals = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100],
    percentile(Vals, 50, P50),
    P50 =:= 55.0,
    percentile(Vals, 90, P90),
    P90 =:= 91.0.

test(welford_variance_and_zscore) :-
    Vals = [10, 10, 10, 10, 10],
    welford_stats(Vals, Mean, Var, StdDev),
    Mean =:= 10.0,
    Var =:= 0.0,
    StdDev =:= 0.0,
    z_score(10.0, Mean, StdDev, Z0),
    Z0 =:= 0.0.

test(ewma_and_anomaly) :-
    ewma(100.0, 200.0, 0.2, Updated),
    Updated =:= 120.0,
    is_anomalous_latency(500.0, 100.0, 50.0, 3.0, Anomaly),
    Anomaly = true.

:- end_tests(stats).
