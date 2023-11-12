/*
 * Module: argus_rule_gc_pause
 * Purpose: Detection and abductive diagnosis of stop-the-world garbage collection pauses.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_rule_gc_pause, [
    diagnose_gc_pause/4
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../engine/hypothesis').

/**
 * diagnose_gc_pause(+Spans, +Metrics, +Logs, -Hypotheses)
 */
diagnose_gc_pause(Spans, Metrics, Logs, Hypotheses) :-
    findall(Hyp, (
        (   detect_gc_from_metrics(Metrics, Hyp)
        ;   detect_gc_from_logs(Logs, Hyp)
        ;   detect_gc_from_spans(Spans, Hyp)
        )
    ), Raw),
    sort(Raw, Hypotheses).

detect_gc_from_metrics(Metrics, Hyp) :-
    member(metric(MetricName, Val, Labels, _), Metrics),
    (   sub_atom(MetricName, _, _, _, 'jvm_gc_pause_seconds'),
        member(service=Svc, Labels),
        Val >= 1.0 % pause >= 1 second
    ;   sub_atom(MetricName, _, _, _, 'go_gc_duration_seconds'),
        member(service=Svc, Labels),
        Val >= 0.5
    ),
    candidate_hypothesis(gc_pause, Svc, 0.4, [], H0),
    evidence_add(H0, format_atom("Stop-the-world GC pause metric spiked to ~2f s", [Val]), 4.5, Hyp).

detect_gc_from_logs(Logs, Hyp) :-
    member(log_record(_, _, Svc, Msg, _, _, _), Logs),
    (   sub_atom(Msg, _, _, _, 'GC pause')
    ;   sub_atom(Msg, _, _, _, 'heartbeat missed during GC')
    ;   sub_atom(Msg, _, _, _, 'Lease lost due to stop-the-world pause')
    ),
    candidate_hypothesis(gc_pause, Svc, 0.45, [], H0),
    evidence_add(H0, "Node dropped cluster lease due to unresponsiveness during GC", 4.8, Hyp).

detect_gc_from_spans(Spans, Hyp) :-
    member(Span, Spans),
    span_service(Span, Svc),
    span_attribute_get(Span, 'gc.pause_duration_ms', PauseMs),
    atom_number_val(PauseMs, PauseNum),
    PauseNum > 1000,
    candidate_hypothesis(gc_pause, Svc, 0.4, [], H0),
    evidence_add(H0, format_atom("Direct GC pause tag recorded: ~w ms", [PauseNum]), 4.0, Hyp).

format_atom(Format, Args, Atom) :-
    format(atom(Atom), Format, Args).

atom_number_val(Atom, Num) :-
    atom(Atom), !, atom_number(Atom, Num).
atom_number_val(Num, Num) :- number(Num).
