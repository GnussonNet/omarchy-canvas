import io
import json
import unittest
import os
import tempfile
from pathlib import Path
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, patch

from canvas import CanvasError, Client, NoRedirect, collect, origin, submission_status, save_settings, settings_info, select_courses, read_assignments, validate_days, input_data


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
        client.pages.side_effect = [source]
        result = collect(client, [{"id": "1", "name": "Math"}], now)
        self.assertEqual([r["id"] for r in result["assignments"]], ["1:3", "1:1"])
        self.assertTrue(all(r["status"] == "Submitted" for r in result["assignments"]))
        self.assertEqual(result["assignments"][0]["url"], "https://canvas.example/courses/1/assignments/3")

    def test_partial_failure_warns(self):
        client = Mock(base="https://canvas.example")
        client.pages.side_effect = [CanvasError("Access denied"), []]
        result = collect(client, [{"id": "1", "name": "Math"}, {"id": "2", "name": "Art"}])
        self.assertEqual(result["warnings"], ["Math: Access denied"])

    def test_custom_window_includes_boundary_and_excludes_later(self):
        now = datetime(2026, 9, 26, 12, tzinfo=timezone.utc)
        source = [{"id": i, "name": "Assignment", "due_at": (now + timedelta(days=days)).isoformat()}
                  for i, days in enumerate([3, 10, 14, 15], start=1)]
        client = Mock(base="https://canvas.example")
        client.pages.return_value = source
        courses = [{"id": "1", "name": "Math"}]
        result = collect(client, courses, now, days_ahead=14)
        self.assertEqual([r["id"] for r in result["assignments"]], ["1:1", "1:2", "1:3"])
        self.assertEqual(result["days_ahead"], 14)
        result = collect(client, courses, now, days_ahead=3)
        self.assertEqual([r["id"] for r in result["assignments"]], ["1:1"])

    def test_days_validation(self):
        for value in [0, -1, 91, True, 1.5, "7", None]:
            with self.subTest(value=value), self.assertRaises(CanvasError):
                validate_days(value)

    def test_blank_parameters_are_rejected_before_network(self):
        client = Client("https://canvas.example", "secret")
        client.opener = Mock()
        for query in ["read_status=", "include[]=", "unexpected", "include[]=submission&read_status="]:
            with self.subTest(query=query), self.assertRaises(CanvasError):
                client.get(client.base + "/api/v1/courses?" + query)
        client.opener.open.assert_not_called()

    def test_malformed_response_is_a_canvas_error(self):
        for body in ["not json", "{}", "[null]", "[1]", '["string"]']:
            client = Client("https://canvas.example", "secret")
            response = io.StringIO(body)
            response.headers = {}
            client.opener = Mock()
            client.opener.open.return_value = response
            with self.subTest(body=body), self.assertRaises(CanvasError):
                client.get(client.base + "/api/v1/courses")

    def test_pagination_cannot_change_route_or_loop(self):
        for next_url in ["https://canvas.example/api/v1/courses/2/assignments", "https://canvas.example/api/v1/courses?"]:
            client = Client("https://canvas.example", "secret")
            client.get = Mock(return_value=([], next_url))
            with self.subTest(url=next_url), self.assertRaises(CanvasError):
                list(client.pages("/api/v1/courses", {}))
            self.assertEqual(client.get.call_count, 1)

    def test_complete_failure_is_not_a_successful_empty_refresh(self):
        client = Mock(base="https://canvas.example")
        client.pages.side_effect = CanvasError("Offline")
        result = collect(client, [{"id": "1", "name": "Math"}])
        self.assertFalse(result["ok"])
        self.assertEqual(result["warnings"], ["Math: Offline"])
        self.assertNotIn("updated_at", result)

    def test_incomplete_course_is_not_mixed_with_complete_courses(self):
        def interrupted():
            yield {"id": "1", "name": "Task", "due_at": "2026-10-09T12:00:00Z"}
            raise CanvasError("Page two failed")
        client = Mock(base="https://canvas.example")
        client.pages.side_effect = [interrupted(), []]
        result = collect(client, [{"id": "1", "name": "Math"}, {"id": "2", "name": "Art"}],
                         datetime(2026, 10, 8, tzinfo=timezone.utc))
        self.assertTrue(result["ok"])
        self.assertEqual(result["assignments"], [])
        self.assertEqual(result["warnings"], ["Math: Page two failed"])

    def test_malformed_assignments_isolate_course_failure(self):
        task = {"id": "1", "name": "Task", "due_at": "2026-10-09T12:00:00Z"}
        for fields in [{"due_at": "bad"}, {"due_at": 42}, {"due_at": "2026-10-09T12:00:00"},
                       {"submission": "bad"}, {"submission_types": None}, {"name": None}, {"id": "١"}]:
            client = Mock(base="https://canvas.example")
            client.pages.side_effect = [[dict(task, **fields)], []]
            with self.subTest(fields=fields):
                result = collect(client, [{"id": "1", "name": "Math"}, {"id": "2", "name": "Art"}],
                                 datetime(2026, 10, 8, tzinfo=timezone.utc))
                self.assertTrue(result["ok"])
                self.assertEqual(result["assignments"], [])
                self.assertEqual(len(result["warnings"]), 1)

    def test_invalid_url_and_token_are_rejected_early(self):
        for url in [None, 1, "https://canvas.example:bad", "https://canvas.example:65536", "https://canvas.example\n"]:
            with self.subTest(url=url), self.assertRaises(CanvasError):
                origin(url)
        with self.assertRaises(CanvasError):
            Client("https://canvas.example", "bad\ntoken")

    def test_large_course_selection_input_and_size_limit(self):
        data = {"selected_course_ids": [str(i) for i in range(5000)]}
        with patch("canvas.sys.stdin", io.StringIO(json.dumps(data) + "\n")):
            self.assertEqual(input_data(), data)
        with patch("canvas.sys.stdin", io.StringIO("x" * 1048577)), self.assertRaises(CanvasError):
            input_data()


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "private" / "config.json"
        self.location = patch("canvas.config_path", return_value=self.path)
        self.location.start()
        self.addCleanup(self.location.stop)
        self.get = patch("canvas.Client.get", return_value=([], None)).start()
        self.addCleanup(patch.stopall)

    def test_onboarding_and_private_save(self):
        self.assertEqual(settings_info(), {"ok": True, "configured": False, "url": ""})
        result = save_settings({"url": "https://canvas.example/", "token": "private-token"})
        self.assertTrue(result["ok"])
        self.assertNotIn("private-token", json.dumps(result))
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.path.parent.stat().st_mode & 0o777, 0o700)
        self.get.assert_called_once_with("https://canvas.example/api/v1/courses?enrollment_type=student&enrollment_state=active&per_page=100")
        self.assertEqual(settings_info(), {"ok": True, "configured": True, "url": "https://canvas.example", "courses": [], "courses_loaded": True, "selected_course_ids": [], "selection_saved": False, "days_ahead": 7})

    def test_failed_connection_preserves_credentials(self):
        save_settings({"url": "https://canvas.example", "token": "original"})
        self.get.side_effect = CanvasError("Token rejected")
        with self.assertRaises(CanvasError):
            save_settings({"url": "https://canvas.example", "token": "replacement"})
        self.assertEqual(json.loads(self.path.read_text())["token"], "original")

    def test_keep_token_only_for_same_site(self):
        save_settings({"url": "https://canvas.example", "token": "original"})
        save_settings({"url": "https://canvas.example/", "token": ""})
        self.assertEqual(json.loads(self.path.read_text())["token"], "original")
        self.get.reset_mock()
        with self.assertRaises(CanvasError):
            save_settings({"url": "https://other.example", "token": ""})
        self.get.assert_not_called()

    def test_replace_token_atomically(self):
        save_settings({"url": "https://canvas.example", "token": "original"})
        save_settings({"url": "https://canvas.example", "token": "replacement"})
        self.assertEqual(json.loads(self.path.read_text())["token"], "replacement")
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_invalid_input_never_contacts_canvas(self):
        for data in [{"url": "http://canvas.example", "token": "secret"},
                     {"url": "https://canvas.example", "token": ""},
                     {"url": "https://canvas.example", "token": "invalid\ntoken"}]:
            with self.assertRaises(CanvasError):
                save_settings(data)
        self.get.assert_not_called()
        self.assertFalse(self.path.exists())

    def test_insecure_file_is_not_exposed(self):
        save_settings({"url": "https://canvas.example", "token": "secret"})
        os.chmod(self.path, 0o644)
        with self.assertRaises(CanvasError):
            settings_info()

    def connect_courses(self):
        self.get.return_value = ([{"id": "1", "name": "Math"}, {"id": "2", "name": "Art"}], None)
        return save_settings({"url": "https://canvas.example", "token": "secret"})

    def test_connect_returns_courses_without_fetching_assignments(self):
        result = self.connect_courses()
        self.assertEqual([c["name"] for c in result["courses"]], ["Art", "Math"])
        self.assertEqual(result["selected_course_ids"], [])
        self.assertEqual(self.get.call_count, 1)
        self.assertNotIn("secret", json.dumps(result))

    def test_refresh_only_fetches_selected_courses(self):
        self.connect_courses()
        select_courses({"url": "https://canvas.example", "selected_course_ids": ["2"]})
        self.get.reset_mock()
        self.get.return_value = ([], None)
        result = read_assignments()
        self.assertEqual(result["selected_course_count"], 1)
        self.assertEqual(self.get.call_count, 1)
        self.assertIn("/courses/2/assignments?", self.get.call_args.args[0])

    def test_no_selection_does_not_fetch(self):
        self.connect_courses()
        self.get.reset_mock()
        self.assertTrue(read_assignments()["needs_setup"])
        select_courses({"url": "https://canvas.example", "selected_course_ids": []})
        self.assertEqual(read_assignments()["assignments"], [])
        self.get.assert_not_called()

    def test_unknown_course_cannot_be_saved(self):
        self.connect_courses()
        with self.assertRaises(CanvasError):
            select_courses({"url": "https://canvas.example", "selected_course_ids": ["999"]})

    def test_account_change_resets_selection(self):
        self.connect_courses()
        select_courses({"url": "https://canvas.example", "selected_course_ids": ["1"]})
        result = save_settings({"url": "https://canvas.example", "token": "different-account-token"})
        self.assertEqual(result["selected_course_ids"], [])
        self.assertFalse(result["selection_saved"])

    def test_existing_config_requires_course_selection_without_network(self):
        self.path.parent.mkdir()
        self.path.write_text(json.dumps({"url": "https://canvas.example", "token": "secret"}))
        os.chmod(self.path, 0o600)
        self.assertTrue(read_assignments()["needs_setup"])
        self.get.assert_not_called()

    def test_days_saved_and_used_on_refresh(self):
        self.connect_courses()
        select_courses({"url": "https://canvas.example", "selected_course_ids": ["1"], "days_ahead": 14})
        self.assertEqual(settings_info()["days_ahead"], 14)
        self.get.return_value = ([], None)
        self.assertEqual(read_assignments()["days_ahead"], 14)
        self.assertEqual(save_settings({"url": "https://canvas.example", "token": ""})["days_ahead"], 14)

    def test_invalid_days_preserve_settings(self):
        self.connect_courses()
        original = self.path.read_text()
        with self.assertRaises(CanvasError):
            select_courses({"url": "https://canvas.example", "selected_course_ids": ["1"], "days_ahead": 100})
        self.assertEqual(self.path.read_text(), original)

    def test_malformed_configuration_returns_controlled_error(self):
        self.connect_courses()
        original = json.loads(self.path.read_text())
        for config in [[], dict(original, courses=[None]), dict(original, courses=[{"id": "1", "name": None}]),
                       dict(original, selected_course_ids=[{}]), dict(original, selection_saved="yes")]:
            self.path.write_text(json.dumps(config))
            with self.subTest(config=config), self.assertRaises(CanvasError):
                settings_info()

    def test_malformed_connection_input_preserves_settings(self):
        self.connect_courses()
        original = self.path.read_text()
        self.get.reset_mock()
        for data in [[], None, {"url": None}, {"url": "https://canvas.example", "token": 42}]:
            with self.subTest(data=data), self.assertRaises(CanvasError):
                save_settings(data)
        self.get.assert_not_called()
        self.assertEqual(self.path.read_text(), original)

    def test_invalid_course_response_preserves_credentials(self):
        self.connect_courses()
        original = self.path.read_text()
        self.get.return_value = ([{"id": "1", "name": None}], None)
        with self.assertRaises(CanvasError):
            save_settings({"url": "https://canvas.example", "token": "replacement"})
        self.assertEqual(self.path.read_text(), original)


if __name__ == "__main__":
    unittest.main()
