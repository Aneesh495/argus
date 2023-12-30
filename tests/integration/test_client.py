"""Unit and integration tests for Argus Python SDK and CLI."""

import unittest
import os
from argus.client import ArgusClient
from argus.flamegraph import render_flamegraph
from argus.graph_view import render_ascii_dag

class TestArgusPythonSDK(unittest.TestCase):
    def setUp(self):
        self.client = ArgusClient()
        self.repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        self.trace_retry = os.path.join(self.repo_root, "data", "zoo", "01_retry_storm_cascade", "trace.json")
        self.trace_pool = os.path.join(self.repo_root, "data", "zoo", "02_connection_pool_starvation", "trace.json")

    def test_diagnose_retry_storm(self):
        res = self.client.diagnose_trace(self.trace_retry)
        self.assertEqual(res["status"], "ok")
        self.assertEqual(res["root_fault"], "retry_storm")
        self.assertEqual(res["originating_service"], "api-gateway")
        self.assertGreater(res["confidence"], 0.80)

    def test_diagnose_connection_pool(self):
        res = self.client.diagnose_trace(self.trace_pool)
        self.assertEqual(res["status"], "ok")
        self.assertEqual(res["root_fault"], "connection_pool_starvation")
        self.assertEqual(res["originating_service"], "inventory-db")
        self.assertGreater(res["confidence"], 0.80)

    def test_flamegraph_rendering(self):
        fg = render_flamegraph(self.trace_retry)
        self.assertIn("ARGUS DISTRIBUTED TRACE FLAMEGRAPH", fg)
        self.assertIn("POST /checkout", fg)
        self.assertIn("chargeCard", fg)

    def test_ascii_dag_rendering(self):
        dag = render_ascii_dag(self.trace_retry)
        self.assertIn("ARGUS CAUSAL TOPOLOGY TREE", dag)
        self.assertIn("POST /checkout", dag)

if __name__ == "__main__":
    unittest.main()
