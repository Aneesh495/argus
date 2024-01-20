# ADR 0006: Declarative Remediation Policy Synthesis

## Status
Accepted

## Context
Automated diagnostic systems often end their workflow by printing unstructured natural language descriptions of the detected problem. Site Reliability Engineers must then manually translate these descriptions into concrete infrastructure changes (Kubernetes resource limits, Istio EnvoyFilter policies, circuit breaker thresholds), introducing human latency and typographical errors during high-severity incidents.

## Decision
We implemented a declarative policy synthesizer (`prolog/remediation/synthesizer.pl`) that couples diagnostic root causes with operational manifest generators:
1. **Queueing Theory Formulations**: Little's Law ($L = \lambda W$) and token bucket equations derive exact numerical parameters (connection pool sizes, rate limits, burst allowances).
2. **Infrastructure Compilation**: Domain generators output production-ready configuration artifacts:
   - Istio EnvoyFilter YAML (`prolog/remediation/envoy_filter.pl`)
   - Kubernetes Deployment RFC 6902 JSON Patches (`prolog/remediation/k8s_patch.pl`)
   - Resilience4j Circuit Breaker YAML (`prolog/remediation/circuit_tuner.pl`)
3. **Automated Incident Reproduction**: Synthesizes Chaos Mesh and Toxiproxy manifests (`prolog/remediation/chaos_manifest.pl`) to reproduce the fault in staging CI/CD environments for post-mortem regression testing.

## Consequences
- **Positive**: Directly closes the loop between diagnosis and operational remediation.
- **Positive**: Generated artifacts are fully auditable and version-controllable.
- **Negative**: Generated manifests require platform-specific schemas.
- **Mitigation**: Generated manifests strictly adhere to upstream API specifications (Istio v1alpha3, Kubernetes apps/v1, Chaos Mesh v1alpha1).
