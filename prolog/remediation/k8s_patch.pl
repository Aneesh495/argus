/*
 * Module: argus_k8s_patch
 * Purpose: Emits Kubernetes JSON and YAML deployment patch manifests.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_k8s_patch, [
    render_k8s_resource_patch/4,
    render_k8s_hpa_yaml/4
]).

/**
 * render_k8s_resource_patch(+DeploymentName, +CpuLimit, +MemLimit, -JsonPatch)
 */
render_k8s_resource_patch(DeploymentName, CpuLimit, MemLimit, JsonPatch) :-
    format(atom(JsonPatch),
"{
  \"apiVersion\": \"apps/v1\",
  \"kind\": \"Deployment\",
  \"metadata\": { \"name\": \"~w\" },
  \"spec\": {
    \"template\": {
      \"spec\": {
        \"containers\": [{
          \"name\": \"~w\",
          \"resources\": {
            \"limits\": { \"cpu\": \"~w\", \"memory\": \"~w\" }
          }
        }]
      }
    }
  }
}",
           [DeploymentName, DeploymentName, CpuLimit, MemLimit]).

/**
 * render_k8s_hpa_yaml(+DeploymentName, +MinReplicas, +MaxReplicas, -Yaml)
 */
render_k8s_hpa_yaml(DeploymentName, MinReplicas, MaxReplicas, Yaml) :-
    format(atom(Yaml),
"apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ~w-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ~w
  minReplicas: ~w
  maxReplicas: ~w
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
",
           [DeploymentName, DeploymentName, MinReplicas, MaxReplicas]).
