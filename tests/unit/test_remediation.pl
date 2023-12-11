/*
 * Unit tests for Argus remediation synthesis modules:
 * Synthesizer, Envoy Filter, Kubernetes Patches, Circuit Tuner, and Chaos Manifests.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(test_remediation, [
    run_remediation_tests/0
]).

:- use_module(library(plunit)).
:- use_module('../../prolog/core/types').
:- use_module('../../prolog/remediation/synthesizer').
:- use_module('../../prolog/remediation/envoy_filter').
:- use_module('../../prolog/remediation/k8s_patch').
:- use_module('../../prolog/remediation/circuit_tuner').
:- use_module('../../prolog/remediation/chaos_manifest').

run_remediation_tests :-
    run_tests([synthesizer, envoy, k8s, circuit, chaos]).

:- begin_tests(synthesizer).

test(remediation_actions_for_retry_storm) :-
    synthesize_remediation(retry_storm, 'payment-gateway', Actions),
    length(Actions, 2),
    member(remediation(clamp_max_retries, 'payment-gateway', Params), Actions),
    member(max_attempts=2, Params),
    member(jitter='FULL_JITTER', Params),
    !.

test(littles_law_pool_capacity) :-
    derive_pool_capacity(1000, 50, 0.2, Capacity),
    Capacity =:= 60,
    !.

test(token_bucket_derivation) :-
    derive_token_bucket(500, 1.5, Rate, Bucket),
    Rate =:= 500,
    Bucket =:= 750,
    !.

:- end_tests(synthesizer).

:- begin_tests(envoy).

test(envoy_filter_rendering) :-
    render_envoy_filter_yaml('order-service', 2, 150, Yaml),
    sub_atom(Yaml, _, _, _, 'kind: EnvoyFilter'),
    sub_atom(Yaml, _, _, _, 'num_retries: 2'),
    sub_atom(Yaml, _, _, _, 'base_interval: 150ms'),
    !.

:- end_tests(envoy).

:- begin_tests(k8s).

test(k8s_patch_rendering) :-
    render_k8s_resource_patch('auth-deploy', '2000m', '4Gi', Patch),
    sub_atom(Patch, _, _, _, '\"kind\": \"Deployment\"'),
    sub_atom(Patch, _, _, _, '\"cpu\": \"2000m\"'),
    
    render_k8s_hpa_yaml('auth-deploy', 2, 10, HpaYaml),
    sub_atom(HpaYaml, _, _, _, 'kind: HorizontalPodAutoscaler'),
    sub_atom(HpaYaml, _, _, _, 'minReplicas: 2'),
    sub_atom(HpaYaml, _, _, _, 'maxReplicas: 10'),
    !.

:- end_tests(k8s).

:- begin_tests(circuit).

test(resilience4j_rendering) :-
    render_resilience4j_yaml('inventoryService', 100, 25, 50.0, Yaml),
    sub_atom(Yaml, _, _, _, 'slidingWindowSize: 100'),
    sub_atom(Yaml, _, _, _, 'minimumNumberOfCalls: 25'),
    sub_atom(Yaml, _, _, _, 'failureRateThreshold: 50.0'),
    !.

:- end_tests(circuit).

:- begin_tests(chaos).

test(chaos_mesh_and_toxiproxy_rendering) :-
    render_chaos_mesh_yaml(retry_storm, 'payment-svc', '5m', ChaosYaml),
    sub_atom(ChaosYaml, _, _, _, 'kind: NetworkChaos'),
    sub_atom(ChaosYaml, _, _, _, 'latency: \'5000ms\''),
    
    render_toxiproxy_json('db_proxy', 'latency', 300, ToxicJson),
    sub_atom(ToxicJson, _, _, _, '\"latency\": 300'),
    !.

:- end_tests(chaos).
