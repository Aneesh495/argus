/*
 * Master integration test runner for Argus.
 * Runs Incident Zoo end-to-end evaluations and embedded HTTP server tests.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(run_integration_tests, [
    run_all_integration_tests/0
]).

:- use_module('test_end_to_end_zoo').
:- use_module('test_http_api').

run_all_integration_tests :-
    format("~n--- Running Incident Zoo End-to-End Tests ---~n"),
    run_zoo_integration_tests,
    format("~n--- Running Embedded HTTP REST Server Tests ---~n"),
    run_http_api_tests,
    format("~nAll Argus integration tests passed successfully!~n").
