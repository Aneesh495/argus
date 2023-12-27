"""Terminal ANSI flamegraph and timeline visualizer for distributed traces."""

import json
from typing import List, Dict, Any

COLOR_RESET = "\033[0m"
COLOR_RED = "\033[31;1m"
COLOR_GREEN = "\033[32m"
COLOR_YELLOW = "\033[33m"
COLOR_BLUE = "\033[34m"
COLOR_CYAN = "\033[36m"
COLOR_BOLD = "\033[1m"

def render_flamegraph(trace_json_path: str, max_width: int = 80) -> str:
    """Reads OTLP or Jaeger trace JSON and renders an ASCII/ANSI execution flamegraph."""
    with open(trace_json_path, "r") as f:
        doc = json.load(f)

    spans = []
    if "resourceSpans" in doc:
        for rs in doc.get("resourceSpans", []):
            svc = "unknown"
            for attr in rs.get("resource", {}).get("attributes", []):
                if attr.get("key") == "service.name":
                    svc = attr.get("value", {}).get("stringValue", "unknown")
            for ss in rs.get("scopeSpans", []):
                for s in ss.get("spans", []):
                    start = int(s.get("startTimeUnixNano", 0)) // 1000
                    end = int(s.get("endTimeUnixNano", 0)) // 1000
                    is_err = s.get("status", {}).get("code") in [2, "STATUS_CODE_ERROR"]
                    spans.append({
                        "id": s.get("spanId"),
                        "parent": s.get("parentSpanId", ""),
                        "service": svc,
                        "name": s.get("name", "span"),
                        "start": start,
                        "end": end,
                        "dur": max(1, end - start),
                        "error": is_err
                    })

    if not spans:
        return "No spans found in trace file."

    min_start = min(s["start"] for s in spans)
    max_end = max(s["end"] for s in spans)
    total_dur = max(1, max_end - min_start)

    lines = []
    lines.append(f"{COLOR_BOLD}=== ARGUS DISTRIBUTED TRACE FLAMEGRAPH ==={COLOR_RESET}")
    lines.append(f"Trace Duration: {total_dur / 1000.0:.2f} ms | Span Count: {len(spans)}")
    lines.append("-" * max_width)

    # Sort spans by start time
    spans.sort(key=lambda x: (x["start"], -x["dur"]))

    for s in spans:
        offset_pct = (s["start"] - min_start) / total_dur
        dur_pct = s["dur"] / total_dur

        indent = int(offset_pct * (max_width - 30))
        bar_len = max(1, int(dur_pct * (max_width - 30)))

        color = COLOR_RED if s["error"] else COLOR_CYAN
        bar = "=" * bar_len
        err_badge = f"{COLOR_RED}[ERR]{COLOR_RESET}" if s["error"] else ""

        line = f"{s['service']:<15} {s['dur']/1000.0:>7.2f}ms | {' ' * indent}{color}{bar}{COLOR_RESET} {s['name']} {err_badge}"
        lines.append(line)

    lines.append("-" * max_width)
    return "\n".join(lines)
