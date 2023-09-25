/*
 * Module: argus_openmetrics
 * Purpose: Prometheus and OpenMetrics text exposition format DCG parser.
 * Ingests metrics (counters, gauges, histograms) and correlates them with trace timelines.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_openmetrics, [
    parse_openmetrics/2,
    parse_openmetrics_line/2
]).

:- use_module(library(dcg/basics)).
:- use_module(library(lists)).

/**
 * parse_openmetrics(+Input, -Metrics)
 * Parses multiline string or codes of OpenMetrics exposition format.
 */
parse_openmetrics(Input, Metrics) :-
    to_codes(Input, Codes),
    phrase(metrics_lines_dcg(Metrics), Codes),
    !.

metrics_lines_dcg([M|Ms]) -->
    whites,
    metric_line(M),
    eol_or_eof,
    !,
    metrics_lines_dcg(Ms).
metrics_lines_dcg(Ms) -->
    whites,
    comment_line,
    eol_or_eof,
    !,
    metrics_lines_dcg(Ms).
metrics_lines_dcg(Ms) -->
    blank_line,
    !,
    metrics_lines_dcg(Ms).
metrics_lines_dcg([]) -->
    whites,
    eos.

comment_line -->
    "#",
    string_without("\n\r", _).

blank_line -->
    whites,
    ("\n" ; "\r\n").

eol_or_eof --> ("\n" ; "\r\n" ; eos).

metric_line(metric(Name, Value, Labels, Timestamp)) -->
    metric_identifier(NameCodes),
    { atom_codes(Name, NameCodes) },
    (   "{"
    ->  labels_dcg(Labels),
        "}"
    ;   { Labels = [] }
    ),
    whites,
    number_val(Value),
    (   whites, number_val(Timestamp)
    ->  { true }
    ;   { Timestamp = 0 }
    ).

metric_identifier([C|Cs]) -->
    [C],
    {
        (   C >= 0'a, C =< 0'z
        ;   C >= 0'A, C =< 0'Z
        ;   C >= 0'0, C =< 0'9
        ;   C =:= 0'_
        ;   C =:= 0':
        )
    },
    (   metric_identifier(Cs)
    ;   { Cs = [] }
    ).

labels_dcg([K=V|Rest]) -->
    whites,
    metric_identifier(KCodes),
    whites,
    "=",
    whites,
    "\"",
    string_without("\"", VCodes),
    "\"",
    whites,
    {
        atom_codes(K, KCodes),
        atom_codes(V, VCodes)
    },
    (   ","
    ->  labels_dcg(Rest)
    ;   { Rest = [] }
    ).
labels_dcg([]) --> [].

number_val(Val) -->
    number(Val).
number_val(Val) -->
    float(Val).

/**
 * parse_openmetrics_line(+Line, -Metric)
 */
parse_openmetrics_line(Line, Metric) :-
    to_codes(Line, Codes),
    phrase(metric_line(Metric), Codes),
    !.

to_codes(Input, Codes) :-
    (   is_list(Input)  -> Codes = Input
    ;   atom(Input)     -> atom_codes(Input, Codes)
    ;   string(Input)   -> string_codes(Input, Codes)
    ).
