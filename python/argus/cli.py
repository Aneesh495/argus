"""Argus Interactive Terminal CLI driver."""

import sys
import os
import argparse
from argus.client import ArgusClient
from argus.flamegraph import render_flamegraph
from argus.graph_view import render_ascii_dag

def cmd_diagnose(args):
    client = ArgusClient()
    print(f"Running Argus abductive diagnosis on: {args.trace_file}...")
    res = client.diagnose_trace(args.trace_file, args.metrics, args.logs)
    
    if res.get("status") == "ok":
        print("\n" + "=" * 50)
        print("           ARGUS ROOT CAUSE DIAGNOSIS")
        print("=" * 50)
        print(f"Root Fault Diagnosed:     {res['root_fault']}")
        print(f"Originating Microservice: {res['originating_service']}")
        print(f"Diagnostic Confidence:    {res['confidence'] * 100.0:.1f}%")
        print(f"Causal Propagation Path:  {res['causal_chain']}")
        print(f"Synthesized Remediation:  {res['remediation_actions']}")
        print("=" * 50)
    else:
        print(f"Diagnosis error: {res.get('message')}")
        if "raw_output" in res:
            print(res["raw_output"])

def cmd_flamegraph(args):
    print(render_flamegraph(args.trace_file))

def cmd_topology(args):
    print(render_ascii_dag(args.trace_file))

def cmd_bench(args):
    import subprocess
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    cmd = ["swipl", "-g", "consult('prolog/bench/runner.pl'), run_benchmarks, halt.", "-t", "halt(1)"]
    subprocess.run(cmd, cwd=repo_root)

def cmd_zoo(args):
    import subprocess
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    cmd = ["swipl", "-g", "consult('tests/integration/test_end_to_end_zoo.pl'), run_zoo_integration_tests, halt.", "-t", "halt(1)"]
    subprocess.run(cmd, cwd=repo_root)

def main():
    parser = argparse.ArgumentParser(description="Argus: Distributed Trace Abductive Reasoning Engine")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # diagnose
    p_diag = subparsers.add_parser("diagnose", help="Diagnose a distributed trace file")
    p_diag.add_argument("trace_file", help="Path to trace JSON file (OTLP or Jaeger)")
    p_diag.add_argument("--metrics", help="Path to OpenMetrics .prom file", default=None)
    p_diag.add_argument("--logs", help="Path to structured logs .jsonl file", default=None)
    p_diag.set_defaults(func=cmd_diagnose)

    # flamegraph
    p_flame = subparsers.add_parser("flamegraph", help="Render ASCII flamegraph of trace")
    p_flame.add_argument("trace_file", help="Path to trace JSON file")
    p_flame.set_defaults(func=cmd_flamegraph)

    # topology
    p_topo = subparsers.add_parser("topology", help="Render ASCII causal DAG of trace")
    p_topo.add_argument("trace_file", help="Path to trace JSON file")
    p_topo.set_defaults(func=cmd_topology)

    # bench
    p_bench = subparsers.add_parser("bench", help="Run Argus performance benchmarks")
    p_bench.set_defaults(func=cmd_bench)

    # zoo
    p_zoo = subparsers.add_parser("zoo", help="Run full Incident Zoo evaluation suite")
    p_zoo.set_defaults(func=cmd_zoo)

    args = parser.parse_args()
    args.func(args)

if __name__ == "__main__":
    main()
