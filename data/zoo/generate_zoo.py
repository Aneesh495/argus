#!/usr/bin/env python3
"""Generate the Argus Incident Zoo: 10 curated real-world distributed failure datasets."""

import os
import json

ZOO_DIR = os.path.dirname(os.path.abspath(__file__))

INCIDENTS = [
    {
        "id": "01_retry_storm_cascade",
        "title": "Cascading Retry Storm in Payment Gateway",
        "fault": "retry_storm",
        "target_service": "api-gateway",
        "spans": [
            {
                "traceId": "trace_retry_01",
                "spanId": "gw_root",
                "parentSpanId": "",
                "name": "POST /checkout",
                "startTimeUnixNano": "1700000000000000000",
                "endTimeUnixNano": "1700000002500000000",
                "status": {"code": "STATUS_CODE_ERROR"},
                "attributes": [{"key": "http.status_code", "value": {"intValue": 504}}]
            },
            {
                "traceId": "trace_retry_01",
                "spanId": "pay_call_1",
                "parentSpanId": "gw_root",
                "name": "chargeCard",
                "startTimeUnixNano": "1700000000100000000",
                "endTimeUnixNano": "1700000000600000000",
                "status": {"code": "STATUS_CODE_ERROR"},
                "attributes": [{"key": "retry.attempt", "value": {"intValue": 1}}]
            },
            {
                "traceId": "trace_retry_01",
                "spanId": "pay_call_2",
                "parentSpanId": "gw_root",
                "name": "chargeCard",
                "startTimeUnixNano": "1700000000700000000",
                "endTimeUnixNano": "1700000001300000000",
                "status": {"code": "STATUS_CODE_ERROR"},
                "attributes": [{"key": "retry.attempt", "value": {"intValue": 2}}]
            },
            {
                "traceId": "trace_retry_01",
                "spanId": "pay_call_3",
                "parentSpanId": "gw_root",
                "name": "chargeCard",
                "startTimeUnixNano": "1700000001400000000",
                "endTimeUnixNano": "1700000002300000000",
                "status": {"code": "STATUS_CODE_ERROR"},
                "attributes": [{"key": "retry.attempt", "value": {"intValue": 3}}]
            }
        ],
        "metrics": "http_requests_total{service=\"api-gateway\",status=\"504\"} 1420.0 1700000002000\n",
        "logs": [
            {"timestamp": 1700000002350, "level": "ERROR", "service": "api-gateway", "message": "Downstream payment service retry budget exhausted", "trace_id": "trace_retry_01", "span_id": "gw_root"}
        ]
    },
    {
        "id": "02_connection_pool_starvation",
        "title": "HikariCP Connection Pool Exhaustion on Inventory Database",
        "fault": "connection_pool_starvation",
        "target_service": "inventory-db",
        "spans": [
            {
                "traceId": "trace_pool_02",
                "spanId": "inv_root",
                "parentSpanId": "",
                "name": "GET /inventory/SKU-9921",
                "startTimeUnixNano": "1700000010000000000",
                "endTimeUnixNano": "1700000015500000000",
                "status": {"code": "STATUS_CODE_ERROR"},
                "attributes": []
            },
            {
                "traceId": "trace_pool_02",
                "spanId": "db_query_01",
                "parentSpanId": "inv_root",
                "name": "SELECT stock FROM inventory WHERE sku = ?",
                "startTimeUnixNano": "1700000010100000000",
                "endTimeUnixNano": "1700000015400000000",
                "status": {"code": "STATUS_CODE_ERROR"},
                "attributes": [
                    {"key": "pool.wait_time_ms", "value": {"intValue": 5200}},
                    {"key": "error.message", "value": {"stringValue": "ConnectionPoolTimeoutException: Timeout waiting for connection from pool"}}
                ]
            }
        ],
        "metrics": "pool_active_connections{service=\"inventory-db\"} 1.0 1700000015000\n",
        "logs": [
            {"timestamp": 1700000015450, "level": "ERROR", "service": "inventory-db", "message": "ConnectionPoolTimeoutException: HikariPool - Connection is not available", "trace_id": "trace_pool_02", "span_id": "db_query_01"}
        ]
    },
    {
        "id": "03_kafka_consumer_lag",
        "title": "Kafka Partition Rebalance Stall and Consumer Lag Saturation",
        "fault": "queue_saturation",
        "target_service": "order-consumer",
        "spans": [
            {
                "traceId": "trace_queue_03",
                "spanId": "cons_root",
                "parentSpanId": "",
                "name": "processOrderEvent",
                "startTimeUnixNano": "1700000020000000000",
                "endTimeUnixNano": "1700000030000000000",
                "status": {"code": "STATUS_CODE_OK"},
                "attributes": [
                    {"key": "messaging.system", "value": {"stringValue": "kafka"}},
                    {"key": "messaging.queue_lag_ms", "value": {"intValue": 12500}}
                ]
            }
        ],
        "metrics": "kafka_consumer_lag_records{consumergroup=\"order-consumer\"} 45000.0 1700000030000\n",
        "logs": [
            {"timestamp": 1700000025000, "level": "WARN", "service": "order-consumer", "message": "Max poll interval exceeded; consumer group rebalance in progress", "trace_id": "trace_queue_03", "span_id": "cons_root"}
        ]
    },
    {
        "id": "04_gc_pause_heartbeat_timeout",
        "title": "Stop-The-World JVM Garbage Collection Pause Causing Lease Eviction",
        "fault": "gc_pause",
        "target_service": "auth-service",
        "spans": [
            {
                "traceId": "trace_gc_04",
                "spanId": "auth_root",
                "parentSpanId": "",
                "name": "verifySessionToken",
                "startTimeUnixNano": "1700000040000000000",
                "endTimeUnixNano": "1700000044500000000",
                "status": {"code": "STATUS_CODE_ERROR"},
                "attributes": [
                    {"key": "gc.pause_duration_ms", "value": {"intValue": 4100}}
                ]
            }
        ],
        "metrics": "jvm_gc_pause_seconds{service=\"auth-service\"} 4.1 1700000044000\n",
        "logs": [
            {"timestamp": 1700000043900, "level": "ERROR", "service": "auth-service", "message": "Lease lost due to stop-the-world pause; heartbeat missed during GC", "trace_id": "trace_gc_04", "span_id": "auth_root"}
        ]
    },
    {
        "id": "05_thread_pool_exhaustion",
        "title": "Worker Thread Pool Starvation and Task Queue Overflow",
        "fault": "thread_pool_exhaustion",
        "target_service": "search-service",
        "spans": [
            {
                "traceId": "trace_thread_05",
                "spanId": "search_root",
                "parentSpanId": "",
                "name": "executeSearchQuery",
                "startTimeUnixNano": "1700000050000000000",
                "endTimeUnixNano": "1700000055000000000",
                "status": {"code": "STATUS_CODE_ERROR"},
                "attributes": [
                    {"key": "thread.queue_wait_ms", "value": {"intValue": 4800}}
                ]
            }
        ],
        "metrics": "threadpool_active_threads{service=\"search-service\"} 1.0 1700000054000\n",
        "logs": [
            {"timestamp": 1700000054800, "level": "ERROR", "service": "search-service", "message": "RejectedExecutionException: Thread pool exhausted; all threads are busy", "trace_id": "trace_thread_05", "span_id": "search_root"}
        ]
    },
    {
        "id": "06_postgres_lock_deadlock",
        "title": "PostgreSQL Row Lock Contention and Deadlock Cycle",
        "fault": "database_lock_contention",
        "target_service": "postgres-db",
        "spans": [
            {
                "traceId": "trace_lock_06",
                "spanId": "txn_root",
                "parentSpanId": "",
                "name": "UPDATE accounts SET balance = balance - 100",
                "startTimeUnixNano": "1700000060000000000",
                "endTimeUnixNano": "1700000066000000000",
                "status": {"code": "STATUS_CODE_ERROR"},
                "attributes": [
                    {"key": "db.lock_wait_ms", "value": {"intValue": 5900}},
                    {"key": "error.message", "value": {"stringValue": "deadlock detected: Process 9182 waits for ShareLock on transaction 8271"}}
                ]
            }
        ],
        "metrics": "pg_stat_activity_waiting_locks{service=\"postgres-db\"} 48.0 1700000065000\n",
        "logs": [
            {"timestamp": 1700000065800, "level": "ERROR", "service": "postgres-db", "message": "deadlock detected: Process 9182 and Process 9184 blocked each other", "trace_id": "trace_lock_06", "span_id": "txn_root"}
        ]
    },
    {
        "id": "07_circuit_breaker_flutter",
        "title": "Circuit Breaker Rapid Flapping Under Transient Load",
        "fault": "circuit_breaker_flapping",
        "target_service": "recommendation-service",
        "spans": [
            {
                "traceId": "trace_cb_07",
                "spanId": "rec_root",
                "parentSpanId": "",
                "name": "getRecommendations",
                "startTimeUnixNano": "1700000070000000000",
                "endTimeUnixNano": "1700000070050000000",
                "status": {"code": "STATUS_CODE_ERROR"},
                "attributes": [
                    {"key": "circuit_breaker.state", "value": {"stringValue": "OPEN"}},
                    {"key": "error.type", "value": {"stringValue": "CircuitBreakerOpenException"}}
                ]
            }
        ],
        "metrics": "circuit_breaker_state_transitions{service=\"recommendation-service\"} 32.0 1700000070000\n",
        "logs": [
            {"timestamp": 1700000070010, "level": "WARN", "service": "recommendation-service", "message": "CircuitBreaker tripped to OPEN due to slow call threshold", "trace_id": "trace_cb_07", "span_id": "rec_root"}
        ]
    },
    {
        "id": "08_cfs_cpu_quota_throttling",
        "title": "Linux CFS CPU Quota Throttling Causing Microservice Brownout",
        "fault": "cgroup_resource_throttling",
        "target_service": "image-processing-service",
        "spans": [
            {
                "traceId": "trace_cfs_08",
                "spanId": "img_root",
                "parentSpanId": "",
                "name": "resizeAvatar",
                "startTimeUnixNano": "1700000080000000000",
                "endTimeUnixNano": "1700000086000000000",
                "status": {"code": "STATUS_CODE_ERROR"},
                "attributes": [
                    {"key": "container.cpu.throttled_percent", "value": {"doubleValue": 68.5}}
                ]
            }
        ],
        "metrics": "container_cpu_cfs_throttled_periods_total{service=\"image-processing-service\"} 120.0 1700000085000\n",
        "logs": [
            {"timestamp": 1700000085900, "level": "WARN", "service": "image-processing-service", "message": "CPU CFS throttling exceeded 60% of runtime periods", "trace_id": "trace_cfs_08", "span_id": "img_root"}
        ]
    },
    {
        "id": "09_cache_stampede_thundering_herd",
        "title": "Hot-Key Redis Expiration Causing Origin Database Thundering Herd",
        "fault": "cache_stampede",
        "target_service": "catalog-db",
        "spans": [
            {
                "traceId": "trace_stampede_09",
                "spanId": "cache_root",
                "parentSpanId": "",
                "name": "getProductListing",
                "startTimeUnixNano": "1700000090000000000",
                "endTimeUnixNano": "1700000095000000000",
                "status": {"code": "STATUS_CODE_OK"},
                "attributes": [
                    {"key": "cache.hit", "value": {"boolValue": False}},
                    {"key": "cache.key", "value": {"stringValue": "hot_category_electronics"}}
                ]
            }
        ] + [
            {
                "traceId": "trace_stampede_09",
                "spanId": f"db_query_{i}",
                "parentSpanId": "cache_root",
                "name": "SELECT * FROM products WHERE category = ?",
                "startTimeUnixNano": str(1700000090100000000 + i * 1000000),
                "endTimeUnixNano": str(1700000094000000000 + i * 1000000),
                "status": {"code": "STATUS_CODE_OK"},
                "attributes": [
                    {"key": "db.query_parameter", "value": {"stringValue": "hot_category_electronics"}}
                ]
            } for i in range(1, 8)
        ],
        "metrics": "cache_misses_per_second{service=\"catalog-db\"} 4800.0 1700000094000\n",
        "logs": [
            {"timestamp": 1700000092000, "level": "WARN", "service": "catalog-db", "message": "Thundering herd on cache key hot_category_electronics", "trace_id": "trace_stampede_09", "span_id": "cache_root"}
        ]
    },
    {
        "id": "10_asymmetric_partition_raft",
        "title": "Asymmetric Transit Loss and Raft Majority Quorum Election Loop",
        "fault": "network_partition",
        "target_service": "consensus-etcd",
        "spans": [
            {
                "traceId": "trace_raft_10",
                "spanId": "etcd_root",
                "parentSpanId": "",
                "name": "appendEntries",
                "startTimeUnixNano": "1700000100000000000",
                "endTimeUnixNano": "1700000105000000000",
                "status": {"code": "STATUS_CODE_ERROR"},
                "attributes": [
                    {"key": "error.type", "value": {"stringValue": "NoRouteToHostException"}}
                ]
            }
        ],
        "metrics": "etcd_server_has_leader{service=\"consensus-etcd\"} 0.0 1700000104000\n",
        "logs": [
            {"timestamp": 1700000104500, "level": "FATAL", "service": "consensus-etcd", "message": "Lost majority quorum; Raft election timeout triggered repeated candidate loops", "trace_id": "trace_raft_10", "span_id": "etcd_root"}
        ]
    }
]

