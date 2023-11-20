/*
 * Module: argus_rule_memory_pressure
 * Purpose: Detection and abductive diagnosis of cgroup CPU CFS throttling and memory pressure.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_rule_memory_pressure, [
    diagnose_memory_pressure/4
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../engine/hypothesis').

/**
 * diagnose_memory_pressure(+Spans, +Metrics, +Logs, -Hypotheses)
 */
diagnose_memory_pressure(Spans, Metrics, Logs, Hypotheses) :-
    findall(Hyp, (
        (   detect_pressure_from_metrics(Metrics, Hyp)
        ;   detect_pressure_from_logs(Logs, Hyp)
        ;   detect_pressure_from_spans(Spans, Hyp)
        )
    ), Raw),
    sort(Raw, Hypotheses).

detect_pressure_from_metrics(Metrics, Hyp) :-
    member(metric(MetricName, Val, Labels, _), Metrics),
    (   sub_atom(MetricName, _, _, _, 'container_cpu_cfs_throttled_periods_total'),
        member(service=Svc, Labels),
        Val > 50 % high CPU throttling
    ;   sub_atom(MetricName, _, _, _, 'container_memory_working_set_bytes'),
        member(service=Svc, Labels),
        Val >= 0.95 % memory working set near limit
    ),
    candidate_hypothesis(cgroup_resource_throttling, Svc, 0.4, [], H0),
    evidence_add(H0, "Container CFS scheduler throttled CPU periods heavily", 4.3, Hyp).

detect_pressure_from_logs(Logs, Hyp) :-
    member(log_record(_, Level, Svc, Msg, _, _, _), Logs),
    (Level = 'FATAL' ; Level = 'ERROR'),
    (   sub_atom(Msg, _, _, _, 'OOMKilled')
    ;   sub_atom(Msg, _, _, _, 'Out of memory: Kill process')
    ;   sub_atom(Msg, _, _, _, 'java.lang.OutOfMemoryError')
    ),
    candidate_hypothesis(cgroup_resource_throttling, Svc, 0.5, [], H0),
    evidence_add(H0, "Container terminated by Linux kernel OOM killer", 5.0, Hyp).

detect_pressure_from_spans(Spans, Hyp) :-
    member(Span, Spans),
    span_service(Span, Svc),
    span_attribute_get(Span, 'container.cpu.throttled_percent', Pct),
    atom_number_val(Pct, PctNum),
    PctNum > 40.0,
    candidate_hypothesis(cgroup_resource_throttling, Svc, 0.4, [], H0),
    evidence_add(H0, format_atom("CPU quota throttled for ~1f% of request lifecycle", [PctNum]), 4.0, Hyp).

format_atom(Format, Args, Atom) :-
    format(atom(Atom), Format, Args).

atom_number_val(Atom, Num) :-
    atom(Atom), !, atom_number(Atom, Num).
atom_number_val(Num, Num) :- number(Num).
