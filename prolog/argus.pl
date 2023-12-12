/*
 * Module: argus
 * Purpose: Master top-level API entrypoint for the Argus Distributed Trace RCA Engine.
 * Exports public interfaces for ingestion, causal topology, abductive diagnosis, and remediation.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus, [
    argus_version/1,
    argus_diagnose_trace_file/3,
    argus_diagnose_json/3,
    argus_remediate_incident/2,
    argus_full_pipeline/5,
    argus_ingest_trace_file/2
]).

% Foundational Core
:- use_module(core/types).
:- use_module(core/error).
:- use_module(core/graph).
:- use_module(core/interval).
:- use_module(core/stats).

% DCG Parsers & Protocol Ingestion
:- use_module(parser/w3c_trace_context).
:- use_module(parser/otlp_json).
:- use_module(parser/jaeger_json).
:- use_module(parser/openmetrics).
:- use_module(parser/structured_log).

% Causal Topology & Geometry
:- use_module(topology/builder).
:- use_module(topology/critical_path).
:- use_module(topology/clock_skew).
:- use_module(topology/concurrency).

% Abductive Diagnostic Engine & Causal SCM
:- use_module(engine/abductive).
:- use_module(engine/hypothesis).
:- use_module(engine/explanation).
:- use_module(engine/causal).
:- use_module(engine/counterfactual).

% Domain Failure Rules & Master Diagnoser
:- use_module(rules/diagnose).

% Automated Remediation Policy Synthesizer
:- use_module(remediation/synthesizer).
:- use_module(remediation/envoy_filter).
:- use_module(remediation/k8s_patch).
:- use_module(remediation/circuit_tuner).
:- use_module(remediation/chaos_manifest).

:- use_module(library(readutil)).

/**
 * argus_version(-VersionAtom)
 */
argus_version('1.0.0').

/**
 * argus_ingest_trace_file(+FilePath, -Spans)
 * Automatically detects whether file is OTLP JSON or Jaeger JSON and parses into spans.
 */
argus_ingest_trace_file(FilePath, Spans) :-
    read_file_to_string(FilePath, Content, []),
    (   sub_atom(Content, _, _, _, 'resourceSpans')
    ->  otlp_json_parse(Content, Spans)
    ;   sub_atom(Content, _, _, _, 'data')
    ->  jaeger_json_parse(Content, Spans)
    ;   otlp_json_parse(Content, Spans)
    ).

/**
 * argus_diagnose_trace_file(+FilePath, -RankedHypotheses, -Explanation)
 */
argus_diagnose_trace_file(FilePath, Ranked, Explanation) :-
    argus_ingest_trace_file(FilePath, RawSpans),
    correct_clock_skews(RawSpans, Spans),
    diagnose_incident_with_explanation(Spans, [], [], Ranked, Explanation).

/**
 * argus_diagnose_json(+TraceJson, -RankedHypotheses, -Explanation)
 */
argus_diagnose_json(TraceJson, Ranked, Explanation) :-
    otlp_json_parse(TraceJson, RawSpans),
    correct_clock_skews(RawSpans, Spans),
    diagnose_incident_with_explanation(Spans, [], [], Ranked, Explanation).

/**
 * argus_remediate_incident(+Explanation, -RemediationActions)
 */
argus_remediate_incident(explanation(Fault, Svc, _, _, _), Actions) :-
    synthesize_remediation(Fault, Svc, Actions).

/**
 * argus_full_pipeline(+TraceFile, +MetricsFile, +LogsFile, -Diagnosis, -Remediation)
 */
argus_full_pipeline(TraceFile, MetricsFile, LogsFile, Explanation, Actions) :-
    argus_ingest_trace_file(TraceFile, RawSpans),
    correct_clock_skews(RawSpans, Spans),
    
    (   MetricsFile \== none, exists_file(MetricsFile)
    ->  read_file_to_string(MetricsFile, MContent, []),
        parse_openmetrics(MContent, Metrics)
    ;   Metrics = []
    ),
    
    (   LogsFile \== none, exists_file(LogsFile)
    ->  open(LogsFile, read, LStream),
        call_cleanup(parse_log_stream(LStream, Logs), close(LStream))
    ;   Logs = []
    ),
    
    diagnose_incident_with_explanation(Spans, Metrics, Logs, _, Explanation),
    argus_remediate_incident(Explanation, Actions).
