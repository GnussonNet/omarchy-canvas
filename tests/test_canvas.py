import io
import json
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock

from canvas import CanvasError, Client, NoRedirect, collect, origin, submission_status


class ReaderTests(unittest.TestCase):
    def test_only_read_routes_and_safe_parameters(self):
        client = Client("https://canvas.example", "secret")
        response = io.StringIO("[]")
        response.headers = {}
        client.opener = Mock()
        client.opener.open.return_value = response
        client.get("https://canvas.example/api/v1/courses")
        request = client.opener.open.call_args.args[0]
        self.assertEqual(request.method, "GET")
        self.assertIsNone(request.data)
        for url in ["https://evil.example/api/v1/courses", "http://canvas.example/api/v1/courses",
                    "https://canvas.example/api/v1/courses/1/assignments/2/submissions",
                    "https://canvas.example/api/v1/courses?include[]=read_status",
                    "https://canvas.example/api/v1/courses?include[]=submission&include[]=read_status"]:
            with self.subTest(url=url), self.assertRaises(CanvasError):
                client.get(url)
        self.assertEqual(client.opener.open.call_count, 1)

    def test_redirects_blocked(self):
        with self.assertRaises(CanvasError):
            NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.example")

    def test_origin_validation(self):
        for url in ["http://canvas.example", "https://token@canvas.example", "https://canvas.example/path", "https://canvas.example?token=secret"]:
            with self.assertRaises(CanvasError):
                origin(url)

    def test_pagination(self):
        client = Client("https://canvas.example", "secret")
        client.get = Mock(side_effect=[([{"id": 1}], "https://canvas.example/api/v1/courses?page=2"), ([{"id": 2}], None)])
        self.assertEqual(list(client.pages("/api/v1/courses", {})), [{"id": 1}, {"id": 2}])

    def test_link_parsing(self):
        client = Client("https://canvas.example", "secret")
        response = io.StringIO("[]")
        response.headers = {"Link": '<https://canvas.example/api/v1/courses?page=2>; rel="next", <https://canvas.example/api/v1/courses?page=1>; rel="current"'}
        client.opener = Mock()
        client.opener.open.return_value = response
        self.assertEqual(client.get(client.base + "/api/v1/courses")[1], client.base + "/api/v1/courses?page=2")

    def test_submission_is_personal(self):
        self.assertEqual(submission_status({"has_submitted_submissions": True, "submission": {"workflow_state": "unsubmitted"}}), "Not submitted")
        cases = [({"submitted_at": "2026-09-26T12:00:00Z"}, "Submitted"),
                 ({"workflow_state": "pending_review"}, "Submitted"),
                 ({"workflow_state": "graded"}, "Graded"),
                 ({"excused": True}, "Excused"),
                 ({"submitted_at": "date", "redo_request": True}, "Resubmission requested")]
        for sub, expected in cases:
            self.assertEqual(submission_status({"submission": sub}), expected)
        self.assertEqual(submission_status({}), "Unknown")

    def test_window_boundaries_submitted_and_sorting(self):
        now = datetime(2026, 9, 26, 12, tzinfo=timezone.utc)
        def assignment(aid, delta):
            return {"id": aid, "name": "Assignment", "due_at": (now + delta).isoformat(), "submission": {"workflow_state": "submitted"}}
        source = [assignment(1, timedelta(days=7)), assignment(2, timedelta(seconds=-1)),
                  assignment(3, timedelta()), assignment(4, timedelta(days=7, seconds=1)),
                  {"id": 5, "name": "Undated", "due_at": None}]
        client = Mock(base="https://canvas.example")
        client.pages.side_effect = [[{"id": "1", "name": "Math"}], source]
        result = collect(client, now)
        self.assertEqual([r["id"] for r in result["assignments"]], ["1:3", "1:1"])
        self.assertTrue(all(r["status"] == "Submitted" for r in result["assignments"]))
        self.assertEqual(result["assignments"][0]["url"], "https://canvas.example/courses/1/assignments/3")

    def test_partial_failure_warns(self):
        client = Mock(base="https://canvas.example")
        client.pages.side_effect = [[{"id": "1", "name": "Math"}, {"id": "2", "name": "Art"}], CanvasError("Access denied"), []]
        result = collect(client)
        self.assertEqual(result["warnings"], ["Math: Access denied"])


if __name__ == "__main__":
    unittest.main()
