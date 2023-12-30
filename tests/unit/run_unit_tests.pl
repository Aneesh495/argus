/*
 * Master runner for all Argus unit test suites.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(run_unit_tests, [
    run_all_unit_tests/0
]).

:- use_module('test_core').
:- use_module('test_parsers').
:- use_module('test_topology').
:- use_module('test_engine').
:- use_module('test_rules').
:- use_module('test_remediation').

run_all_unit_tests :-
    format("~n--- Running Core Unit Tests ---~n"),
    run_core_tests,
    format("~n--- Running Parser Unit Tests ---~n"),
    run_parser_tests,
    format("~n--- Running Topology Unit Tests ---~n"),
    run_topology_tests,
    format("~n--- Running Diagnostic Engine Unit Tests ---~n"),
    run_engine_tests,
    format("~n--- Running Failure Rules Unit Tests ---~n"),
    run_rules_tests,
    format("~n--- Running Remediation Unit Tests ---~n"),
    run_remediation_tests,
    format("~nAll Argus unit tests passed successfully!~n").
