/*
 * Module: argus_envoy_filter
 * Purpose: Emits Envoy Proxy and Istio EnvoyFilter rate limiting and retry configurations.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_envoy_filter, [
    render_envoy_filter_yaml/4
]).

/**
 * render_envoy_filter_yaml(+Service, +MaxRetries, +BackoffMs, -YamlOutput)
 */
render_envoy_filter_yaml(Service, MaxRetries, BackoffMs, Yaml) :-
    format(atom(Yaml),
"apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: ~w-remediation-filter
  namespace: default
spec:
  workloadSelector:
    labels:
      app: ~w
  configPatches:
  - applyTo: HTTP_ROUTE
    match:
      context: SIDECAR_OUTBOUND
    patch:
      operation: MERGE
      value:
        route:
          retry_policy:
            retry_on: '5xx,connect-failure,refused-stream'
            num_retries: ~w
            retry_back_off:
              base_interval: ~wms
              max_interval: 1000ms
",
           [Service, Service, MaxRetries, BackoffMs]).
