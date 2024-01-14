# Distributed Failure Mode Catalog

Argus includes formal detection rules, structural causal models, and remediation templates for 12 canonical distributed systems failure modes. Each failure mode is codified as a declarative Prolog rule module that cross-correlates OpenTelemetry trace spans, OpenMetrics/Prometheus counters, and structured log events.

---

## Catalog Summary Matrix

| ID | Failure Mode | Primary Span Signature | Primary Metric Signature | Primary Log Signature |
|:---|:---|:---|:---|:---|
| 01 | **Retry Storm Cascade** | Repeated identical client calls with exponential backoff or tight spacing | `http_requests_total` spike with low unique trace IDs | `client_retry`, `retry_exhausted` |
| 02 | **Connection Pool Starvation** | Long span duration before DB query start; zero DB work | `db_pool_wait_duration_seconds > 1.0` | `pool_timeout`, `Connection acquisition timeout` |
| 03 | **Kafka Consumer Lag** | Time delta between message production and consumption exceeds SLA | `kafka_consumer_lag_records > 1000` | `rebalance_in_progress`, `commit_failed` |
| 04 | **JVM Stop-The-World GC** | All concurrent spans in a JVM pause simultaneously for identical duration | `jvm_gc_pause_seconds_sum > 1.0` | `GC pause (G1 Evacuation Pause)`, `safepoint` |
| 05 | **Thread Pool Exhaustion** | Tasks spend seconds in executor queue before thread assignment | `executor_queue_depth > 500`, `active_threads == max` | `RejectedExecutionException`, `pool full` |
| 06 | **Postgres Lock Deadlock** | Concurrently intersecting transactions aborted by engine | `postgresql_locks_waiting > 0` | `deadlock detected`, `Process X waits for ShareLock` |
| 07 | **Circuit Breaker Flutter** | Rapid state oscillation between CLOSED, OPEN, and HALF_OPEN | `resilience4j_circuitbreaker_state` frequency > 0.1 Hz | `circuit_state_transition`, `short-circuited` |
| 08 | **Linux CFS Quota Throttling** | High span duration with low host CPU usage but high container throttled periods | `container_cpu_cfs_throttled_periods_total > 500` | `cgroup: cpu limit exceeded` |
| 09 | **Cache Stampede (Thundering Herd)** | Cache key expiry followed by thousands of identical concurrent DB queries | `cache_miss_total` spike + DB read saturation | `cache_miss`, `cache_lock_contention` |
| 10 | **Asymmetric Network Partition** | Heartbeat timeouts between minority and majority Raft/Consul nodes | `raft_heartbeat_timeout_total > 5` | `dropped message to peer`, `leader election timeout` |
| 11 | **Disk I/O Stall** | High sync/fsync span duration with low CPU and normal memory | `node_disk_io_time_weighted_seconds > 2.0` | `blocked for more than 120 seconds`, `task hung` |
| 12 | **Distributed 2PC / Sagas Timeout** | Coordinator span exceeds timeout waiting on participant PREPARE/COMMIT | `saga_participant_pending > 0` | `saga_timeout`, `two_phase_commit_abort` |

---

## Detailed Specifications

### 01. Retry Storm Cascade
- **Module**: `prolog/rules/retry_storm.pl`
- **Mechanism**: When a downstream microservice suffers a brief latency hiccup, uncoordinated upstream clients with aggressive retry policies re-transmit failed requests. The amplified request volume overwhelms the downstream service, turning a minor transient degradation into total cluster failure.
- **Prolog Inference Rule**:
  ```prolog
  rule_retry_storm(Spans, Service, Target, RetryCount) :-
      span_repeated_calls(Spans, Service, Target, RetryCount),
      RetryCount >= 3,
      span_has_transient_error(Spans, Target).
  ```
- **Synthesized Remediation**:
  - Istio `EnvoyFilter` capping retry attempts to 1 and enforcing exponential jittered backoff.
  - Token-bucket retry budget limiting retries to at most 10% of total ingress requests.

---

### 02. Connection Pool Starvation
- **Module**: `prolog/rules/connection_pool.pl`
- **Mechanism**: Applications acquire database connections from a fixed pool (e.g., HikariCP, PgBouncer). When query latency rises or application threads fail to return connections promptly, all connections are occupied. Incoming worker threads block waiting for connections until acquisition timeouts fire.
- **Prolog Inference Rule**:
  ```prolog
  rule_connection_pool(Spans, Metrics, Logs, Service) :-
      (   member(metric_sample(WaitMetric, Labels, WaitTime, _), Metrics),
          sub_atom(WaitMetric, _, _, _, 'pool_wait'),
          WaitTime > 1.0
      ;   member(log_entry(_, Service, Msg, error), Logs),
          sub_atom(Msg, _, _, _, 'Connection acquisition timeout')
      ).
  ```
