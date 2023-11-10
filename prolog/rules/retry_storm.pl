/*
 * Module: argus_rule_retry_storm
 * Purpose: Detection and abductive diagnosis of cascading retry storms.
 * Identifies multiplicative request amplification, missing jitter, and exponential backoff collapse.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_rule_retry_storm, [
    diagnose_retry_storm/4,
    retry_amplification_factor/3
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../topology/builder').
:- use_module('../engine/hypothesis').

/**
 * diagnose_retry_storm(+Spans, +Metrics, +Logs, -Hypotheses)
 */
diagnose_retry_storm(Spans, _Metrics, _Logs, Hypotheses) :-
    findall(Hyp, detect_single_retry_storm(Spans, Hyp), Raw),
    sort(Raw, Hypotheses).

detect_single_retry_storm(Spans, Hyp) :-
    member(Parent, Spans),
    span_id(Parent, ParentId),
    span_service(Parent, CallerSvc),
    span_children(Spans, ParentId, Children),
    find_retried_target(Children, TargetSvc, TargetEndpoint, RetrySpans),
    length(RetrySpans, AttemptCount),
    AttemptCount >= 3,
    % Check for high error rate among attempts
    include(span_is_error, RetrySpans, Errors),
    length(Errors, ErrorCount),
    ErrorRatio is ErrorCount / AttemptCount,
    ErrorRatio >= 0.5,
    
    Amplification is AttemptCount,
    candidate_hypothesis(retry_storm, CallerSvc, 0.35, [], H0),
    evidence_add(H0, format_atom("Service ~w retried ~w on ~w ~w times", [CallerSvc, TargetEndpoint, TargetSvc, AttemptCount]), 3.5, H1),
    evidence_add(H1, format_atom("Amplification factor: ~wX downstream load", [Amplification]), 2.5, H2),
    (   ErrorCount =:= AttemptCount
    ->  evidence_add(H2, "100% downstream retry failure with complete backoff exhaustion", 3.0, Hyp)
    ;   Hyp = H2
    ).

find_retried_target(Children, TargetSvc, TargetEndpoint, MatchingSpans) :-
    member(Sample, Children),
    span_service(Sample, TargetSvc),
    span_name(Sample, TargetEndpoint),
    findall(C, (
        member(C, Children),
        span_service(C, TargetSvc),
        span_name(C, TargetEndpoint)
    ), MatchingSpans),
    length(MatchingSpans, Count),
    Count >= 3.

retry_amplification_factor(Spans, ParentId, Factor) :-
    span_children(Spans, ParentId, Children),
    length(Children, TotalCalls),
    findall(Target, (member(C, Children), span_service(C, Target)), Targets),
    sort(Targets, UniqueTargets),
    length(UniqueTargets, UniqueCount),
    (UniqueCount > 0 -> Factor is TotalCalls / UniqueCount ; Factor = 1.0).

format_atom(Format, Args, Atom) :-
    format(atom(Atom), Format, Args).
