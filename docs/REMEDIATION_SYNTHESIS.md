# Automated Remediation Policy Synthesis

Diagnosing the root cause of an incident is only half the battle. In modern infrastructure, operators need verified, machine-executable configuration changes that immediately mitigate ongoing outages and prevent recurrence.

Argus integrates automated remediation synthesis directly into its diagnostic pipeline. Rather than outputting passive text recommendations, Argus uses **queueing theory (Little's Law)** and **constraint logic** to compute provably safe configuration parameters, generating ready-to-apply infrastructure manifests.

---

## 1. Capacity Sizing via Little's Law

In queueing theory, **Little's Law** states that the long-term average number of items $L$ in a stationary queueing system is equal to the long-term average effective arrival rate $\lambda$ multiplied by the average time $W$ that an item spends in the system:

$$L = \lambda \cdot W$$

### 1.1 Microservice Concurrency & Pool Sizing
In a distributed microservice:
- $\lambda$: Ingress request arrival rate (requests per second).
- $W$: Service latency residence time (seconds per request, evaluated at $p99$ to absorb tail latency).
- $L$: Required internal concurrent execution capacity (database connections, HTTP client sockets, thread pool workers).

When upstream arrival rate spikes or downstream latency degrades, a system whose capacity $C < \lambda \cdot W_{p99}$ enters unbounded queueing, triggering cascade failures.

### 1.2 Mathematical Formulation in Argus (`prolog/remediation/synthesizer.pl`)
Argus calculates the required capacity with safety headroom:

$$\text{Capacity}_{\text{synthesized}} = \left\lceil \lambda_{\text{peak}} \cdot W_{p99} \cdot (1 + \text{Headroom}) \right\rceil$$

Where:
- $\text{Headroom} = 0.50$ (50% surge buffer to absorb bursts up to three standard deviations above mean arrival rate).

For example, for a database service with $\lambda = 120\text{ req/sec}$ and $W_{p99} = 0.085\text{ sec}$ (85ms):
$$\text{Base Concurrency} = 120 \times 0.085 = 10.2$$
$$\text{Synthesized Pool Size} = \lceil 10.2 \times 1.5 \rceil = 16\text{ connections}$$

If the existing connection pool was configured to 5 connections, the service had a structural capacity deficit of 11 connections, directly causing the observed connection acquisition timeout.

---

## 2. Token Bucket Rate Limiting Derivation

To mitigate retry storms and protect downstream microservices without shedding legitimate user traffic, Argus synthesizes token bucket parameters:

$$\text{Bucket Capacity } B = \lceil \text{Peak Burst Rate} \cdot \text{Burst Duration} \rceil$$
$$\text{Refill Rate } R = \text{Sustained Capacity Rate}$$

```prolog
derive_token_bucket(TargetRPS, PeakBurstRPS, BurstWindowSecs, Capacity, RefillRate) :-
    Capacity is ceil(PeakBurstRPS * BurstWindowSecs),
    RefillRate is TargetRPS.
```

---

## 3. Infrastructure Manifest Generators

Argus compiles synthesized numerical parameters into declarative production configurations across multiple target systems.

### 3.1 Istio EnvoyFilter YAML (`prolog/remediation/envoy_filter.pl`)
For service mesh traffic control, Argus emits Kubernetes `networking.istio.io/v1alpha3` `EnvoyFilter` manifests:

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: argus-remediate-inventory-db
  namespace: default
spec:
  workloadSelector:
    labels:
      app: inventory-db
  configPatches:
    - applyTo: CLUSTER
      match:
        context: SIDECAR_OUTBOUND
        cluster:
          service: inventory-db.default.svc.cluster.local
      patch:
        operation: MERGE
        value:
          circuit_breakers:
            thresholds:
              - priority: DEFAULT
                max_connections: 64
                max_pending_requests: 128
                max_requests: 1024
                max_retries: 1
```

### 3.2 Kubernetes Deployment RFC 6902 JSON Patch (`prolog/remediation/k8s_patch.pl`)
When the diagnosed root cause is Linux CFS CPU throttling or JVM heap exhaustion, Argus generates standard JSON Patch operations:

```json
[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/limits/memory",
    "value": "4Gi"
  },
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/requests/memory",
    "value": "2Gi"
  },
  {
    "op": "remove",
    "path": "/spec/template/spec/containers/0/resources/limits/cpu"
  }
]
```

Removing hard CPU limits eliminates the CFS quota throttling pauses while preserving memory safety limits.

### 3.3 Resilience4j Circuit Breaker Tuner (`prolog/remediation/circuit_tuner.pl`)
For application-level resilience in JVM services, Argus generates tuned Resilience4j configuration YAMLs:

```yaml
resilience4j.circuitbreaker:
  instances:
    orderService:
      slidingWindowType: COUNT_BASED
      slidingWindowSize: 100
      minimumNumberOfCalls: 20
      failureRateThreshold: 50.0
      slowCallRateThreshold: 75.0
      slowCallDurationThreshold: 1500ms
      waitDurationInOpenState: 15000ms
      permittedNumberOfCallsInHalfOpenState: 10
      automaticTransitionFromOpenToHalfOpenEnabled: true
```

### 3.4 Chaos Mesh & Toxiproxy Incident Reproduction (`prolog/remediation/chaos_manifest.pl`)
A critical requirement of modern Site Reliability Engineering is ensuring that a proposed fix actually resolves the issue and prevents regression.

Argus automatically generates **Chaos Mesh** and **Toxiproxy** definitions that reproduce the exact fault profile in pre-production staging:

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: argus-reproduce-retry-storm
  namespace: staging
spec:
  action: delay
  mode: one
  selector:
    namespaces:
      - staging
    labelSelectors:
      app: inventory-db
  delay:
    latency: "250ms"
    jitter: "50ms"
    correlation: "50"
  duration: "5m"
```

Running this chaos test against the cluster before applying the patch reproduces the outage. Applying the synthesized EnvoyFilter and re-running the chaos test verifies that the system remains stable, proving the efficacy of the remediation before pushing to production.
