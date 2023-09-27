/*
 * Unit tests for Argus parser modules:
 * W3C TraceContext, OTLP JSON, Jaeger JSON, OpenMetrics, and Structured Logs.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(test_parsers, [
    run_parser_tests/0
]).

:- use_module(library(plunit)).
:- use_module('../../prolog/parser/w3c_trace_context').
:- use_module('../../prolog/parser/otlp_json').
:- use_module('../../prolog/parser/jaeger_json').
:- use_module('../../prolog/parser/openmetrics').
:- use_module('../../prolog/parser/structured_log').
:- use_module('../../prolog/core/types').

run_parser_tests :-
    run_tests([w3c_trace_context, otlp_json, jaeger_json, openmetrics, structured_log]).

:- begin_tests(w3c_trace_context).

test(traceparent_parsing_and_formatting) :-
    Header = '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
    parse_traceparent(Header, TraceId, ParentId, Flags),
    TraceId = '4bf92f3577b34da6a3ce929d0e0e4736',
    ParentId = '00f067aa0ba902b7',
    Flags =:= 1,
    format_traceparent(TraceId, ParentId, Flags, ReFormatted),
    ReFormatted = Header.

test(tracestate_parsing_and_formatting) :-
    StateHeader = 'rojo=1,congo=4,argus=ratio:0.95',
    parse_tracestate(StateHeader, Entries),
    Entries = [rojo='1', congo='4', argus='ratio:0.95'],
    format_tracestate(Entries, Formatted),
    Formatted = StateHeader.

:- end_tests(w3c_trace_context).

:- begin_tests(otlp_json).

test(otlp_resource_spans_parsing) :-
    Json = '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"order-service"}}]},"scopeSpans":[{"spans":[{"traceId":"t001","spanId":"s001","name":"createOrder","startTimeUnixNano":"1700000000000000000","endTimeUnixNano":"1700000000150000000","status":{"code":"STATUS_CODE_OK"}}]}]}]}',
    otlp_json_parse(Json, Spans),
    Spans = [Span],
    span_service(Span, 'order-service'),
    span_name(Span, 'createOrder'),
    span_duration_us(Span, 150000),
    span_status(Span, 1).

:- end_tests(otlp_json).

:- begin_tests(jaeger_json).

test(jaeger_trace_parsing) :-
    Json = '{"data":[{"traceID":"trace-j1","processes":{"p1":{"serviceName":"payment-gateway"}},"spans":[{"spanID":"span-j1","operationName":"chargeCard","startTime":1600000000,"duration":45000,"processID":"p1","tags":[{"key":"http.status_code","value":200}]}]}]}',
    jaeger_json_parse(Json, Spans),
    Spans = [Span],
    span_trace_id(Span, 'trace-j1'),
    span_id(Span, 'span-j1'),
    span_service(Span, 'payment-gateway'),
    span_name(Span, 'chargeCard'),
    span_duration_us(Span, 45000).

:- end_tests(jaeger_json).

:- begin_tests(openmetrics).

test(openmetrics_line_and_text_parsing) :-
    Text = '# HELP http_requests_total Total requests\n# TYPE http_requests_total counter\nhttp_requests_total{method="POST",status="500"} 42.5 1670000000000\n\nprocess_cpu_seconds 3.14\n',
    parse_openmetrics(Text, Metrics),
    length(Metrics, 2),
    Metrics = [
        metric(http_requests_total, 42.5, [method='POST', status='500'], 1670000000000),
        metric(process_cpu_seconds, 3.14, [], 0)
    ].

:- end_tests(openmetrics).

:- begin_tests(structured_log).

test(json_log_line_parsing) :-
    LogJson = '{"timestamp":1670000000500,"level":"ERROR","service":"auth","message":"token expired","trace_id":"t001","span_id":"s001","user_id":"u42"}',
    parse_log_line(LogJson, Record),
    Record = log_record(1670000000500, 'ERROR', 'auth', 'token expired', 't001', 's001', Attrs),
    member(user_id='u42', Attrs).

test(logfmt_line_parsing) :-
    Logfmt = 'ts=1670000000600 level=WARN service=database msg="slow query detected" trace_id=t001 duration_ms=450',
    parse_log_line(Logfmt, Record),
    Record = log_record(1670000000600, 'WARN', 'database', 'slow query detected', 't001', '', Attrs),
    member(duration_ms='450', Attrs).

:- end_tests(structured_log).
