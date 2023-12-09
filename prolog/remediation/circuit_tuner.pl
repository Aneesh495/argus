/*
 * Module: argus_circuit_tuner
 * Purpose: Emits Resilience4j and Polly circuit breaker tuning configurations.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_circuit_tuner, [
    render_resilience4j_yaml/5
]).

/**
 * render_resilience4j_yaml(+InstanceName, +SlidingWindow, +MinCalls, +FailureRateThreshold, -Yaml)
 */
render_resilience4j_yaml(InstanceName, SlidingWindow, MinCalls, FailureRateThreshold, Yaml) :-
    format(atom(Yaml),
"resilience4j.circuitbreaker:
  instances:
    ~w:
      slidingWindowType: COUNT_BASED
      slidingWindowSize: ~w
      minimumNumberOfCalls: ~w
      failureRateThreshold: ~1f
      slowCallRateThreshold: 70.0
      slowCallDurationThreshold: 2000ms
      waitDurationInOpenState: 10000ms
      permittedNumberOfCallsInHalfOpenState: 10
      automaticTransitionFromOpenToHalfOpenEnabled: true
",
           [InstanceName, SlidingWindow, MinCalls, FailureRateThreshold]).
