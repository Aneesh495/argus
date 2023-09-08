/*
 * Module: argus_types
 * Purpose: First-order canonical representations and predicates for telemetry records.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_types, [
    span_create/10,
    span_trace_id/2,
    span_id/2,
    span_parent_id/2,
    span_service/2,
    span_name/2,
    span_start_us/2,
    span_end_us/2,
    span_status/2,
    span_attributes/2,
    span_events/2,
    span_duration_us/2,
    span_is_root/1,
    span_is_error/1,
    span_attribute_get/3,
    event_create/4,
    metric_create/5,
    hypothesis_create/5,
    remediation_create/4
]).

:- use_module(library(lists)).

/**
 * span_create(?TraceId, ?SpanId, ?ParentId, ?Service, ?Name, ?StartUs, ?EndUs, ?Status, ?Attrs, -Span)
 * Constructs or destructures a canonical span record:
 * span(TraceId, SpanId, ParentId, Service, Name, StartUs, EndUs, Status, Attrs, Events)
 */
span_create(TraceId, SpanId, ParentId, Service, Name, StartUs, EndUs, Status, Attrs,
            span(TraceId, SpanId, ParentId, Service, Name, StartUs, EndUs, Status, Attrs, [])).

span_trace_id(span(TraceId, _, _, _, _, _, _, _, _, _), TraceId).
span_id(span(_, SpanId, _, _, _, _, _, _, _, _), SpanId).
span_parent_id(span(_, _, ParentId, _, _, _, _, _, _, _), ParentId).
span_service(span(_, _, _, Service, _, _, _, _, _, _), Service).
span_name(span(_, _, _, _, Name, _, _, _, _, _), Name).
span_start_us(span(_, _, _, _, _, StartUs, _, _, _, _), StartUs).
span_end_us(span(_, _, _, _, _, _, EndUs, _, _, _), EndUs).
span_status(span(_, _, _, _, _, _, _, Status, _, _), Status).
span_attributes(span(_, _, _, _, _, _, _, _, Attrs, _), Attrs).
span_events(span(_, _, _, _, _, _, _, _, _, Events), Events).

/**
 * span_duration_us(+Span, -DurationUs)
 * Calculates the wall-clock execution duration in microseconds.
 */
span_duration_us(span(_, _, _, _, _, StartUs, EndUs, _, _, _), DurationUs) :-
    integer(StartUs),
    integer(EndUs),
    DurationUs is max(0, EndUs - StartUs).

/**
 * span_is_root(+Span)
 * True if the span has no parent (empty atom '', or '0000000000000000', or none).
 */
span_is_root(span(_, _, '', _, _, _, _, _, _, _)) :- !.
span_is_root(span(_, _, none, _, _, _, _, _, _, _)) :- !.
span_is_root(span(_, _, '0', _, _, _, _, _, _, _)) :- !.
span_is_root(span(_, _, '0000000000000000', _, _, _, _, _, _, _)) :- !.

/**
 * span_is_error(+Span)
 * True if the span status indicates error (status code 2, error, or failure).
 */
span_is_error(span(_, _, _, _, _, _, _, 2, _, _)) :- !.
span_is_error(span(_, _, _, _, _, _, _, error, _, _)) :- !.
span_is_error(span(_, _, _, _, _, _, _, 'ERROR', _, _)) :- !.
span_is_error(span(_, _, _, _, _, _, _, failed, _, _)) :- !.

/**
 * span_attribute_get(+Span, +Key, -Value)
 * Looks up attribute value by key in key-value list.
 */
span_attribute_get(span(_, _, _, _, _, _, _, _, Attrs, _), Key, Value) :-
    member(Key=Value, Attrs), !.
span_attribute_get(span(_, _, _, _, _, _, _, _, Attrs, _), Key, Value) :-
    member(attr(Key, Value), Attrs), !.

/**
 * event_create(?TimestampUs, ?Name, ?Attrs, -Event)
 */
event_create(TimestampUs, Name, Attrs, event(TimestampUs, Name, Attrs)).

/**
 * metric_create(?MetricName, ?Service, ?TimestampUs, ?Value, -Metric)
 */
metric_create(MetricName, Service, TimestampUs, Value, metric(MetricName, Service, TimestampUs, Value)).

/**
 * hypothesis_create(?FaultType, ?Service, ?Confidence, ?Evidence, -Hypothesis)
 */
hypothesis_create(FaultType, Service, Confidence, Evidence,
                  hypothesis(FaultType, Service, Confidence, Evidence)).

/**
 * remediation_create(?ActionType, ?Service, ?Params, -Remediation)
 */
remediation_create(ActionType, Service, Params, remediation(ActionType, Service, Params)).
