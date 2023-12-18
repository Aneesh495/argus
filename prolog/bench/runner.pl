/*
 * Module: argus_benchmark_runner
 * Purpose: Performance micro-benchmarks for ingestion, DAG construction, and abductive inference.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_benchmark_runner, [
    run_benchmarks/0
]).

:- use_module(library(statistics)).
:- use_module('../argus').
:- use_module('../topology/builder').
:- use_module('../topology/critical_path').
:- use_module('../rules/diagnose').
:- use_module('generator').

run_benchmarks :-
    format("==================================================~n"),
    format("           ARGUS BENCHMARK SUITE~n"),
    format("==================================================~n"),
    bench_trace_generation(Spans),
    bench_topology_construction(Spans),
    bench_abductive_diagnosis(Spans),
    format("==================================================~n"),
    format("All benchmarks executed successfully!~n").

bench_trace_generation(Spans) :-
    format("[1/3] Generating synthetic trace topology (depth=4, branch=3)...~n"),
    get_time(T0),
    generate_synthetic_trace('bench_trace', 4, 3, retry_storm, Spans),
    get_time(T1),
    Elapsed is (T1 - T0) * 1000.0,
    length(Spans, SpanCount),
    format("      Generated ~w spans in ~2f ms~n", [SpanCount, Elapsed]).

bench_topology_construction(Spans) :-
    format("[2/3] Benchmarking DAG construction and critical path analysis...~n"),
    get_time(T0),
    run_topology_iterations(Spans, 100),
    get_time(T1),
    Elapsed is (T1 - T0) * 1000.0,
    AvgUs is (Elapsed / 100.0) * 1000.0,
    format("      100 iterations complete: ~2f ms total (~2f us/iter)~n", [Elapsed, AvgUs]).

run_topology_iterations(_, 0) :- !.
run_topology_iterations(Spans, N) :-
    build_span_dag(Spans, _Edges),
    compute_critical_path(Spans, _Path, _Dur),
    N1 is N - 1,
    run_topology_iterations(Spans, N1).

bench_abductive_diagnosis(Spans) :-
    format("[3/3] Benchmarking abductive diagnosis & remediation synthesis...~n"),
    get_time(T0),
    run_diagnose_iterations(Spans, 50),
    get_time(T1),
    Elapsed is (T1 - T0) * 1000.0,
    AvgMs is Elapsed / 50.0,
    QPS is 50.0 / (T1 - T0),
    format("      50 iterations complete: ~2f ms total (~2f ms/eval, ~1f QPS)~n", [Elapsed, AvgMs, QPS]).

run_diagnose_iterations(_, 0) :- !.
run_diagnose_iterations(Spans, N) :-
    diagnose_incident_with_explanation(Spans, [], [], _, Explanation),
    argus_remediate_incident(Explanation, _),
    N1 is N - 1,
    run_diagnose_iterations(Spans, N1).