- **Synthesized Remediation**:
  - Little's Law capacity recalculation: $\text{Capacity} = \lambda \cdot W_{p99} \cdot 1.5$.
  - Envoy circuit breaker `max_connections` matching database max worker capacity.

---

### 03. Kafka Consumer Lag Saturation
- **Module**: `prolog/rules/queue_saturation.pl`
- **Mechanism**: Message producer throughput exceeds consumer processing capacity, or frequent consumer group rebalances cause stop-the-world partition reassignments. Unprocessed message lag grows monotonically, breaching end-to-end processing SLAs.
- **Prolog Inference Rule**:
  ```prolog
  rule_queue_saturation(Spans, Metrics, Service) :-
      member(metric_sample(LagMetric, _, LagValue, _), Metrics),
      sub_atom(LagMetric, _, _, _, 'consumer_lag'),
      LagValue > 1000.
  ```
- **Synthesized Remediation**:
  - HorizontalPodAutoscaler patch scaling consumer replica count proportionally to current lag rate.
  - Kafka consumer fetch max bytes tuning to prevent out-of-memory pauses.

---

### 04. JVM Stop-The-World GC Pauses
- **Module**: `prolog/rules/gc_pause.pl`
- **Mechanism**: Heap allocation rate outpaces concurrent garbage collection marking, forcing the JVM into a full stop-the-world compaction pause. During this window, all application threads freeze, network socket buffers fill, and cluster peers assume the node has died due to missing heartbeats.
- **Prolog Inference Rule**:
  ```prolog
  rule_gc_pause(Spans, Metrics, Service) :-
      member(metric_sample(GCMetric, _, Duration, _), Metrics),
      sub_atom(GCMetric, _, _, _, 'jvm_gc_pause'),
      Duration > 1.0.
  ```
- **Synthesized Remediation**:
  - Kubernetes memory request and limit increase.
  - JVM flag tuning: Transition to ZGC / Shenandoah with concurrent uncommit.

---

### 05. Thread Pool Saturation / Worker Starvation
- **Module**: `prolog/rules/thread_exhaustion.pl`
- **Mechanism**: Asynchronous executors or HTTP worker thread pools become saturated due to blocking synchronous I/O or downstream lock contention. Incoming tasks accumulate in unbounded or bounded queues, triggering thread pool rejection exceptions.
- **Prolog Inference Rule**:
  ```prolog
  rule_thread_exhaustion(Spans, Metrics, Logs, Service) :-
      member(log_entry(_, Service, Msg, error), Logs),
      sub_atom(Msg, _, _, _, 'RejectedExecutionException').
  ```
- **Synthesized Remediation**:
  - Convert blocking calls to non-blocking asynchronous dispatch.
  - Increase core thread pool size and set bounded queue capacity with caller-runs rejection policy.

---

### 06. Relational Database Lock Contention / Deadlocks
- **Module**: `prolog/rules/lock_contention.pl`
- **Mechanism**: Multiple concurrent transactions acquire row or table locks in conflicting order (e.g., Tx 1 locks Row A then requests Row B; Tx 2 locks Row B then requests Row A). The database deadlock detector aborts one transaction, creating request failures.
- **Prolog Inference Rule**:
  ```prolog
  rule_lock_contention(Spans, Metrics, Logs, Service) :-
      member(log_entry(_, Service, Msg, error), Logs),
      sub_atom(Msg, _, _, _, 'deadlock detected').
  ```
- **Synthesized Remediation**:
  - Enforce global deterministic lock acquisition ordering across transactions.
  - Configure statement timeouts and exponential retry jitter on serialization failures.

---

### 07. Circuit Breaker Flutter
- **Module**: `prolog/rules/circuit_breaker.pl`
- **Mechanism**: A circuit breaker configured with an excessively narrow evaluation window or low call volume threshold trips open upon encountering transient errors, then immediately attempts recovery in half-open state. The sudden burst of probe requests immediately re-trips the breaker, causing high-frequency oscillation between open and closed states.
- **Prolog Inference Rule**:
  ```prolog
  rule_circuit_breaker(Spans, Metrics, Logs, Service) :-
      member(log_entry(_, Service, Msg, _), Logs),
      sub_atom(Msg, _, _, _, 'circuit_state_transition').
  ```
