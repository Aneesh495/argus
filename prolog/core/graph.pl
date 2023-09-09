/*
 * Module: argus_graph
 * Purpose: Graph theoretical algorithms for microservice topology and causal dependency DAGs.
 * Implements topological sort, cycle detection, critical path calculation, and Tarjan SCC.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_graph, [
    dag_nodes/2,
    dag_edges/2,
    dag_topological_sort/2,
    dag_has_cycle/2,
    dag_ancestors/3,
    dag_descendants/3,
    dag_transitive_closure/2,
    dag_critical_path/5,
    tarjan_scc/2
]).

:- use_module(library(lists)).
:- use_module(library(ordsets)).

/**
 * dag_nodes(+Edges, -Nodes)
 * Extracts all unique nodes present as edge sources or targets.
 */
dag_nodes(Edges, Nodes) :-
    findall(N, (member(edge(U, V, _), Edges), (N = U ; N = V)), Raw),
    sort(Raw, Nodes).

/**
 * dag_edges(+Graph, -Edges)
 */
dag_edges(Edges, Edges).

/**
 * dag_topological_sort(+Edges, -SortedNodes)
 * Performs topological sort on a directed acyclic graph.
 * Fails if graph contains a cycle.
 */
dag_topological_sort(Edges, Sorted) :-
    dag_nodes(Edges, Nodes),
    toposort_loop(Nodes, Edges, [], RevSorted),
    reverse(RevSorted, Sorted).

toposort_loop([], _, Acc, Acc) :- !.
toposort_loop(Remaining, Edges, Acc, Sorted) :-
    % Find a node with in-degree 0 in the remaining subgraph
    member(N, Remaining),
    \+ (member(edge(U, N, _), Edges), member(U, Remaining)),
    !,
    delete(Remaining, N, NextRemaining),
    toposort_loop(NextRemaining, Edges, [N|Acc], Sorted).

/**
 * dag_has_cycle(+Edges, -CyclePath)
 * Checks if directed graph contains a directed cycle; if so, unifies CyclePath with the cycle.
 */
dag_has_cycle(Edges, Cycle) :-
    dag_nodes(Edges, Nodes),
    member(Start, Nodes),
    find_cycle(Start, Edges, [Start], RevCycle),
    reverse(RevCycle, Cycle), !.

find_cycle(Current, Edges, Visited, [Next, Current | Rest]) :-
    member(edge(Current, Next, _), Edges),
    member(Next, Visited),
    !,
    take_until(Next, Visited, Rest).
find_cycle(Current, Edges, Visited, Cycle) :-
    member(edge(Current, Next, _), Edges),
    \+ member(Next, Visited),
    find_cycle(Next, Edges, [Next|Visited], Cycle).

take_until(Target, [Target|_], []) :- !.
take_until(Target, [H|T], [H|Rest]) :-
    take_until(Target, T, Rest).

/**
 * dag_ancestors(+Edges, +Node, -Ancestors)
 * Finds all upstream transitive dependencies of Node.
 */
dag_ancestors(Edges, Node, Ancestors) :-
    findall(A, path_exists(A, Node, Edges, [Node]), Raw),
    sort(Raw, Ancestors).

/**
 * dag_descendants(+Edges, +Node, -Descendants)
 * Finds all downstream transitive dependencies of Node.
 */
dag_descendants(Edges, Node, Descendants) :-
    findall(D, path_exists(Node, D, Edges, [Node]), Raw),
    sort(Raw, Descendants).

path_exists(Start, End, Edges, _Visited) :-
    member(edge(Start, End, _), Edges).
path_exists(Start, End, Edges, Visited) :-
    member(edge(Start, Mid, _), Edges),
    Mid \= End,
    \+ member(Mid, Visited),
    path_exists(Mid, End, Edges, [Mid|Visited]).

/**
 * dag_transitive_closure(+Edges, -ClosurePairs)
 * Returns all (U, V) pairs such that V is reachable from U.
 */
dag_transitive_closure(Edges, Closure) :-
    dag_nodes(Edges, Nodes),
    findall(pair(U, V), (member(U, Nodes), member(V, Nodes), U \= V, path_exists(U, V, Edges, [U])), Raw),
    sort(Raw, Closure).

/**
 * dag_critical_path(+Edges, +Source, +Sink, -Path, -TotalWeight)
 * Finds the maximum-weight (longest) path from Source to Sink in a DAG.
 * Used for critical execution path identification.
 */
