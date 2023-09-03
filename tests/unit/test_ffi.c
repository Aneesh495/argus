/*
 * Unit tests for Argus C11 FFI ring buffer and span parser.
 * Tests wrap-around, bounds checking, empty/full states, and JSON tokenization.
 */

#include "argus/argus_ffi.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

static void test_ring_buffer_basic(void) {
    argus_ring_buffer_t *rb = argus_ring_create(16);
    assert(rb != NULL);
    assert(argus_ring_available(rb) == 0);
    assert(argus_ring_space(rb) == 16);

    const char *msg1 = "abcdefgh"; /* 8 bytes */
    size_t written = argus_ring_write(rb, (const uint8_t *)msg1, 8);
    assert(written == 8);
    assert(argus_ring_available(rb) == 8);
    assert(argus_ring_space(rb) == 8);

    uint8_t out[16];
    size_t read_bytes = argus_ring_read(rb, out, 4);
    assert(read_bytes == 4);
    assert(memcmp(out, "abcd", 4) == 0);
    assert(argus_ring_available(rb) == 4);

    /* Write 10 bytes to trigger wrap-around (space is 12, capacity 16) */
    const char *msg2 = "1234567890";
    written = argus_ring_write(rb, (const uint8_t *)msg2, 10);
    assert(written == 10);
    assert(argus_ring_available(rb) == 14);

    /* Read all remaining 14 bytes */
    read_bytes = argus_ring_read(rb, out, sizeof(out));
    assert(read_bytes == 14);
    assert(memcmp(out, "efgh1234567890", 14) == 0);
    assert(argus_ring_available(rb) == 0);

    argus_ring_destroy(rb);
    printf("test_ring_buffer_basic passed.\n");
}

static void test_ring_buffer_overflow_protection(void) {
    argus_ring_buffer_t *rb = argus_ring_create(8);
    assert(rb != NULL);

    const char *data = "1234567890EXTRA";
    size_t written = argus_ring_write(rb, (const uint8_t *)data, strlen(data));
    assert(written == 8); /* Should clamp to capacity */
    assert(argus_ring_space(rb) == 0);

    /* Writing to full buffer returns 0 */
    written = argus_ring_write(rb, (const uint8_t *)"more", 4);
    assert(written == 0);

    argus_ring_destroy(rb);
    printf("test_ring_buffer_overflow_protection passed.\n");
}

static void test_span_parser_json(void) {
    const char *json = "{\"trace_id\":\"trace-999\",\"span_id\":\"span-100\",\"parent_id\":\"span-001\","
                       "\"service_name\":\"checkout-service\",\"name\":\"processPayment\","
                       "\"start_time_us\":1700000000100,\"end_time_us\":1700000000650,\"status_code\":2}";

    argus_c_span_t s;
    int rc = argus_parse_span_from_json(json, strlen(json), &s);
    assert(rc == 0);
    assert(strcmp(s.trace_id, "trace-999") == 0);
    assert(strcmp(s.span_id, "span-100") == 0);
    assert(strcmp(s.parent_id, "span-001") == 0);
    assert(strcmp(s.service_name, "checkout-service") == 0);
    assert(strcmp(s.span_name, "processPayment") == 0);
    assert(s.start_time_us == 1700000000100LL);
    assert(s.end_time_us == 1700000000650LL);
    assert(s.status_code == 2);

    printf("test_span_parser_json passed.\n");
}

int main(void) {
    printf("Running Argus C11 FFI unit tests...\n");
    test_ring_buffer_basic();
    test_ring_buffer_overflow_protection();
    test_span_parser_json();
    printf("All C11 FFI unit tests passed successfully!\n");
    return 0;
}
