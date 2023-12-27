"""Terminal ASCII causal dependency DAG and service topology renderer."""

import json
from typing import Dict, List, Any

def render_ascii_dag(trace_json_path: str) -> str:
    """Renders hierarchical ASCII tree of spans in the trace."""
    with open(trace_json_path, "r") as f:
        doc = json.load(f)

    spans_by_id = {}
    children_map = {}
    roots = []

    if "resourceSpans" in doc:
        for rs in doc.get("resourceSpans", []):
            svc = "unknown"
            for attr in rs.get("resource", {}).get("attributes", []):
                if attr.get("key") == "service.name":
                    svc = attr.get("value", {}).get("stringValue", "unknown")
            for ss in rs.get("scopeSpans", []):
                for s in ss.get("spans", []):
                    s_id = s.get("spanId")
                    p_id = s.get("parentSpanId", "")
                    start = int(s.get("startTimeUnixNano", 0)) // 1000
                    end = int(s.get("endTimeUnixNano", 0)) // 1000
                    dur_ms = (end - start) / 1000.0
                    is_err = s.get("status", {}).get("code") in [2, "STATUS_CODE_ERROR"]

                    rec = {
                        "id": s_id,
                        "parent": p_id,
                        "service": svc,
                        "name": s.get("name", "span"),
                        "duration_ms": dur_ms,
                        "error": is_err
                    }
                    spans_by_id[s_id] = rec

        for s_id, rec in spans_by_id.items():
            p_id = rec["parent"]
            if not p_id or p_id not in spans_by_id:
                roots.append(s_id)
            else:
                children_map.setdefault(p_id, []).append(s_id)

    lines = []
    lines.append("=== ARGUS CAUSAL TOPOLOGY TREE ===")
    
    def print_node(node_id: str, prefix: str = "", is_last: bool = True):
        rec = spans_by_id[node_id]
        connector = "`-- " if is_last else "|-- "
        err_str = " [FAILED]" if rec["error"] else ""
        lines.append(f"{prefix}{connector}[{rec['service']}] {rec['name']} ({rec['duration_ms']:.2f} ms){err_str}")
        
        child_ids = children_map.get(node_id, [])
        for i, cid in enumerate(child_ids):
            child_is_last = (i == len(child_ids) - 1)
            child_prefix = prefix + ("    " if is_last else "|   ")
            print_node(cid, child_prefix, child_is_last)

    for r in roots:
        print_node(r, "", True)

    lines.append("==================================")
    return "\n".join(lines)
