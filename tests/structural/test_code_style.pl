/*
 * Structural and architectural style verification tests for Argus.
 * Asserts module boundaries, clean exports, and absence of syntax anomalies.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(test_code_style, [
    run_style_tests/0
]).

:- use_module(library(plunit)).

run_style_tests :-
    run_tests([code_style]).

:- begin_tests(code_style).

test(all_modules_consult_cleanly) :-
    Modules = [
        'prolog/core/types.pl',
        'prolog/core/error.pl',
        'prolog/core/graph.pl',
        'prolog/core/interval.pl',
        'prolog/core/stats.pl',
        'prolog/parser/w3c_trace_context.pl',
        'prolog/parser/otlp_json.pl',
        'prolog/parser/jaeger_json.pl',
        'prolog/parser/openmetrics.pl',
        'prolog/parser/structured_log.pl',
        'prolog/topology/builder.pl',
        'prolog/topology/critical_path.pl',
        'prolog/topology/clock_skew.pl',
        'prolog/topology/concurrency.pl',
        'prolog/engine/abductive.pl',
        'prolog/engine/hypothesis.pl',
        'prolog/engine/explanation.pl',
        'prolog/engine/causal.pl',
        'prolog/engine/counterfactual.pl',
        'prolog/rules/retry_storm.pl',
        'prolog/rules/connection_pool.pl',
        'prolog/rules/queue_saturation.pl',
        'prolog/rules/gc_pause.pl',
        'prolog/rules/thread_exhaustion.pl',
        'prolog/rules/lock_contention.pl',
        'prolog/rules/circuit_breaker.pl',
        'prolog/rules/memory_pressure.pl',
        'prolog/rules/cache_stampede.pl',
        'prolog/rules/network_partition.pl',
        'prolog/rules/disk_io_stall.pl',
        'prolog/rules/distributed_txn.pl',
        'prolog/rules/diagnose.pl',
        'prolog/remediation/synthesizer.pl',
        'prolog/remediation/envoy_filter.pl',
        'prolog/remediation/k8s_patch.pl',
        'prolog/remediation/circuit_tuner.pl',
        'prolog/remediation/chaos_manifest.pl',
        'prolog/server/api_handlers.pl',
        'prolog/server/http_daemon.pl',
        'prolog/bench/generator.pl',
        'prolog/bench/runner.pl',
        'prolog/argus.pl'
    ],
    maplist(verify_module_file, Modules).

test(no_dangling_exports) :-
    % Verify that argus module exposes expected public API
    consult('prolog/argus.pl'),
    current_predicate(argus:argus_version/1),
    current_predicate(argus:argus_diagnose_trace_file/3),
    current_predicate(argus:argus_diagnose_json/3),
    current_predicate(argus:argus_remediate_incident/2),
    current_predicate(argus:argus_full_pipeline/5).

:- end_tests(code_style).

verify_module_file(RelPath) :-
    exists_file(RelPath),
    catch(consult(RelPath), Error, (
        format(user_error, "Failed to consult ~w: ~w~n", [RelPath, Error]),
        fail
    )).
