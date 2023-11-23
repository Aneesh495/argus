/*
 * Module: argus_rule_disk_io_stall
 * Purpose: Detection and abductive diagnosis of storage IOPS exhaustion and fsync stalls.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_rule_disk_io_stall, [
    diagnose_disk_io_stall/4
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../engine/hypothesis').

/**
 * diagnose_disk_io_stall(+Spans, +Metrics, +Logs, -Hypotheses)
 */
diagnose_disk_io_stall(Spans, Metrics, Logs, Hypotheses) :-
    findall(Hyp, (
        (   detect_disk_from_metrics(Metrics, Hyp)
        ;   detect_disk_from_logs(Logs, Hyp)
        ;   detect_disk_from_spans(Spans, Hyp)
        )
    ), Raw),
    sort(Raw, Hypotheses).

detect_disk_from_metrics(Metrics, Hyp) :-
    member(metric(MetricName, Val, Labels, _), Metrics),
    (   sub_atom(MetricName, _, _, _, 'node_disk_io_time_seconds_total'),
        member(service=Svc, Labels),
        Val >= 0.95 % 95% disk utilization
    ;   sub_atom(MetricName, _, _, _, 'disk_write_latency_ms'),
        member(service=Svc, Labels),
        Val > 500 % > 500ms write latency
    ),
    candidate_hypothesis(storage_io_stall, Svc, 0.4, [], H0),
    evidence_add(H0, "Disk queue pinned at 100% capacity with high write await latency", 4.5, Hyp).

detect_disk_from_logs(Logs, Hyp) :-
    member(log_record(_, Level, Svc, Msg, _, _, _), Logs),
    (Level = 'WARN' ; Level = 'ERROR'),
    (   sub_atom(Msg, _, _, _, 'fsync failed or took longer than')
    ;   sub_atom(Msg, _, _, _, 'WAL write took over')
    ;   sub_atom(Msg, _, _, _, 'slow disk I/O')
    ),
    candidate_hypothesis(storage_io_stall, Svc, 0.45, [], H0),
    evidence_add(H0, "Database WAL flush logged severe fsync latency stall", 4.8, Hyp).

detect_disk_from_spans(Spans, Hyp) :-
    member(Span, Spans),
    span_service(Span, Svc),
    span_attribute_get(Span, 'io.fsync_wait_ms', FsyncMs),
    atom_number_val(FsyncMs, FsyncNum),
    FsyncNum > 1000,
    candidate_hypothesis(storage_io_stall, Svc, 0.35, [], H0),
    evidence_add(H0, format_atom("Direct fsync duration tag: ~w ms", [FsyncNum]), 4.0, Hyp).

format_atom(Format, Args, Atom) :-
    format(atom(Atom), Format, Args).

atom_number_val(Atom, Num) :-
    atom(Atom), !, atom_number(Atom, Num).
atom_number_val(Num, Num) :- number(Num).