dag_critical_path(Edges, Source, Sink, Path, TotalWeight) :-
    findall(Weight-P, find_weighted_path(Source, Sink, Edges, [Source], 0, P, Weight), Paths),
    Paths \= [],
    sort(1, @>=, Paths, [TotalWeight-Path|_]).

find_weighted_path(Sink, Sink, _Edges, Visited, AccWeight, Path, AccWeight) :-
    reverse(Visited, Path).
find_weighted_path(Current, Sink, Edges, Visited, AccWeight, Path, FinalWeight) :-
    member(edge(Current, Next, Weight), Edges),
    \+ member(Next, Visited),
    NewWeight is AccWeight + Weight,
    find_weighted_path(Next, Sink, Edges, [Next|Visited], NewWeight, Path, FinalWeight).

/**
 * tarjan_scc(+Edges, -Components)
 * Computes Strongly Connected Components (SCC) using Tarjan's linear time algorithm.
 */
tarjan_scc(Edges, Components) :-
    dag_nodes(Edges, Nodes),
    tarjan_run(Nodes, Edges, [], 0, [], [], Components),
    !.

tarjan_run([], _, _, _, _, Comps, Comps).
tarjan_run([V|Vs], Edges, VMap, Index, Stack, Acc, Comps) :-
    member(node_idx(V, _, _), VMap),
    !,
    tarjan_run(Vs, Edges, VMap, Index, Stack, Acc, Comps).
tarjan_run([V|Vs], Edges, VMap, Index, Stack, Acc, Comps) :-
    tarjan_connect(V, Edges, VMap, Index, Stack, NewVMap, NewIndex, NewStack, SubComps),
    append(Acc, SubComps, UpdatedAcc),
    tarjan_run(Vs, Edges, NewVMap, NewIndex, NewStack, UpdatedAcc, Comps).

tarjan_connect(V, Edges, VMap, Index, Stack, OutVMap, OutIndex, OutStack, OutComps) :-
    NextIndex is Index + 1,
    VMap1 = [node_idx(V, Index, Index)|VMap],
    Stack1 = [V|Stack],
    findall(W, member(edge(V, W, _), Edges), Neighbors),
    tarjan_neighbors(Neighbors, V, Edges, VMap1, NextIndex, Stack1, VMap2, OutIndex, Stack2, SubComps),
    member(node_idx(V, VIdx, VLow), VMap2),
    (   VIdx =:= VLow
    ->  tarjan_pop_scc(V, Stack2, [], Scc, RestStack),
        OutComps = [Scc|SubComps],
        OutVMap = VMap2,
        OutStack = RestStack
    ;   OutComps = SubComps,
        OutVMap = VMap2,
        OutStack = Stack2
    ).

tarjan_neighbors([], _, _, VMap, Index, Stack, VMap, Index, Stack, []).
tarjan_neighbors([W|Ws], V, Edges, VMap, Index, Stack, OutVMap, OutIndex, OutStack, Comps) :-
    (   \+ member(node_idx(W, _, _), VMap)
    ->  tarjan_connect(W, Edges, VMap, Index, Stack, VMap1, Index1, Stack1, C1),
        member(node_idx(W, _, WLow), VMap1),
        update_lowlink(V, WLow, VMap1, VMap2),
        tarjan_neighbors(Ws, V, Edges, VMap2, Index1, Stack1, OutVMap, OutIndex, OutStack, C2),
        append(C1, C2, Comps)
    ;   member(W, Stack)
    ->  member(node_idx(W, WIdx, _), VMap),
        update_lowlink(V, WIdx, VMap, VMap1),
        tarjan_neighbors(Ws, V, Edges, VMap1, Index, Stack, OutVMap, OutIndex, OutStack, Comps)
    ;   tarjan_neighbors(Ws, V, Edges, VMap, Index, Stack, OutVMap, OutIndex, OutStack, Comps)
    ).

update_lowlink(V, CandidateLow, [node_idx(V, Idx, CurrentLow)|T], [node_idx(V, Idx, MinLow)|T]) :-
    !, MinLow is min(CurrentLow, CandidateLow).
update_lowlink(V, CandidateLow, [H|T], [H|T2]) :-
    update_lowlink(V, CandidateLow, T, T2).

tarjan_pop_scc(V, [V|Rest], Acc, [V|Acc], Rest) :- !.
tarjan_pop_scc(V, [H|Rest], Acc, Scc, Rem) :-
    tarjan_pop_scc(V, Rest, [H|Acc], Scc, Rem).
