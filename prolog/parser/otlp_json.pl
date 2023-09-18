/*
 * Module: argus_otlp_json
 * Purpose: OpenTelemetry (OTLP) v1 JSON parser and deserializer into canonical Argus spans.
 * Converts OTLP resourceSpans, scopeSpans, attributes, status, and events into first-order terms.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_otlp_json, [
    otlp_json_parse/2,
    otlp_json_parse_stream/2,
    otlp_dict_to_spans/2
]).

:- use_module(library(http/json)).
:- use_module('../core/types').

/**
 * otlp_json_parse(+Input, -Spans)
 * Parses JSON atom, string, or code list in OpenTelemetry v1 format into list of span/10 records.
 */
otlp_json_parse(Input, Spans) :-
    (   atom(Input)   -> open_string(Input, Stream)
    ;   string(Input) -> open_string(Input, Stream)
    ;   is_list(Input)-> atom_codes(Atom, Input), open_string(Atom, Stream)
    ),
    call_cleanup(
        otlp_json_parse_stream(Stream, Spans),
        close(Stream)
    ).

otlp_json_parse_stream(Stream, Spans) :-
    json_read_dict(Stream, Dict, [value_string_as(atom)]),
    otlp_dict_to_spans(Dict, Spans).

/**
 * otlp_dict_to_spans(+Dict, -Spans)
 */
otlp_dict_to_spans(Dict, Spans) :-
    (   get_dict(resourceSpans, Dict, ResSpans)
    ->  phrase(extract_resource_spans(ResSpans), Spans)
    ;   get_dict(spans, Dict, RawSpans)
    ->  maplist(convert_single_otlp_span('unknown-service'), RawSpans, Spans)
    ;   Spans = []
    ).

extract_resource_spans([]) --> [].
extract_resource_spans([RS|Rest]) -->
    {
        extract_service_name(RS, ServiceName),
        (   get_dict(scopeSpans, RS, ScopeSpans)
        ->  true
        ;   ScopeSpans = []
        )
    },
    extract_scope_spans(ScopeSpans, ServiceName),
    extract_resource_spans(Rest).

extract_service_name(RS, ServiceName) :-
    (   get_dict(resource, RS, Res),
        get_dict(attributes, Res, Attrs),
        member(Attr, Attrs),
        get_dict(key, Attr, 'service.name'),
        get_dict(value, Attr, ValDict),
        (   get_dict(stringValue, ValDict, ServiceName)
        ;   ServiceName = ValDict
        )
    ->  true
    ;   ServiceName = 'unnamed-service'
    ), !.

extract_scope_spans([], _) --> [].
extract_scope_spans([SS|Rest], ServiceName) -->
    {
        (   get_dict(spans, SS, RawSpans)
        ->  true
        ;   RawSpans = []
        ),
        maplist(convert_single_otlp_span(ServiceName), RawSpans, Converted)
    },
    list_to_diff(Converted),
    extract_scope_spans(Rest, ServiceName).

list_to_diff([]) --> [].
list_to_diff([H|T]) --> [H], list_to_diff(T).

convert_single_otlp_span(DefaultService, SpanDict, Span) :-
    get_or_default(traceId, SpanDict, '', TraceId),
    get_or_default(spanId, SpanDict, '', SpanId),
    get_or_default(parentSpanId, SpanDict, '', ParentId),
    get_or_default(name, SpanDict, 'unnamed-operation', Name),
    
    get_time_us(startTimeUnixNano, SpanDict, StartUs),
    get_time_us(endTimeUnixNano, SpanDict, EndUs),
    
    get_status_code(SpanDict, StatusCode),
    extract_attributes_dict(SpanDict, Attrs),
    
    span_create(TraceId, SpanId, ParentId, DefaultService, Name, StartUs, EndUs, StatusCode, Attrs, Span).

get_or_default(Key, Dict, Default, Value) :-
    (   get_dict(Key, Dict, V) -> Value = V ; Value = Default ).

get_time_us(Key, Dict, Us) :-
    (   get_dict(Key, Dict, Val)
    ->  (   atom(Val) -> atom_number(Val, Num) ; Num = Val ),
        Us is Num // 1000
    ;   Us = 0
    ).

get_status_code(Dict, Code) :-
    (   get_dict(status, Dict, StatusDict),
        get_dict(code, StatusDict, RawCode)
    ->  (   RawCode = 'STATUS_CODE_ERROR' -> Code = 2
        ;   RawCode = 'STATUS_CODE_OK'    -> Code = 1
        ;   integer(RawCode)              -> Code = RawCode
        ;   Code = 0
        )
    ;   Code = 0
    ).

extract_attributes_dict(Dict, Flattened) :-
    (   get_dict(attributes, Dict, Attrs), is_list(Attrs)
    ->  findall(Key=Val, (
            member(A, Attrs),
            get_dict(key, A, Key),
            get_dict(value, A, VDict),
            extract_val(VDict, Val)
        ), Flattened)
    ;   Flattened = []
    ).

extract_val(Dict, Val) :-
    is_dict(Dict), !,
    (   get_dict(stringValue, Dict, Val)
    ;   get_dict(intValue, Dict, Val)
    ;   get_dict(doubleValue, Dict, Val)
    ;   get_dict(boolValue, Dict, Val)
    ;   Val = Dict
    ), !.
extract_val(Val, Val).
