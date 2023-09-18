/*
 * Module: argus_jaeger_json
 * Purpose: Jaeger trace JSON format parser and converter to canonical Argus spans.
 * Resolves processID to serviceName and decodes CHILD_OF / FOLLOWS_FROM references.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_jaeger_json, [
    jaeger_json_parse/2,
    jaeger_dict_to_spans/2
]).

:- use_module(library(http/json)).
:- use_module('../core/types').

/**
 * jaeger_json_parse(+Input, -Spans)
 */
jaeger_json_parse(Input, Spans) :-
    (   atom(Input)   -> open_string(Input, Stream)
    ;   string(Input) -> open_string(Input, Stream)
    ;   is_list(Input)-> atom_codes(Atom, Input), open_string(Atom, Stream)
    ),
    call_cleanup(
        (   json_read_dict(Stream, Dict, [value_string_as(atom)]),
            jaeger_dict_to_spans(Dict, Spans)
        ),
        close(Stream)
    ).

/**
 * jaeger_dict_to_spans(+Dict, -Spans)
 */
jaeger_dict_to_spans(Dict, Spans) :-
    (   get_dict(data, Dict, Traces), is_list(Traces)
    ->  phrase(extract_jaeger_traces(Traces), Spans)
    ;   get_dict(spans, Dict, RawSpans)
    ->  extract_jaeger_spans_with_processes(RawSpans, Dict, Spans)
    ;   Spans = []
    ).

extract_jaeger_traces([]) --> [].
extract_jaeger_traces([TraceDict|Rest]) -->
    {
        (   get_dict(spans, TraceDict, RawSpans) -> true ; RawSpans = [] ),
        extract_jaeger_spans_with_processes(RawSpans, TraceDict, Converted)
    },
    list_to_diff(Converted),
    extract_jaeger_traces(Rest).

list_to_diff([]) --> [].
list_to_diff([H|T]) --> [H], list_to_diff(T).

extract_jaeger_spans_with_processes(RawSpans, ContextDict, Converted) :-
    (   get_dict(processes, ContextDict, ProcDict) -> true ; ProcDict = _{} ),
    get_or_default(traceID, ContextDict, '', DefaultTraceId),
    maplist(convert_jaeger_span(ProcDict, DefaultTraceId), RawSpans, Converted).

convert_jaeger_span(ProcDict, DefaultTraceId, SpanDict, Span) :-
    get_or_default(traceID, SpanDict, DefaultTraceId, TraceId),
    get_or_default(spanID, SpanDict, '', SpanId),
    get_or_default(operationName, SpanDict, 'unnamed-op', Name),
    
    extract_jaeger_parent(SpanDict, ParentId),
    extract_jaeger_service(SpanDict, ProcDict, ServiceName),
    
    get_or_default(startTime, SpanDict, 0, StartUs),
    get_or_default(duration, SpanDict, 0, DurationUs),
    EndUs is StartUs + DurationUs,
    
    extract_jaeger_tags(SpanDict, Tags, StatusCode),
    
    span_create(TraceId, SpanId, ParentId, ServiceName, Name, StartUs, EndUs, StatusCode, Tags, Span).

extract_jaeger_parent(SpanDict, ParentId) :-
    (   get_dict(references, SpanDict, Refs),
        is_list(Refs),
        member(Ref, Refs),
        get_dict(refType, Ref, Type),
        (Type = 'CHILD_OF' ; Type = 'FOLLOWS_FROM'),
        get_dict(spanID, Ref, ParentId)
    ->  true
    ;   ParentId = ''
    ), !.

extract_jaeger_service(SpanDict, ProcDict, ServiceName) :-
    (   get_dict(processID, SpanDict, Pid),
        get_dict(Pid, ProcDict, ProcInfo),
        get_dict(serviceName, ProcInfo, ServiceName)
    ->  true
    ;   ServiceName = 'unnamed-service'
    ), !.

extract_jaeger_tags(SpanDict, Tags, StatusCode) :-
    (   get_dict(tags, SpanDict, TagList), is_list(TagList)
    ->  findall(K=V, (
            member(Tag, TagList),
            get_dict(key, Tag, K),
            get_dict(value, Tag, V)
        ), Tags),
        (   member(error=true, Tags) -> StatusCode = 2
        ;   member('error'=1, Tags)    -> StatusCode = 2
        ;   StatusCode = 1
        )
    ;   Tags = [], StatusCode = 0
    ).

get_or_default(Key, Dict, Default, Value) :-
    (   get_dict(Key, Dict, V) -> Value = V ; Value = Default ).
