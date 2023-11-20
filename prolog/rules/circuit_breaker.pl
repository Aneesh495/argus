/*
 * Module: argus_rule_circuit_breaker
 * Purpose: Detection and abductive diagnosis of circuit breaker flapping and premature tripping.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_rule_circuit_breaker, [
    diagnose_circuit_breaker/4
]).

:- use_module(library(lists)).
:- use_module('../core/types').
:- use_module('../engine/hypothesis').

/**
 * diagnose_circuit_breaker(+Spans, +Metrics, +Logs, -Hypotheses)
 */
diagnose_circuit_breaker(Spans, Metrics, Logs, Hypotheses) :-
    findall(Hyp, (
        (   detect_cb_from_spans(Spans, Hyp)
        ;   detect_cb_from_metrics(Metrics, Hyp)
        ;   detect_cb_from_logs(Logs, Hyp)
        )
    ), Raw),
    sort(Raw, Hypotheses).

detect_cb_from_spans(Spans, Hyp) :-
    member(Span, Spans),
    span_service(Span, Svc),
    (   span_attribute_get(Span, 'circuit_breaker.state', 'OPEN')
    ;   span_attribute_get(Span, 'error.type', 'CircuitBreakerOpenException')
    ),
    candidate_hypothesis(circuit_breaker_flapping, Svc, 0.35, [], H0),
    evidence_add(H0, "Short-circuit execution rejecting requests via OPEN circuit state", 4.5, Hyp).

detect_cb_from_metrics(Metrics, Hyp) :-
    member(metric(MetricName, Val, Labels, _), Metrics),
    sub_atom(MetricName, _, _, _, 'circuit_breaker_state_transitions'),
    member(service=Svc, Labels),
    Val > 10, % frequent state flips
    candidate_hypothesis(circuit_breaker_flapping, Svc, 0.4, [], H0),
    evidence_add(H0, format_atom("Circuit breaker fluttered through ~w state transitions", [Val]), 4.2, Hyp).

detect_cb_from_logs(Logs, Hyp) :-
    member(log_record(_, _, Svc, Msg, _, _, _), Logs),
    (   sub_atom(Msg, _, _, _, 'CircuitBreaker tripped to OPEN')
    ;   sub_atom(Msg, _, _, _, 'Call not permitted by CircuitBreaker')
    ),
    candidate_hypothesis(circuit_breaker_flapping, Svc, 0.45, [], H0),
    evidence_add(H0, "Circuit breaker tripped due to slow calls threshold breach", 4.8, Hyp).

format_atom(Format, Args, Atom) :-
    format(atom(Atom), Format, Args).
