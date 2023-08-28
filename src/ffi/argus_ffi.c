/*
 * Argus C11 Foreign Language Interface (FFI) Implementation
 * High-performance circular ring buffer and fast span parser for SWI-Prolog.
 *
 * All rights reserved. Apache-2.0 License.
 */

#include "argus/argus_ffi.h"
#include <SWI-Prolog.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Allocate circular ring buffer */
argus_ring_buffer_t *argus_ring_create(size_t capacity) {
    if (capacity == 0) {
        capacity = ARGUS_DEFAULT_RING_CAPACITY;
    }
    argus_ring_buffer_t *rb = (argus_ring_buffer_t *)malloc(sizeof(argus_ring_buffer_t));
    if (!rb) {
        return NULL;
    }
    rb->buffer = (uint8_t *)malloc(capacity);
    if (!rb->buffer) {
        free(rb);
        return NULL;
    }
    rb->capacity = capacity;
    rb->head = 0;
    rb->tail = 0;
    rb->size = 0;
    rb->is_closed = false;
    return rb;
}

/* Deallocate ring buffer */
void argus_ring_destroy(argus_ring_buffer_t *rb) {
    if (rb) {
        if (rb->buffer) {
            free(rb->buffer);
        }
        free(rb);
    }
}

/* Write bytes into ring buffer */
size_t argus_ring_write(argus_ring_buffer_t *rb, const uint8_t *data, size_t len) {
    if (!rb || !data || len == 0 || rb->is_closed) {
        return 0;
    }
    size_t space = rb->capacity - rb->size;
    size_t to_write = (len < space) ? len : space;
    if (to_write == 0) {
        return 0;
    }

    size_t part1 = rb->capacity - rb->head;
    if (part1 >= to_write) {
        memcpy(rb->buffer + rb->head, data, to_write);
        rb->head = (rb->head + to_write) % rb->capacity;
    } else {
        memcpy(rb->buffer + rb->head, data, part1);
        memcpy(rb->buffer, data + part1, to_write - part1);
        rb->head = to_write - part1;
    }
    rb->size += to_write;
    return to_write;
}

/* Read bytes from ring buffer */
size_t argus_ring_read(argus_ring_buffer_t *rb, uint8_t *dest, size_t max_len) {
    if (!rb || !dest || max_len == 0 || rb->size == 0) {
        return 0;
    }
    size_t to_read = (max_len < rb->size) ? max_len : rb->size;
    size_t part1 = rb->capacity - rb->tail;
    if (part1 >= to_read) {
        memcpy(dest, rb->buffer + rb->tail, to_read);
        rb->tail = (rb->tail + to_read) % rb->capacity;
    } else {
        memcpy(dest, rb->buffer + rb->tail, part1);
        memcpy(dest + part1, rb->buffer, to_read - part1);
        rb->tail = to_read - part1;
    }
    rb->size -= to_read;
    return to_read;
}

size_t argus_ring_available(const argus_ring_buffer_t *rb) {
    return rb ? rb->size : 0;
}

size_t argus_ring_space(const argus_ring_buffer_t *rb) {
    return rb ? (rb->capacity - rb->size) : 0;
}

void argus_ring_clear(argus_ring_buffer_t *rb) {
    if (rb) {
        rb->head = 0;
        rb->tail = 0;
        rb->size = 0;
    }
}

/* Helper: extract string value for a key in flat JSON */
static int extract_json_field(const char *json, size_t len, const char *key, char *out, size_t max_out) {
    char pattern[128];
    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    const char *pos = strstr(json, pattern);
    if (!pos || (size_t)(pos - json) >= len) {
        return 0;
    }
    pos += strlen(pattern);
    while (pos < json + len && (*pos == ' ' || *pos == ':' || *pos == '\t')) {
        pos++;
    }
    if (pos >= json + len) {
        return 0;
    }
    if (*pos == '\"') {
        pos++;
        const char *end = pos;
        while (end < json + len && *end != '\"' && *end != '\\') {
            end++;
        }
        size_t val_len = (size_t)(end - pos);
        if (val_len >= max_out) {
            val_len = max_out - 1;
        }
        memcpy(out, pos, val_len);
        out[val_len] = '\0';
        return 1;
    } else {
        /* Numeric or identifier value */
        const char *end = pos;
        while (end < json + len && *end != ',' && *end != '}' && *end != '\n' && *end != ' ') {
            end++;
        }
        size_t val_len = (size_t)(end - pos);
        if (val_len >= max_out) {
            val_len = max_out - 1;
        }
        memcpy(out, pos, val_len);
        out[val_len] = '\0';
        return 1;
    }
}

