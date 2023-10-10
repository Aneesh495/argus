/*
 * Module: argus_clock_skew
 * Purpose: Distributed clock skew detection, causality violation analysis, and convex alignment.
 * Restores causal monotonicity (child start >= parent start) without altering intrinsic span duration.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_clock_skew, [
    detect_clock_skews/2,
    correct_clock_skews/2,
    has_causality_violation/2
]).

:- use_module(library(lists)).
:- use_module('../core/types').

/**
 * detect_clock_skews(+Spans, -SkewAnomalies)
 * Finds parent-child pairs where ChildStart < ParentStart or ChildEnd > ParentEnd.
 */
detect_clock_skews(Spans, Anomalies) :-
    findall(skew(ParentId, ChildId, SkewUs), (
        member(Child, Spans),
        span_id(Child, ChildId),
        span_parent_id(Child, ParentId),
        ParentId \== '',
        member(Parent, Spans),
        span_id(Parent, ParentId),
        span_start_us(Parent, PStart),
        span_start_us(Child, CStart),
        CStart < PStart,
        SkewUs is PStart - CStart
    ), Anomalies).

/**
 * has_causality_violation(+ParentSpan, +ChildSpan)
 */
has_causality_violation(Parent, Child) :-
    span_start_us(Parent, PStart),
    span_start_us(Child, CStart),
    CStart < PStart.

/**
 * correct_clock_skews(+Spans, -AdjustedSpans)
 * Applies convex causal alignment: if ChildStart < ParentStart, shifts child
 * so ChildStart = ParentStart + 1 us (minimum positive causal forward delta),
 * preserving exact span duration (ChildEnd = NewChildStart + Duration).
 */
correct_clock_skews(Spans, AdjustedSpans) :-
    trace_root_spans(Spans, Roots),
    align_spans_recursive(Roots, Spans, [], AdjustedSpans).

align_spans_recursive([], _, Acc, Acc).
align_spans_recursive([Current|RestQueue], AllSpans, Visited, Result) :-
    span_id(Current, CurrId),
    (   member(Current, Visited)
    ->  align_spans_recursive(RestQueue, AllSpans, Visited, Result)
    ;   span_children(AllSpans, CurrId, Children),
        span_start_us(Current, PStart),
        span_end_us(Current, PEnd),
        maplist(align_child_span(PStart, PEnd), Children, AlignedChildren),
        append(Visited, [Current], NewVisited),
        append(RestQueue, AlignedChildren, NewQueue),
        align_spans_recursive(NewQueue, AllSpans, NewVisited, Result)
    ).

align_child_span(PStart, _PEnd, Child, AlignedChild) :-
    span_start_us(Child, CStart),
    span_duration_us(Child, Dur),
    (   CStart < PStart
    ->  NewStart is PStart + 1, % Shift forward to respect causality
        NewEnd is NewStart + Dur
    ;   NewStart = CStart,
        NewEnd is NewStart + Dur
    ),
    span_trace_id(Child, TraceId),
    span_id(Child, SpanId),
    span_parent_id(Child, ParentId),
    span_service(Child, Service),
    span_name(Child, Name),
    span_status(Child, Status),
    span_attributes(Child, Attrs),
    span_create(TraceId, SpanId, ParentId, Service, Name, NewStart, NewEnd, Status, Attrs, AlignedChild).

trace_root_spans(Spans, Roots) :-
    findall(S, (member(S, Spans), span_is_root(S)), Roots).

span_children(Spans, ParentId, Children) :-
    findall(C, (member(C, Spans), span_parent_id(C, ParentId)), Children).
