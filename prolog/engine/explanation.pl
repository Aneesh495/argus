/*
 * Module: argus_explanation
 * Purpose: Causal explanation synthesis, propagation chain formatting, and report generation.
 * Synthesizes root-cause diagnostic reports with exact causal mechanisms and evidence chains.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_explanation, [
    explanation_create/6,
    explanation_to_text/2,
    explanation_to_json/2,
    explain_propagation_chain/3
]).

:- use_module(library(lists)).
:- use_module(library(http/json)).

/**
 * explanation_create(+RootFault, +RootService, +Confidence, +CausalChain, +Evidence, -Explanation)
 */
explanation_create(Fault, Svc, Conf, Chain, Evidence,
                   explanation(Fault, Svc, Conf, Chain, Evidence)).

/**
 * explanation_to_text(+Explanation, -FormattedText)
 * Formats a comprehensive diagnostic explanation summary.
 */
explanation_to_text(explanation(Fault, Svc, Conf, Chain, Evidence), Text) :-
    Pct is Conf * 100.0,
    format_chain(Chain, ChainStr),
    format_evidence_items(Evidence, EvStr),
    format(atom(Text),
"=== ARGUS ROOT CAUSE DIAGNOSIS ===\n\
Root Fault: ~w\n\
Originating Service: ~w\n\
Diagnostic Confidence: ~1f%\n\
Causal Propagation Path: ~w\n\
Corroborating Evidence:\n~w\
==================================\n",
           [Fault, Svc, Pct, ChainStr, EvStr]).

format_chain([], "Local (Single Service)") :- !.
format_chain(Chain, Str) :-
    atomic_list_concat(Chain, ' -> ', Str).

format_evidence_items([], "  (No explicit evidence records)\n") :- !.
format_evidence_items(Items, Str) :-
    maplist(format_one_ev, Items, Lines),
    atomic_list_concat(Lines, Str).

format_one_ev(ev(Desc, W), Line) :-
    format(atom(Line), "  * ~w (weight: ~2f)\n", [Desc, W]).
format_one_ev(Desc, Line) :-
    format(atom(Line), "  * ~w\n", [Desc]).

/**
 * explanation_to_json(+Explanation, -JsonString)
 */
explanation_to_json(explanation(Fault, Svc, Conf, Chain, Evidence), JsonStr) :-
    maplist(ev_to_atom, Evidence, EvAtoms),
    Dict = json{
        root_fault: Fault,
        service: Svc,
        confidence: Conf,
        causal_chain: Chain,
        evidence: EvAtoms
    },
    atom_json_dict(JsonAtom, Dict, [as(atom)]),
    atom_string(JsonAtom, JsonStr).

ev_to_atom(ev(Desc, _), Desc) :- !.
ev_to_atom(Desc, Desc).

/**
 * explain_propagation_chain(+TopologyEdges, +RootSvc, -Chains)
 * Traces all downstream paths influenced by RootSvc in the topology.
 */
explain_propagation_chain(Edges, RootSvc, Chains) :-
    findall(Path, trace_path(RootSvc, Edges, [RootSvc], Path), RawChains),
    (   RawChains \= [] -> Chains = RawChains ; Chains = [[RootSvc]] ).

trace_path(Current, Edges, Visited, Path) :-
    member(service_edge(Current, Next, _, _, _), Edges),
    \+ member(Next, Visited),
    (   trace_path(Next, Edges, [Next|Visited], Path)
    ;   reverse([Next|Visited], Path)
    ).
