import os
import shutil
import sys
import unittest


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "clients", "python"))

from zmr_client import ZmrClient, ZmrRpcError  # noqa: E402


class PythonClientTest(unittest.TestCase):
    def test_drives_stdio_json_rpc_session(self):
        node = shutil.which("node")
        self.assertIsNotNone(node)
        client = ZmrClient(
            node,
            [os.path.join(ROOT, "tests", "fake-json-rpc-server.mjs")],
        )
        try:
            capabilities = client.capabilities()
            self.assertEqual(capabilities["protocolVersion"], "2026-04-28")
            self.assertIn("observe.snapshot", capabilities["methods"])

            session = client.create_session()
            self.assertEqual(session["sessionId"], "default")

            self.assertTrue(client.open_link("exampleapp://python-client"))
            self.assertTrue(client.wait_until({"text": "Home"}, timeout_ms=1000))

            snapshot = client.snapshot()
            self.assertEqual(snapshot["activePackage"], "com.example.mobiletest")
            self.assertEqual(snapshot["nodes"][0]["text"], "Home")

            exported = client.export_trace("traces/python-client.zmrtrace", redact=True, omit_screenshots=True)
            self.assertTrue(exported["redacted"])
            self.assertTrue(exported["omitScreenshots"])

            events = client.trace_events(0, limit=10)
            self.assertEqual(events["nextSeq"], 2)
            self.assertEqual(events["events"][0]["kind"], "rpc.request")
        finally:
            client.close()

    def test_raises_json_rpc_errors_with_details(self):
        node = shutil.which("node")
        self.assertIsNotNone(node)
        client = ZmrClient(
            node,
            [os.path.join(ROOT, "tests", "fake-json-rpc-server.mjs")],
        )
        try:
            with self.assertRaises(ZmrRpcError) as caught:
                client.request("missing.method", {})
            self.assertEqual(caught.exception.code, -32601)
            self.assertEqual(str(caught.exception), "method not found")
        finally:
            client.close()


if __name__ == "__main__":
    unittest.main()
