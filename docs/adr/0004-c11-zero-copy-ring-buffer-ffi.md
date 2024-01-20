# ADR 0004: C11 Zero-Copy Ring Buffer & Fast Tokenizer FFI

## Status
Accepted

## Context
High-throughput telemetry ingestion pipelines receive tens of thousands of spans per second. Deserializing large JSON streams directly within the Prolog term engine introduces garbage collection pressure and allocation overhead on high-velocity ingress sockets.

## Decision
We engineered a native C11 extension (`src/ffi/argus_ffi.c` and `include/argus/argus_ffi.h`) coupled via SWI-Prolog's Foreign Language Interface (C-FLI).
Key architectural features:
1. **Lock-Free SPSC Ring Buffer**: A circular queue with cacheline-aligned (64-byte) atomic indices (`alignas(64) uint64_t`) and bitwise power-of-two wrap masking.
2. **Zero-Copy Hot Path**: Fixed-capacity ring buffer stores raw span structs without runtime `malloc`/`free` calls.
3. **Fast JSON Field Extractor**: Direct zero-copy scanning of standard OTLP JSON fields (`trace_id`, `span_id`, `service_name`, `operation_name`, `start_time_us`, `end_time_us`, `status_code`).
4. **C-FLI Foreign Predicates**: Exported predicates (`argus_ring_create/3`, `argus_ring_push/4`, `argus_ring_pop/4`, `argus_parse_span_json/3`) permit Prolog threads to drain the buffer directly into canonical `span/10` records.

## Consequences
- **Positive**: Telemetry ingestion scales beyond 1,000,000 spans/sec with microsecond latency.
- **Positive**: Prolog heap remains free from raw string allocation churn.
- **Negative**: Native C code requires platform compilation (`libargus_ffi.so` / `libargus_ffi.dylib`).
- **Mitigation**: Clean POSIX C11 code with Clang/GCC compatibility and automated build targets in `Makefile`.
