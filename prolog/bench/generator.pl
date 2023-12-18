/*
 * Module: argus_trace_generator
 * Purpose: Synthetic microservice trace and incident scenario generator for benchmarks and tests.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_trace_generator, [
    generate_synthetic_trace/5,
    inject_synthetic_fault/3
]).

:- use_module(library(lists)).
:- use_module(library(random)).
:- use_module('../core/types').

/**
 * generate_synthetic_trace(+TraceId, +Depth, +BranchingFactor, +FaultType, -Spans)
 * Generates an synthetic microservice execution tree with an optional injected fault.
 */
generate_synthetic_trace(TraceId, Depth, Branching, FaultType, AllSpans) :-
    RootStart = 1000,
    span_create(TraceId, 'span_0', '', 'gateway', 'GET /api', RootStart, RootStart + 50000, 1, [], RootSpan),
    gen_children(TraceId, 'span_0', 'gateway', 1, Depth, Branching, RootStart + 100, Children),
    RawSpans = [RootSpan|Children],
    (   FaultType \== none
    ->  inject_synthetic_fault(FaultType, RawSpans, AllSpans)
    ;   AllSpans = RawSpans
    ).

gen_children(_, _, _, CurrentDepth, MaxDepth, _, _, []) :-
    CurrentDepth > MaxDepth, !.
gen_children(TraceId, ParentId, _ParentSvc, CurrentDepth, MaxDepth, Branching, StartUs, Spans) :-
    findall(ChildSpan, (
        between(1, Branching, B),
        format(atom(ChildId), "~w_~w_~w", [ParentId, CurrentDepth, B]),
        format(atom(ChildSvc), "svc_d~w_b~w", [CurrentDepth, B]),
        format(atom(OpName), "op_~w", [B]),
        random_between(500, 5000, Dur),
        ChildStart is StartUs + (B * 200),
        ChildEnd is ChildStart + Dur,
        span_create(TraceId, ChildId, ParentId, ChildSvc, OpName, ChildStart, ChildEnd, 1, [], ChildSpan)
    ), DirectChildren),
    NextDepth is CurrentDepth + 1,
    findall(SubDescendants, (
        member(DC, DirectChildren),
        span_id(DC, DCId),
        span_service(DC, DCSvc),
        span_end_us(DC, DCEnd),
        gen_children(TraceId, DCId, DCSvc, NextDepth, MaxDepth, Branching, DCEnd, SubDescendants)
    ), Nested),
    flatten([DirectChildren|Nested], Spans).

/**
 * inject_synthetic_fault(+FaultType, +SpansIn, -SpansOut)
 */
inject_synthetic_fault(retry_storm, [Root|Rest], [Root, R1, R2, R3|Rest]) :-
    span_trace_id(Root, TraceId),
    span_id(Root, RootId),
    span_create(TraceId, 'retry_1', RootId, 'payment', 'charge', 2000, 2500, 2, [], R1),
    span_create(TraceId, 'retry_2', RootId, 'payment', 'charge', 2600, 3100, 2, [], R2),
    span_create(TraceId, 'retry_3', RootId, 'payment', 'charge', 3200, 3800, 2, [], R3).

inject_synthetic_fault(connection_pool_starvation, [Root|Rest], [Root, PoolSpan|Rest]) :-
    span_trace_id(Root, TraceId),
    span_id(Root, RootId),
    span_create(TraceId, 'db_starve', RootId, 'inventory-db', 'SELECT stock', 2000, 80000, 1,
                ['pool.wait_time_ms'=65], PoolSpan).

inject_synthetic_fault(_, Spans, Spans).
