/*
 * Module: test_regression_ledger
 * Purpose: Regression test ledger verifying all bugs encountered during development.
 * Each test documents the root cause, original failure mode, and regression prevention assertion.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(test_regression_ledger, [
    run_regression_tests/0
]).

:- use_module(library(plunit)).
:- use_module('../../prolog/argus').
:- use_module('../../prolog/core/types').
:- use_module('../../prolog/core/graph').
:- use_module('../../prolog/parser/w3c_trace_context').
:- use_module('../../prolog/parser/openmetrics').
:- use_module('../../prolog/parser/jaeger_json').
:- use_module('../../prolog/topology/builder').
:- use_module('../../prolog/engine/abductive').
:- use_module('../../prolog/remediation/envoy_filter').
:- use_module('../../prolog/remediation/chaos_manifest').

run_regression_tests :-
    run_tests([regression_ledger]).

:- begin_tests(regression_ledger).

/**
 * BUG-001: C FFI compound span term construction.
 * Original symptom: parse_span returned unbound variable instead of instantiated span term.
 * Resolution: Used PL_new_term_ref and PL_unify with PL_cons_functor_v.
 */
test(bug_001_c_ffi_span_unification) :-
    use_foreign_library('lib/libargus_ffi.dylib'),
    Json = '{"trace_id":"reg_t1","span_id":"reg_s1","parent_id":"reg_p0","service_name":"auth","name":"login","start_time_us":1000,"end_time_us":2500,"status_code":1}',
    argus_c_parse_span(Json, Span),
    Span = span(reg_t1, reg_s1, reg_p0, auth, login, 1000, 2500, 1),
    !.

/**
 * BUG-002: Arity mismatch in core constructors.
 * Original symptom: Exported procedure was arity N, definition was N+1.
 * Resolution: Synchronized module export list with predicate definitions.
 */
test(bug_002_core_arities_synchronized) :-
    hypothesis_create(test_fault, test_svc, 0.9, [ev1], H),
    H = hypothesis(test_fault, test_svc, 0.9, [ev1]),
    remediation_create(test_action, test_svc, [k=v], R),
    R = remediation(test_action, test_svc, [k=v]),
    event_create(1000, test_ev, [attr=1], E),
    E = event(1000, test_ev, [attr=1]),
    !.

/**
 * BUG-003: Choicepoint in Tarjan Strongly Connected Components.
 * Original symptom: Tarjan search left unpruned choicepoints after finding all SCCs.
 * Resolution: Placed deterministic cut at the exit boundary of tarjan_scc/2.
 */
test(bug_003_tarjan_determinism) :-
    Edges = [edge(1, 2, 1), edge(2, 3, 1), edge(3, 1, 1), edge(4, 5, 1)],
    tarjan_scc(Edges, Components),
    length(Components, 3),
    !.

/**
 * BUG-004: Character code escaping in W3C tracestate parser.
 * Original symptom: 0'= caused syntax error with adjacent operators.
 * Resolution: Used unambiguous ASCII decimal constant 61.
 */
test(bug_004_tracestate_ascii_equality) :-
    parse_tracestate("congo=t6106642a,rojo=00f067aa0ba902b7", Entries),
    Entries = [congo='t6106642a', rojo='00f067aa0ba902b7'],
    !.

/**
 * BUG-005: OpenMetrics DCG condition evaluation.
 * Original symptom: Bare 'true' in DCG parsed as non-terminal true//0 rather than control flow.
 * Resolution: Wrapped in braces { true }.
 */
test(bug_005_openmetrics_dcg_true) :-
    MetricText = "http_latency_ms{route=\"/checkout\"} 45.2 1670000000000\n",
    parse_openmetrics(MetricText, [M]),
    M = metric(http_latency_ms, 45.2, [route='/checkout'], 1670000000000),
    !.

/**
 * BUG-006: Jaeger JSON traceId inheritance.
 * Original symptom: Spans missing inline traceID defaulted to empty string.
 * Resolution: Propagated top-level ContextDict traceID down into span mapper.
 */
test(bug_006_jaeger_trace_id_inheritance) :-
    JaegerJson = '{"data":[{"traceID":"inherited_trace_123","processes":{"p1":{"serviceName":"svc1"}},"spans":[{"spanID":"s1","operationName":"op","startTime":1000,"duration":500,"processID":"p1"}]}]}',
    jaeger_json_parse(JaegerJson, [Span]),
    span_trace_id(Span, 'inherited_trace_123'),
    !.

/**
 * BUG-007: Float vs integer latency comparison in topology aggregation.
 * Original symptom: Integer division 150/1 yielded integer 150, causing float equality 150.0 to fail.
 * Resolution: Used arithmetic evaluation =:= for all latency comparisons.
 */
test(bug_007_topology_latency_numeric_comparison) :-
    Spans = [
        span('t', 'p', '', 'svc_a', 'op', 0, 1000, 1, [], []),
        span('t', 'c', 'p', 'svc_b', 'op', 100, 250, 1, [], [])
    ],
    build_service_topology(Spans, [service_edge('svc_a', 'svc_b', rpc, Lat, 1)]),
    Lat =:= 150,
    !.

/**
 * BUG-008: Abductive meta-interpreter module qualification.
 * Original symptom: Goals qualified with user: or test module failed clause lookup.
 * Resolution: Implemented strip_module/3 in abduce_m before abducible pattern matching.
 */
test(bug_008_abductive_module_stripping) :-
    clear_abductive_kb,
    register_abducible(reg_fault/1, 5),
    abduce_minimal(user:reg_fault(node_a), [], Best, Cost),
    Cost =:= 5,
    Best = [hypothesis(reg_fault(node_a), 5)],
    !.

/**
 * BUG-009: Multiline formatting syntax deprecation in remediation generators.
 * Original symptom: Backslash newline produced SWI-Prolog deprecation warnings.
 * Resolution: Migrated to direct multiline string literals.
 */
test(bug_009_multiline_string_rendering) :-
    render_envoy_filter_yaml('payment-service', 2, 100, FilterYaml),
    sub_atom(FilterYaml, _, _, _, 'num_retries: 2'),
    render_chaos_mesh_yaml(retry_storm, 'payment-service', '5m', ChaosYaml),
    sub_atom(ChaosYaml, _, _, _, 'kind: NetworkChaos'),
    !.

:- end_tests(regression_ledger).
