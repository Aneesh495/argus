/*
 * Argus C11 Foreign Language Interface (FFI) Header
 * High-performance circular ring buffer and fast span parser for SWI-Prolog.
 *
 * All rights reserved. Apache-2.0 License.
 */

#ifndef ARGUS_FFI_H
#define ARGUS_FFI_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ARGUS_FFI_VERSION_MAJOR 1
#define ARGUS_FFI_VERSION_MINOR 0
#define ARGUS_FFI_VERSION_PATCH 0

#define ARGUS_DEFAULT_RING_CAPACITY (1024 * 1024) /* 1 MB */
#define ARGUS_MAX_ID_LEN 64
#define ARGUS_MAX_NAME_LEN 128
#define ARGUS_MAX_SERVICE_LEN 128
#define ARGUS_MAX_ATTRS 32

/* Fixed-size C span representation for high-throughput zero-copy ingestion */
typedef struct {
    char trace_id[ARGUS_MAX_ID_LEN];
    char span_id[ARGUS_MAX_ID_LEN];
    char parent_id[ARGUS_MAX_ID_LEN];
    char service_name[ARGUS_MAX_SERVICE_LEN];
    char span_name[ARGUS_MAX_NAME_LEN];
    int64_t start_time_us;
    int64_t end_time_us;
    int32_t status_code; /* 0: unset, 1: ok, 2: error */
    int32_t kind;        /* 0: internal, 1: server, 2: client, 3: producer, 4: consumer */
} argus_c_span_t;

/* Circular ring buffer state */
typedef struct {
    uint8_t *buffer;
    size_t capacity;
    size_t head;
    size_t tail;
    size_t size;
    bool is_closed;
} argus_ring_buffer_t;

/* Ring buffer lifecycle API */
argus_ring_buffer_t *argus_ring_create(size_t capacity);
void argus_ring_destroy(argus_ring_buffer_t *rb);
size_t argus_ring_write(argus_ring_buffer_t *rb, const uint8_t *data, size_t len);
size_t argus_ring_read(argus_ring_buffer_t *rb, uint8_t *dest, size_t max_len);
size_t argus_ring_available(const argus_ring_buffer_t *rb);
size_t argus_ring_space(const argus_ring_buffer_t *rb);
void argus_ring_clear(argus_ring_buffer_t *rb);

/* Fast span tokenization from raw bytes */
int argus_parse_span_from_json(const char *json_str, size_t len, argus_c_span_t *out_span);

#ifdef __cplusplus
}
#endif

#endif /* ARGUS_FFI_H */