/* Fast span tokenization from raw JSON buffer */
int argus_parse_span_from_json(const char *json_str, size_t len, argus_c_span_t *out_span) {
    if (!json_str || !out_span || len == 0) {
        return -1;
    }
    memset(out_span, 0, sizeof(argus_c_span_t));

    char buf[128];
    if (extract_json_field(json_str, len, "trace_id", out_span->trace_id, sizeof(out_span->trace_id)) == 0) {
        extract_json_field(json_str, len, "traceId", out_span->trace_id, sizeof(out_span->trace_id));
    }
    if (extract_json_field(json_str, len, "span_id", out_span->span_id, sizeof(out_span->span_id)) == 0) {
        extract_json_field(json_str, len, "spanId", out_span->span_id, sizeof(out_span->span_id));
    }
    if (extract_json_field(json_str, len, "parent_id", out_span->parent_id, sizeof(out_span->parent_id)) == 0) {
        extract_json_field(json_str, len, "parentId", out_span->parent_id, sizeof(out_span->parent_id));
    }
    if (extract_json_field(json_str, len, "service_name", out_span->service_name, sizeof(out_span->service_name)) == 0) {
        extract_json_field(json_str, len, "serviceName", out_span->service_name, sizeof(out_span->service_name));
    }
    if (extract_json_field(json_str, len, "name", out_span->span_name, sizeof(out_span->span_name)) == 0) {
        extract_json_field(json_str, len, "operationName", out_span->span_name, sizeof(out_span->span_name));
    }

    if (extract_json_field(json_str, len, "start_time_us", buf, sizeof(buf))) {
        out_span->start_time_us = atoll(buf);
    } else if (extract_json_field(json_str, len, "startTimeUnixNano", buf, sizeof(buf))) {
        out_span->start_time_us = atoll(buf) / 1000;
    }

    if (extract_json_field(json_str, len, "end_time_us", buf, sizeof(buf))) {
        out_span->end_time_us = atoll(buf);
    } else if (extract_json_field(json_str, len, "endTimeUnixNano", buf, sizeof(buf))) {
        out_span->end_time_us = atoll(buf) / 1000;
    }

    if (extract_json_field(json_str, len, "status_code", buf, sizeof(buf))) {
        out_span->status_code = atoi(buf);
    }

    return 0;
}

/* SWI-Prolog C-FLI Predicates */

/* argus_c_ring_create(+Capacity, -Handle) */
static foreign_t pl_argus_c_ring_create(term_t t_cap, term_t t_handle) {
    long cap = 0;
    if (!PL_get_long(t_cap, &cap) || cap <= 0) {
        cap = ARGUS_DEFAULT_RING_CAPACITY;
    }
    argus_ring_buffer_t *rb = argus_ring_create((size_t)cap);
    if (!rb) {
        return PL_warning("Failed to allocate ring buffer");
    }
    return PL_unify_pointer(t_handle, rb);
}

/* argus_c_ring_destroy(+Handle) */
static foreign_t pl_argus_c_ring_destroy(term_t t_handle) {
    void *ptr = NULL;
    if (!PL_get_pointer(t_handle, &ptr) || !ptr) {
        return FALSE;
    }
    argus_ring_destroy((argus_ring_buffer_t *)ptr);
    return TRUE;
}

/* argus_c_ring_write(+Handle, +DataAtom, -Written) */
static foreign_t pl_argus_c_ring_write(term_t t_handle, term_t t_data, term_t t_written) {
    void *ptr = NULL;
    if (!PL_get_pointer(t_handle, &ptr) || !ptr) {
        return FALSE;
    }
    char *str = NULL;
    size_t len = 0;
    if (!PL_get_nchars(t_data, &len, &str, CVT_ALL | REP_UTF8)) {
        return FALSE;
    }
    size_t written = argus_ring_write((argus_ring_buffer_t *)ptr, (const uint8_t *)str, len);
    return PL_unify_integer(t_written, (long)written);
}

