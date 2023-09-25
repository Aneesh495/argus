/*
 * Module: argus_structured_log
 * Purpose: Structured JSON and logfmt log record parser.
 * Correlates log events with distributed traces via trace_id and span_id.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_structured_log, [
    parse_log_line/2,
    parse_log_stream/2,
    log_correlate_with_spans/3
]).

:- use_module(library(http/json)).
:- use_module(library(dcg/basics)).
:- use_module(library(lists)).
:- use_module('../core/types').

/**
 * parse_log_line(+Line, -LogRecord)
 * Parses JSON line or logfmt string into:
 * log_record(TimestampUs, Level, Service, Message, TraceId, SpanId, Attrs)
 */
parse_log_line(Line, LogRecord) :-
    % First attempt fast JSON parsing
    (   atom(Line) -> open_string(Line, Stream) ; string(Line) -> open_string(Line, Stream) ),
    call_cleanup(
        catch(json_read_dict(Stream, Dict, [value_string_as(atom)]), _, fail),
        close(Stream)
    ),
    !,
    dict_to_log_record(Dict, LogRecord).
parse_log_line(Line, LogRecord) :-
    % Fallback to logfmt DCG parser
    to_codes(Line, Codes),
    phrase(logfmt_dcg(Pairs), Codes),
    pairs_to_log_record(Pairs, LogRecord),
    !.

dict_to_log_record(Dict, log_record(TsUs, Level, Service, Msg, TraceId, SpanId, Attrs)) :-
    get_or_default(timestamp, Dict, 0, RawTs),
    (   integer(RawTs) -> TsUs = RawTs
    ;   atom(RawTs)    -> (atom_number(RawTs, N) -> TsUs = N ; TsUs = 0)
    ;   TsUs = 0
    ),
    get_or_default(level, Dict, 'INFO', Level),
    get_or_default(service, Dict, 'unknown', Service),
    get_or_default(message, Dict, '', Msg),
    get_or_default(trace_id, Dict, '', TraceId),
    get_or_default(span_id, Dict, '', SpanId),
    dict_pairs(Dict, _, Pairs),
    findall(K=V, (member(K-V, Pairs), \+ member(K, [timestamp, level, service, message, trace_id, span_id])), Attrs).

pairs_to_log_record(Pairs, log_record(TsUs, Level, Service, Msg, TraceId, SpanId, Attrs)) :-
    (   member(ts=RawTs, Pairs)
    ->  (atom_number(RawTs, N) -> TsUs = N ; TsUs = 0)
    ;   TsUs = 0
    ),
    (   member(level=Level, Pairs) -> true ; Level = 'INFO' ),
    (   member(service=Service, Pairs) -> true ; Service = 'unknown' ),
    (   member(msg=Msg, Pairs) -> true ; member(message=Msg, Pairs) -> true ; Msg = '' ),
    (   member(trace_id=TraceId, Pairs) -> true ; TraceId = '' ),
    (   member(span_id=SpanId, Pairs) -> true ; SpanId = '' ),
    findall(K=V, (member(K=V, Pairs), \+ member(K, [ts, level, service, msg, message, trace_id, span_id])), Attrs).

logfmt_dcg([K=V|Rest]) -->
    whites,
    logfmt_ident(KCodes),
    "=",
    logfmt_val(VCodes),
    whites,
    {
        atom_codes(K, KCodes),
        atom_codes(V, VCodes)
    },
    (   logfmt_dcg(Rest)
    ;   { Rest = [] }
    ).
logfmt_dcg([]) --> whites, eos.

logfmt_ident([C|Cs]) -->
    [C],
    { C \= 0'=, C \= 0' , C \= 0'\t, C \= 0'\n },
    (   logfmt_ident(Cs)
    ;   { Cs = [] }
    ).

logfmt_val(VCodes) -->
    "\"",
    string_without("\"", VCodes),
    "\"".
logfmt_val([C|Cs]) -->
    [C],
    { C \= 0' , C \= 0'\t, C \= 0'\n },
    (   logfmt_val(Cs)
    ;   { Cs = [] }
    ).

parse_log_stream(Stream, Records) :-
    read_line_to_string(Stream, Line),
    (   Line == end_of_file
    ->  Records = []
    ;   (   parse_log_line(Line, Record)
        ->  Records = [Record|Rest]
        ;   Records = Rest
        ),
        parse_log_stream(Stream, Rest)
    ).

/**
 * log_correlate_with_spans(+Logs, +Spans, -CorrelatedEvents)
 */
log_correlate_with_spans(Logs, Spans, Correlated) :-
    findall(event(TsUs, Msg, [level=Level, service=Service, span_id=SpanId|Attrs]), (
        member(log_record(TsUs, Level, Service, Msg, TraceId, SpanId, Attrs), Logs),
        member(Span, Spans),
        span_trace_id(Span, TraceId),
        (SpanId == '' ; span_id(Span, SpanId))
    ), Correlated).

get_or_default(Key, Dict, Default, Value) :-
    (   get_dict(Key, Dict, V) -> Value = V ; Value = Default ).

to_codes(Input, Codes) :-
    (   is_list(Input)  -> Codes = Input
    ;   atom(Input)     -> atom_codes(Input, Codes)
    ;   string(Input)   -> string_codes(Input, Codes)
    ).