def generate():
    for inc in INCIDENTS:
        inc_dir = os.path.join(ZOO_DIR, inc["id"])
        os.makedirs(inc_dir, exist_ok=True)
        
        # Build OTLP JSON trace file
        otlp_doc = {
            "resourceSpans": [{
                "resource": {
                    "attributes": [{"key": "service.name", "value": {"stringValue": inc["target_service"]}}]
                },
                "scopeSpans": [{"spans": inc["spans"]}]
            }]
        }
        trace_file = os.path.join(inc_dir, "trace.json")
        with open(trace_file, "w") as f:
            json.dump(otlp_doc, f, indent=2)
            
        # Write OpenMetrics file
        metrics_file = os.path.join(inc_dir, "metrics.prom")
        with open(metrics_file, "w") as f:
            f.write(inc["metrics"])
            
        # Write Structured Logs
        logs_file = os.path.join(inc_dir, "logs.jsonl")
        with open(logs_file, "w") as f:
            for l in inc["logs"]:
                f.write(json.dumps(l) + "\n")
                
        # Write ground truth manifest
        manifest_file = os.path.join(inc_dir, "manifest.json")
        with open(manifest_file, "w") as f:
            json.dump({
                "id": inc["id"],
                "title": inc["title"],
                "expected_fault": inc["fault"],
                "expected_service": inc["target_service"]
            }, f, indent=2)
            
    print(f"Successfully generated {len(INCIDENTS)} Incident Zoo scenarios in {ZOO_DIR}")

if __name__ == "__main__":
    generate()
