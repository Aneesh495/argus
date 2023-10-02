/*
 * Module: argus_topology_builder
 * Purpose: Reconstructs microservice call DAGs, service dependency graphs, and span trees.
 * Synthesizes RPC edges, async messaging links, database queries, and cache lookups.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_topology_builder, [
    build_span_dag/2,
    build_service_topology/2,
    trace_root_spans/2,
    trace_leaf_spans/2,
    span_children/3,
    span_tree/3
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../core/graph').

/**
 * build_span_dag(+Spans, -Edges)
 * Constructs directed edges: edge(ParentSpanId, ChildSpanId, WeightUs)
 * where WeightUs is the execution duration of the child span.
 */
build_span_dag(Spans, Edges) :-
    findall(edge(ParentId, ChildId, DurationUs), (
        member(Child, Spans),
        span_id(Child, ChildId),
        span_parent_id(Child, ParentId),
        ParentId \== '',
        ParentId \== '0',
        ParentId \== '0000000000000000',
        ParentId \== none,
        member(Parent, Spans),
        span_id(Parent, ParentId),
        span_duration_us(Child, DurationUs)
    ), Edges).

/**
 * build_service_topology(+Spans, -ServiceEdges)
 * Reconstructs cross-service dependencies:
 * service_edge(FromService, ToService, Kind, AvgLatencyUs, Count)
 */
build_service_topology(Spans, ServiceEdges) :-
    findall(call(FromSvc, ToSvc, Dur), (
        member(Child, Spans),
        span_parent_id(Child, ParentId),
        ParentId \== '',
        member(Parent, Spans),
        span_id(Parent, ParentId),
        span_service(Parent, FromSvc),
        span_service(Child, ToSvc),
        FromSvc \== ToSvc,
        span_duration_us(Child, Dur)
    ), Calls),
    aggregate_service_calls(Calls, ServiceEdges).

aggregate_service_calls(Calls, Aggregated) :-
    findall(pair(From, To), member(call(From, To, _), Calls), Pairs),
    sort(Pairs, UniquePairs),
    maplist(summarize_pair_calls(Calls), UniquePairs, Aggregated).

summarize_pair_calls(Calls, pair(From, To), service_edge(From, To, rpc, AvgLat, Count)) :-
    findall(Dur, member(call(From, To, Dur), Calls), Durations),
    length(Durations, Count),
    sum_list(Durations, Sum),
    AvgLat is Sum / Count.

/**
 * trace_root_spans(+Spans, -Roots)
 */
trace_root_spans(Spans, Roots) :-
    findall(S, (member(S, Spans), span_is_root(S)), Roots).

/**
 * trace_leaf_spans(+Spans, -Leaves)
 */
trace_leaf_spans(Spans, Leaves) :-
    findall(S, (
        member(S, Spans),
        span_id(S, SId),
        \+ (member(Other, Spans), span_parent_id(Other, SId))
    ), Leaves).

/**
 * span_children(+Spans, +ParentId, -Children)
 */
span_children(Spans, ParentId, Children) :-
    findall(C, (member(C, Spans), span_parent_id(C, ParentId)), Children).

/**
 * span_tree(+Spans, +RootSpan, -Tree)
 * Recursively builds hierarchical tree: node(Span, ChildrenTrees)
 */
span_tree(Spans, RootSpan, node(RootSpan, ChildTrees)) :-
    span_id(RootSpan, RootId),
    span_children(Spans, RootId, Children),
    maplist(span_tree(Spans), Children, ChildTrees).
