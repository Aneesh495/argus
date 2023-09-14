/*
 * Module: argus_w3c_trace_context
 * Purpose: Definite Clause Grammar (DCG) parser and formatter for W3C TraceContext specification.
 * Handles traceparent (version-traceid-parentid-flags) and tracestate key-value pairs.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_w3c_trace_context, [
    parse_traceparent/4,
    format_traceparent/4,
    parse_tracestate/2,
    format_tracestate/2
]).

:- use_module(library(dcg/basics)).
:- use_module(library(lists)).

/**
 * parse_traceparent(+Input, -TraceId, -ParentId, -TraceFlags)
 * Ingests string, atom, or code list and parses W3C traceparent header:
 * e.g., "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01".
 */
parse_traceparent(Input, TraceId, ParentId, TraceFlags) :-
    to_codes(Input, Codes),
    phrase(traceparent_dcg(TraceId, ParentId, TraceFlags), Codes),
    !.

traceparent_dcg(TraceId, ParentId, TraceFlags) -->
    hex_byte(Version),
    "-",
    hex_bytes(16, TraceIdCodes),
    "-",
    hex_bytes(8, ParentIdCodes),
    "-",
    hex_byte(TraceFlags),
    {
        Version =:= 0, % Version 00 is W3C Recommendation Level 1
        atom_codes(TraceId, TraceIdCodes),
        atom_codes(ParentId, ParentIdCodes)
    }.

hex_byte(Val) -->
    hex_digit(D1),
    hex_digit(D2),
    { Val is (D1 << 4) + D2 }.

hex_bytes(0, []) --> !.
hex_bytes(N, [C1, C2 | Rest]) -->
    hex_char(C1),
    hex_char(C2),
    { N1 is N - 1 },
    hex_bytes(N1, Rest).

hex_char(C) -->
    [C],
    {
        (   C >= 0'0, C =< 0'9
        ;   C >= 0'a, C =< 0'f
        ;   C >= 0'A, C =< 0'F
        )
    }.

hex_digit(Val) -->
    [C],
    {
        (   C >= 0'0, C =< 0'9 -> Val is C - 0'0
        ;   C >= 0'a, C =< 0'f -> Val is C - 0'a + 10
        ;   C >= 0'A, C =< 0'F -> Val is C - 0'A + 10
        )
    }.

/**
 * format_traceparent(+TraceId, +ParentId, +Flags, -HeaderAtom)
 */
format_traceparent(TraceId, ParentId, Flags, Header) :-
    format(atom(Header), "00-~w-~w-~|~`0t~16r~2+", [TraceId, ParentId, Flags]).

/**
 * parse_tracestate(+Input, -Entries)
 * Parses comma-separated vendor key=value list:
 * e.g., "rojo=1,congo=4,argus=ratio:0.95".
 */
parse_tracestate(Input, Entries) :-
    to_codes(Input, Codes),
    phrase(tracestate_dcg(Entries), Codes),
    !.

tracestate_dcg([Entry|Rest]) -->
    whites,
    tracestate_entry(Entry),
    whites,
    (   ","
    ->  tracestate_dcg(Rest)
    ;   whites,
        eos,
        { Rest = [] }
    ).
tracestate_dcg([]) -->
    whites,
    eos.

tracestate_entry(Key=Value) -->
    tracestate_key(KeyCodes),
    "=",
    tracestate_value(ValCodes),
    {
        atom_codes(Key, KeyCodes),
        atom_codes(Value, ValCodes)
    }.

tracestate_key([C|Cs]) -->
    [C],
    { C =\= 61, C =\= 44, C =\= 32, C =\= 9 },
    (   tracestate_key(Cs)
    ;   { Cs = [] }
    ).

tracestate_value([C|Cs]) -->
    [C],
    { C =\= 44, C =\= 32, C =\= 9, C =\= 10 },
    (   tracestate_value(Cs)
    ;   { Cs = [] }
    ).

/**
 * format_tracestate(+Entries, -HeaderAtom)
 */
format_tracestate(Entries, Header) :-
    maplist(format_pair, Entries, PairAtoms),
    atomic_list_concat(PairAtoms, ',', Header).

format_pair(Key=Val, Atom) :-
    format(atom(Atom), "~w=~w", [Key, Val]).

to_codes(Input, Codes) :-
    (   is_list(Input)  -> Codes = Input
    ;   atom(Input)     -> atom_codes(Input, Codes)
    ;   string(Input)   -> string_codes(Input, Codes)
    ).
