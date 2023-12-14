/*
 * Module: argus_api_handlers
 * Purpose: HTTP REST API route handlers for health, diagnosis, and remediation endpoints.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_api_handlers, [
    handle_health/1,
    handle_diagnose/1,
    handle_remediate/1
]).

:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_parameters)).
:- use_module('../argus').
:- use_module('../parser/otlp_json').
:- use_module('../rules/diagnose').
:- use_module('../remediation/synthesizer').

/**
 * handle_health(+Request)
 * GET /health
 */
handle_health(_Request) :-
    reply_json_dict(json{
        status: "ok",
        service: "argus-rca-engine",
        version: "1.0.0"
    }).

/**
 * handle_diagnose(+Request)
 * POST /api/v1/diagnose
 */
handle_diagnose(Request) :-
    http_read_json_dict(Request, Body),
    (   get_dict(spans, Body, SpanDicts)
    ->  otlp_dict_to_spans(json{spans: SpanDicts}, Spans)
    ;   Spans = []
    ),
    diagnose_incident_with_explanation(Spans, [], [], Ranked, Explanation),
    format_ranked_hypotheses(Ranked, RankedDicts),
    explanation_to_dict(Explanation, ExplDict),
    reply_json_dict(json{
        status: "ok",
        ranked_hypotheses: RankedDicts,
        explanation: ExplDict
    }).

/**
 * handle_remediate(+Request)
 * POST /api/v1/remediate
 */
handle_remediate(Request) :-
    http_read_json_dict(Request, Body),
    get_dict(fault, Body, FaultAtom),
    get_dict(service, Body, SvcAtom),
    synthesize_remediation(FaultAtom, SvcAtom, Actions),
    maplist(action_to_dict, Actions, ActionDicts),
    reply_json_dict(json{
        status: "ok",
        actions: ActionDicts
    }).

format_ranked_hypotheses([], []).
format_ranked_hypotheses([ranked(Rank, Conf, cand_hyp(Fault, Svc, Prior, EvList))|Rest],
                         [json{rank: Rank, confidence: Conf, fault: Fault, service: Svc, prior: Prior, evidence: EvList}|RestDicts]) :-
    format_ranked_hypotheses(Rest, RestDicts).

explanation_to_dict(explanation(Fault, Svc, Conf, Chain, EvList), json{
    root_fault: Fault,
    service: Svc,
    confidence: Conf,
    causal_chain: Chain,
    evidence_count: EvCount
}) :-
    length(EvList, EvCount).

action_to_dict(remediation(ActionType, Svc, Params), json{
    action: ActionType,
    service: Svc,
    parameters: ParamDict
}) :-
    dict_create(ParamDict, json, Params).