- **Synthesized Remediation**:
  - Resilience4j tuning: Increase minimum number of calls from 10 to 100.
  - Expand wait duration in open state from 5s to 30s with smooth ramp-up in half-open state.

---

### 08. Linux CFS CPU Quota Bandwidth Throttling
- **Module**: `prolog/rules/memory_pressure.pl`
- **Mechanism**: In containerized Kubernetes environments, pods with strict CPU limits (`resources.limits.cpu`) are subject to the Completely Fair Scheduler (CFS) bandwidth quota enforcement. Highly multithreaded runtimes (Go, JVM) exhaust their 100ms quota within the first 10ms of a period, leaving threads frozen for the remaining 90ms despite low average host CPU utilization.
- **Prolog Inference Rule**:
  ```prolog
  rule_memory_pressure(Spans, Metrics, Service) :-
      member(metric_sample(ThrottledMetric, _, ThrottledPeriods, _), Metrics),
      sub_atom(ThrottledMetric, _, _, _, 'cfs_throttled'),
      ThrottledPeriods > 500.
  ```
- **Synthesized Remediation**:
  - Kubernetes patch removing hard CPU limits in favor of CPU requests with node-level overcommit protection.
  - Adjust container runtime thread count to match allocated CFS quota.

---

### 09. Cache Stampede (Thundering Herd)
- **Module**: `prolog/rules/cache_stampede.pl`
- **Mechanism**: A high-traffic cached resource expires simultaneously across all distributed cache nodes. Thousands of concurrent client requests observe a cache miss at the exact same instant and simultaneously query the underlying primary database to regenerate the cached value, causing database brownout.
- **Prolog Inference Rule**:
  ```prolog
  rule_cache_stampede(Spans, Metrics, Logs, Service) :-
      member(log_entry(_, Service, Msg, _), Logs),
      sub_atom(Msg, _, _, _, 'cache_miss'),
      span_high_concurrency(Spans, Service, DBTarget).
  ```
- **Synthesized Remediation**:
  - Probabilistic early cache re-computation (XFetch algorithm).
  - Distributed singleflight mutex lock preventing duplicate origin database queries.

---

### 10. Asymmetric Network Partition / Raft Split Brain
- **Module**: `prolog/rules/network_partition.pl`
- **Mechanism**: A network router or firewall misconfiguration creates a directional or partial network partition where node A can send packets to node B, but node B cannot reply, or node C is disconnected from the quorum leader while remaining accessible to clients. Raft consensus loops in continuous election cycles.
- **Prolog Inference Rule**:
  ```prolog
  rule_network_partition(Spans, Metrics, Logs, Service) :-
      member(metric_sample(HeartbeatMetric, _, Drops, _), Metrics),
      sub_atom(HeartbeatMetric, _, _, _, 'heartbeat_timeout'),
      Drops > 5.
  ```
- **Synthesized Remediation**:
  - Dynamic route reconfiguration and leader election lease timeouts.
  - Toxiproxy and Chaos Mesh network partition assertion test harness.

---

### 11. Distributed File System & Disk I/O Stalls
- **Module**: `prolog/rules/disk_io_stall.pl`
- **Mechanism**: Underlying storage devices (cloud block stores, SAN, local NVMe) experience write queue saturation, metadata lock contention, or slow drive recovery. Write operations block in `D` state (uninterruptible disk sleep), cascading into blocked application workers.
- **Prolog Inference Rule**:
  ```prolog
  rule_disk_io_stall(Spans, Metrics, Logs, Service) :-
      member(metric_sample(IOMetric, _, WaitTime, _), Metrics),
      sub_atom(IOMetric, _, _, _, 'disk_io_time'),
      WaitTime > 2.0.
  ```
- **Synthesized Remediation**:
  - Storage class migration to provisioned IOPS SSD volumes.
  - Asynchronous background write flushing with bounded ring buffers.

---

### 12. Distributed 2PC / Sagas Coordination Timeout
- **Module**: `prolog/rules/distributed_txn.pl`
- **Mechanism**: In a distributed saga or two-phase commit transaction, one participant encounters an unexpected network stall or database lock during the prepare/commit phase. The transaction coordinator blocks while holding distributed locks, stalling all subsequent transactions on those entity keys.
- **Prolog Inference Rule**:
  ```prolog
  rule_distributed_txn(Spans, Metrics, Logs, Service) :-
      member(log_entry(_, Service, Msg, _), Logs),
      sub_atom(Msg, _, _, _, 'saga_timeout').
  ```
- **Synthesized Remediation**:
  - Implement compensating transactions with idempotent replay semantics.
  - Configure aggressive participant timeouts with dead letter queue offloading.