/* argus_c_ring_read(+Handle, +MaxBytes, -DataAtom) */
static foreign_t pl_argus_c_ring_read(term_t t_handle, term_t t_max, term_t t_data) {
    void *ptr = NULL;
    if (!PL_get_pointer(t_handle, &ptr) || !ptr) {
        return FALSE;
    }
    long max_bytes = 0;
    if (!PL_get_long(t_max, &max_bytes) || max_bytes <= 0) {
        return FALSE;
    }
    uint8_t *dest = (uint8_t *)malloc((size_t)max_bytes + 1);
    if (!dest) {
        return FALSE;
    }
    size_t read_bytes = argus_ring_read((argus_ring_buffer_t *)ptr, dest, (size_t)max_bytes);
    dest[read_bytes] = '\0';
    int res = PL_unify_chars(t_data, PL_ATOM | REP_UTF8, read_bytes, (const char *)dest);
    free(dest);
    return res;
}

/* argus_c_ring_available(+Handle, -Available) */
static foreign_t pl_argus_c_ring_available(term_t t_handle, term_t t_avail) {
    void *ptr = NULL;
    if (!PL_get_pointer(t_handle, &ptr) || !ptr) {
        return FALSE;
    }
    size_t avail = argus_ring_available((argus_ring_buffer_t *)ptr);
    return PL_unify_integer(t_avail, (long)avail);
}

/* argus_c_version(-VersionAtom) */
static foreign_t pl_argus_c_version(term_t t_ver) {
    char ver_str[32];
    snprintf(ver_str, sizeof(ver_str), "%d.%d.%d",
             ARGUS_FFI_VERSION_MAJOR,
             ARGUS_FFI_VERSION_MINOR,
             ARGUS_FFI_VERSION_PATCH);
    return PL_unify_atom_chars(t_ver, ver_str);
}

/* argus_c_parse_span(+JsonAtom, -SpanTerm) */
static foreign_t pl_argus_c_parse_span(term_t t_json, term_t t_span) {
    char *json_str = NULL;
    size_t len = 0;
    if (!PL_get_nchars(t_json, &len, &json_str, CVT_ALL | REP_UTF8)) {
        return FALSE;
    }

    argus_c_span_t s;
    if (argus_parse_span_from_json(json_str, len, &s) != 0) {
        return FALSE;
    }

    functor_t f_span = PL_new_functor(PL_new_atom("span"), 8);
    term_t args = PL_new_term_refs(8);
    PL_put_atom_chars(args + 0, s.trace_id);
    PL_put_atom_chars(args + 1, s.span_id);
    PL_put_atom_chars(args + 2, s.parent_id);
    PL_put_atom_chars(args + 3, s.service_name);
    PL_put_atom_chars(args + 4, s.span_name);
    if (!PL_put_int64(args + 5, s.start_time_us) ||
        !PL_put_int64(args + 6, s.end_time_us) ||
        !PL_put_integer(args + 7, s.status_code)) {
        return FALSE;
    }

    term_t tmp = PL_new_term_ref();
    if (!PL_cons_functor_v(tmp, f_span, args)) {
        return FALSE;
    }
    return PL_unify(t_span, tmp);
}

/* Module initialization entry points called by SWI-Prolog load_foreign_library */
install_t install_argus_ffi(void) {
    PL_register_foreign("argus_c_ring_create", 2, (pl_function_t)pl_argus_c_ring_create, 0);
    PL_register_foreign("argus_c_ring_destroy", 1, (pl_function_t)pl_argus_c_ring_destroy, 0);
    PL_register_foreign("argus_c_ring_write", 3, (pl_function_t)pl_argus_c_ring_write, 0);
    PL_register_foreign("argus_c_ring_read", 3, (pl_function_t)pl_argus_c_ring_read, 0);
    PL_register_foreign("argus_c_ring_available", 2, (pl_function_t)pl_argus_c_ring_available, 0);
    PL_register_foreign("argus_c_version", 1, (pl_function_t)pl_argus_c_version, 0);
    PL_register_foreign("argus_c_parse_span", 2, (pl_function_t)pl_argus_c_parse_span, 0);
}

install_t install_libargus_ffi(void) {
    install_argus_ffi();
}

install_t install(void) {
    install_argus_ffi();
}
