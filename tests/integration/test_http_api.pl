/*
 * Integration tests for Argus Embedded HTTP Daemon and REST API.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(test_http_api, [
    run_http_api_tests/0
]).

:- use_module(library(plunit)).
:- use_module(library(http/http_open)).
:- use_module(library(http/json)).
:- use_module('../../prolog/server/http_daemon').

run_http_api_tests :-
    run_tests([http_api]).

:- begin_tests(http_api).

test(http_daemon_health_check) :-
    Port = 9876,
    start_argus_server(Port),
    call_cleanup(
        (   format(atom(Url), "http://localhost:~w/health", [Port]),
            http_open(Url, In, []),
            call_cleanup(
                (   json_read_dict(In, Dict),
                    get_dict(status, Dict, Status),
                    Status == "ok"
                ),
                close(In)
            )
        ),
        stop_argus_server(Port)
    ),
    !.

:- end_tests(http_api).
