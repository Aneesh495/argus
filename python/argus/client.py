"""Argus Python Client: programmatic interface to the Argus Prolog RCA engine."""

import os
import json
import subprocess
from typing import Dict, Any, Optional, List

class ArgusClient:
    """Client for running diagnostic queries against the Argus SWI-Prolog engine."""

    def __init__(self, prolog_bin: str = "swipl"):
        self.prolog_bin = prolog_bin
        self.repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

    def diagnose_trace(self, trace_path: str, metrics_path: Optional[str] = None, logs_path: Optional[str] = None) -> Dict[str, Any]:
        """Diagnoses a distributed trace file by running the Argus Prolog engine."""
        abs_trace = os.path.abspath(trace_path)
        m_arg = f"'{os.path.abspath(metrics_path)}'" if metrics_path and os.path.exists(metrics_path) else "none"
        l_arg = f"'{os.path.abspath(logs_path)}'" if logs_path and os.path.exists(logs_path) else "none"

        goal = (
            f"consult('{self.repo_root}/prolog/argus.pl'), "
            f"argus_full_pipeline('{abs_trace}', {m_arg}, {l_arg}, Explanation, Actions), "
            f"Explanation = explanation(Fault, Svc, Conf, Chain, EvList), "
            f"findall(Action, member(Action, Actions), ActionList), "
            f"format('JSON_RESULT: ~w|~w|~w|~w|~w~n', [Fault, Svc, Conf, Chain, ActionList]), "
            f"halt."
        )

        cmd = [self.prolog_bin, "-q", "-g", goal, "-t", "halt(1)"]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=self.repo_root)

        if res.returncode != 0:
            raise RuntimeError(f"Argus Prolog engine execution failed:\n{res.stderr}")

        for line in res.stdout.splitlines():
            if line.startswith("JSON_RESULT: "):
                parts = line.replace("JSON_RESULT: ", "").split("|")
                if len(parts) >= 5:
                    fault = parts[0]
                    service = parts[1]
                    conf = float(parts[2])
                    chain = parts[3]
                    actions = parts[4]
                    return {
                        "status": "ok",
                        "root_fault": fault,
                        "originating_service": service,
                        "confidence": conf,
                        "causal_chain": chain,
                        "remediation_actions": actions
                    }

        return {
            "status": "error",
            "message": "No diagnostic explanation derived by Argus Prolog engine",
            "raw_output": res.stdout
        }
