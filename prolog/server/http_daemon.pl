/*
 * Module: argus_http_daemon
 * Purpose: Embedded multithreaded HTTP daemon for Argus REST API server.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_http_daemon, [
    start_argus_server/1,
    stop_argus_server/1,
    run_argus_server_foreground/1
]).

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module('api_handlers').

% Route Registrations
:- http_handler(root(health), handle_health, [methods([get])]).
:- http_handler(root('api/v1/diagnose'), handle_diagnose, [methods([post])]).
:- http_handler(root('api/v1/remediate'), handle_remediate, [methods([post])]).

/**
 * start_argus_server(+Port)
 * Starts the HTTP server on Port in a background thread.
 */
start_argus_server(Port) :-
    http_server(http_dispatch, [port(Port)]).

/**
 * stop_argus_server(+Port)
 */
stop_argus_server(Port) :-
    http_stop_server(Port, []).

/**
 * run_argus_server_foreground(+Port)
 * Starts server and blocks the main thread to serve requests until interrupted.
 */
run_argus_server_foreground(Port) :-
    start_argus_server(Port),
    format("Argus RCA Engine HTTP Daemon listening on http://localhost:~w~n", [Port]),
    thread_get_message(_).
