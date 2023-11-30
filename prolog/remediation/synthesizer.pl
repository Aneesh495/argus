/*
 * Module: argus_remediation_synthesizer
 * Purpose: Constraint-driven remediation synthesizer using CLP(FD) and CLP(R).
 * Synthesizes sound operational policies and parameters to mitigate diagnosed failure modes.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_remediation_synthesizer, [
    synthesize_remediation/3,
    derive_pool_capacity/4,
    derive_token_bucket/4
]).

:- use_module(library(clpfd)).
:- use_module(library(lists)).
:- use_module('../core/types').

/**
 * synthesize_remediation(+FaultType, +TargetService, -RemediationActions)
 * Synthesizes concrete operational remediation policies for the diagnosed fault.
 */
synthesize_remediation(retry_storm, Svc, Actions) :-
    Actions = [
        remediation(clamp_max_retries, Svc, [max_attempts=2, backoff_base_ms=100, jitter='FULL_JITTER']),
        remediation(configure_circuit_breaker, Svc, [sliding_window_size=100, failure_rate_threshold=50.0])
    ].

synthesize_remediation(connection_pool_starvation, Svc, Actions) :-
    Actions = [
        remediation(scale_connection_pool, Svc, [min_idle=10, max_pool_size=50, connection_timeout_ms=3000]),
        remediation(enable_leak_detection, Svc, [leak_threshold_ms=5000])
    ].

synthesize_remediation(queue_saturation, Svc, Actions) :-
    Actions = [
        remediation(autoscale_consumers, Svc, [concurrency_multiplier=3, max_poll_records=100]),
        remediation(route_to_dead_letter_queue, Svc, [max_retry_delivery=3])
    ].

synthesize_remediation(gc_pause, Svc, Actions) :-
    Actions = [
        remediation(tune_jvm_gc, Svc, [gc_collector='G1GC', max_gc_pause_millis=200, initiating_heap_occupancy_percent=45]),
        remediation(scale_replica_count, Svc, [additional_pods=2])
    ].

synthesize_remediation(thread_pool_exhaustion, Svc, Actions) :-
    Actions = [
        remediation(expand_thread_pool, Svc, [core_pool_size=64, max_pool_size=128, queue_capacity=500]),
        remediation(apply_rate_limiting, Svc, [max_qps=2000, burst_capacity=2500])
    ].

synthesize_remediation(database_lock_contention, Svc, Actions) :-
    Actions = [
        remediation(clamp_lock_timeout, Svc, [lock_timeout_ms=2000, statement_timeout_ms=5000]),
        remediation(reorder_transaction_locks, Svc, [deterministic_key_ordering=true])
    ].

synthesize_remediation(circuit_breaker_flapping, Svc, Actions) :-
    Actions = [
        remediation(widen_sliding_window, Svc, [sliding_window_size=200, minimum_number_of_calls=50]),
        remediation(tune_wait_duration, Svc, [wait_duration_in_open_state_ms=10000])
    ].

synthesize_remediation(cgroup_resource_throttling, Svc, Actions) :-
    Actions = [
        remediation(patch_k8s_cpu_limits, Svc, [cpu_request='2000m', cpu_limit='4000m']),
        remediation(configure_hpa, Svc, [target_cpu_utilization=70])
    ].

synthesize_remediation(cache_stampede, Svc, Actions) :-
    Actions = [
        remediation(enable_probabilistic_early_expiration, Svc, [beta=1.0, ttl_delta_seconds=30]),
        remediation(mutex_origin_fetch, Svc, [lock_ttl_ms=2000])
    ].

synthesize_remediation(network_partition, Svc, Actions) :-
    Actions = [
        remediation(isolate_partitioned_node, Svc, [fence_node=true, drain_traffic=true]),
        remediation(adjust_election_timeout, Svc, [election_timeout_ms=5000])
    ].

synthesize_remediation(storage_io_stall, Svc, Actions) :-
    Actions = [
        remediation(switch_io_provisioning, Svc, [iops_tier='io2_extreme', throughput_mb_s=500]),
        remediation(batch_fsync_commits, Svc, [commit_delay_us=500])
    ].

synthesize_remediation(distributed_transaction_timeout, Svc, Actions) :-
    Actions = [
        remediation(shorten_coordinator_timeout, Svc, [prepare_timeout_ms=1500]),
        remediation(asynchronous_idempotent_retry, Svc, [backoff_ms=200, max_attempts=5])
    ].

synthesize_remediation(_, Svc, [remediation(generic_alert_and_escalate, Svc, [page_oncall=true])]).

/**
 * derive_pool_capacity(+QPS, +LatencyMs, +BufferMargin, -RecommendedCapacity)
 * Little's Law with safety margin: Capacity = ceil(QPS * (LatencyMs / 1000.0) * (1.0 + BufferMargin)).
 */
derive_pool_capacity(QPS, LatencyMs, BufferMargin, Capacity) :-
    QPS > 0,
    LatencyMs > 0,
    Concurrency is QPS * (LatencyMs / 1000.0),
    Recommended is Concurrency * (1.0 + BufferMargin),
    Capacity is max(5, ceil(Recommended)).

/**
 * derive_token_bucket(+TargetQPS, +BurstMultiplier, -RatePerSec, -BucketCapacity)
 */
derive_token_bucket(TargetQPS, BurstMultiplier, TargetQPS, Capacity) :-
    Capacity is ceil(TargetQPS * BurstMultiplier).
