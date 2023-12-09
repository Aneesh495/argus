/*
 * Module: argus_chaos_manifest
 * Purpose: Generates Chaos Mesh Kubernetes manifests and Toxiproxy configs to reproduce incidents.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_chaos_manifest, [
    render_chaos_mesh_yaml/4,
    render_toxiproxy_json/4
]).

/**
 * render_chaos_mesh_yaml(+FaultType, +TargetService, +DurationStr, -Yaml)
 */
render_chaos_mesh_yaml(retry_storm, TargetService, Duration, Yaml) :-
    format(atom(Yaml),
"apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: reproduce-retry-storm-~w
  namespace: default
spec:
  action: delay
  mode: all
  selector:
    namespaces: [default]
    labelSelectors:
      app: ~w
  delay:
    latency: '5000ms'
    jitter: '0ms'
  duration: '~w'
",
           [TargetService, TargetService, Duration]).

render_chaos_mesh_yaml(connection_pool_starvation, TargetService, Duration, Yaml) :-
    format(atom(Yaml),
"apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: reproduce-pool-starve-~w
  namespace: default
spec:
  mode: all
  selector:
    namespaces: [default]
    labelSelectors:
      app: ~w
  stressors:
    cpu:
      workers: 4
      load: 100
  duration: '~w'
",
           [TargetService, TargetService, Duration]).

render_chaos_mesh_yaml(network_partition, TargetService, Duration, Yaml) :-
    format(atom(Yaml),
"apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: reproduce-partition-~w
  namespace: default
spec:
  action: partition
  mode: all
  selector:
    namespaces: [default]
    labelSelectors:
      app: ~w
  duration: '~w'
",
           [TargetService, TargetService, Duration]).

render_chaos_mesh_yaml(_, TargetService, Duration, Yaml) :-
    format(atom(Yaml),
"apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: generic-chaos-~w
spec:
  action: pod-kill
  mode: one
  selector:
    labelSelectors:
      app: ~w
  duration: '~w'
",
           [TargetService, TargetService, Duration]).

/**
 * render_toxiproxy_json(+ProxyName, +ToxicType, +LatencyMs, -Json)
 */
render_toxiproxy_json(ProxyName, ToxicType, LatencyMs, Json) :-
    format(atom(Json),
"{
  \"name\": \"~w_latency_toxic\",
  \"type\": \"~w\",
  \"stream\": \"downstream\",
  \"toxicity\": 1.0,
  \"attributes\": {
    \"latency\": ~w,
    \"jitter\": 50
  }
}",
           [ProxyName, ToxicType, LatencyMs]).
