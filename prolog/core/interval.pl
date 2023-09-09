/*
 * Module: argus_interval
 * Purpose: Allen's Interval Algebra and temporal constraint reasoning via CLP(FD).
 * Enables exact causal ordering, concurrency detection, and queuing delay decomposition.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_interval, [
    interval_create/3,
    interval_start/2,
    interval_end/2,
    interval_duration/2,
    interval_relation/3,
    interval_before/2,
    interval_meets/2,
    interval_overlaps/2,
    interval_starts/2,
    interval_during/2,
    interval_finishes/2,
    interval_equals/2,
    interval_concurrency/2,
    interval_intersection/3,
    interval_gap/3,
    interval_delay_decomposition/4
]).

:- use_module(library(clpfd)).
:- use_module(library(lists)).

/**
 * interval_create(?Start, ?End, -Interval)
 * Creates temporal interval iv(Start, End) with constraint Start #=< End.
 */
interval_create(Start, End, iv(Start, End)) :-
    Start #=< End.

interval_start(iv(Start, _), Start).
interval_end(iv(_, End), End).

/**
 * interval_duration(+Interval, -Duration)
 */
interval_duration(iv(Start, End), Duration) :-
    Duration #= End - Start.

/**
 * interval_relation(+I1, +I2, -Relation)
 * Determines which of Allen's 13 basic relations holds between I1 and I2.
 */
interval_relation(iv(S1, E1), iv(S2, E2), Relation) :-
    (   E1 #< S2  -> Relation = before
    ;   E1 #= S2  -> Relation = meets
    ;   S1 #< S2, S2 #< E1, E1 #< E2 -> Relation = overlaps
    ;   S1 #= S2, E1 #< E2 -> Relation = starts
    ;   S2 #< S1, E1 #< E2 -> Relation = during
    ;   S2 #< S1, E1 #= E2 -> Relation = finishes
    ;   S1 #= S2, E1 #= E2 -> Relation = equals
    ;   S1 #> E2  -> Relation = after
    ;   S1 #= E2  -> Relation = met_by
    ;   S2 #< S1, S1 #< E2, E2 #< E1 -> Relation = overlapped_by
    ;   S1 #= S2, E2 #< E1 -> Relation = started_by
    ;   S1 #< S2, E2 #< E1 -> Relation = contains
    ;   S1 #< S2, E1 #= E2 -> Relation = finished_by
    ).

interval_before(I1, I2) :- interval_relation(I1, I2, before).
interval_meets(I1, I2) :- interval_relation(I1, I2, meets).
interval_overlaps(I1, I2) :- interval_relation(I1, I2, overlaps).
interval_starts(I1, I2) :- interval_relation(I1, I2, starts).
interval_during(I1, I2) :- interval_relation(I1, I2, during).
interval_finishes(I1, I2) :- interval_relation(I1, I2, finishes).
interval_equals(I1, I2) :- interval_relation(I1, I2, equals).

/**
 * interval_concurrency(+I1, +I2)
 * True if I1 and I2 share non-zero overlapping wall-clock time.
 */
interval_concurrency(iv(S1, E1), iv(S2, E2)) :-
    S1 #< E2,
    S2 #< E1.

/**
 * interval_intersection(+I1, +I2, -IntersectionInterval)
 * Computes the overlapping interval of two concurrent intervals.
 */
interval_intersection(iv(S1, E1), iv(S2, E2), iv(StartMax, EndMin)) :-
    interval_concurrency(iv(S1, E1), iv(S2, E2)),
    StartMax #= max(S1, S2),
    EndMin #= min(E1, E2),
    StartMax #< EndMin.

/**
 * interval_gap(+I1, +I2, -GapDuration)
 * Computes idle time between two non-overlapping intervals.
 */
interval_gap(iv(_, E1), iv(S2, _), Gap) :-
    E1 #=< S2,
    !,
    Gap #= S2 - E1.
interval_gap(iv(S1, _), iv(_, E2), Gap) :-
    E2 #=< S1,
    Gap #= S1 - E2.

/**
 * interval_delay_decomposition(+ParentInterval, +ChildrenIntervals, -QueuingDelay, -ExecutionDelay)
 * Decomposes parent wall-clock duration into active child execution vs waiting / queue delay.
 */
interval_delay_decomposition(iv(PS, PE), Children, QueuingDelay, ExecutionDelay) :-
    ParentDuration #= PE - PS,
    merge_concurrent_intervals(Children, DisjointSpans),
    sum_durations(DisjointSpans, 0, ExecutionDelay),
    QueuingDelay #= max(0, ParentDuration - ExecutionDelay).

merge_concurrent_intervals([], []) :- !.
merge_concurrent_intervals([iv(S, E)|Rest], Merged) :-
    sort_intervals([iv(S, E)|Rest], [First|Sorted]),
    merge_sorted_intervals(Sorted, First, Merged).

sort_intervals(List, Sorted) :-
    findall(iv(S, E), member(iv(S, E), List), Normalized),
    sort(1, @=<, Normalized, Sorted).

merge_sorted_intervals([], Current, [Current]).
merge_sorted_intervals([iv(S, E)|Rest], iv(CS, CE), Merged) :-
    (   S #=< CE
    ->  NewEnd #= max(CE, E),
        merge_sorted_intervals(Rest, iv(CS, NewEnd), Merged)
    ;   Merged = [iv(CS, CE)|Tail],
        merge_sorted_intervals(Rest, iv(S, E), Tail)
    ).

sum_durations([], Acc, Acc).
sum_durations([iv(S, E)|Rest], Acc, Total) :-
    Dur #= E - S,
    NewAcc #= Acc + Dur,
    sum_durations(Rest, NewAcc, Total).
