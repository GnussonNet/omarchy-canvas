#!/usr/bin/env python3
"""Canvas reader. Only two allowlisted GET routes can receive credentials."""
import argparse
import getpass
import json
import os
from pathlib import Path
import re
import signal
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class CanvasError(Exception):
    pass


def config_path():
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "omarchy-canvas" / "config.json"


def origin(value):
    p = urlsplit(value)
    if p.scheme != "https" or not p.hostname or p.username or p.password or p.query or p.fragment or p.path not in ("", "/"):
        raise CanvasError("Canvas URL must be an HTTPS site root, such as https://school.instructure.com.")
    return value.rstrip("/")


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise CanvasError("Canvas redirected the API request. Check the configured site URL.")


class Client:
    def __init__(self, base, token):
        self.base = origin(base)
        self.token = token
        self.opener = build_opener(NoRedirect())

    def get(self, url):
        p = urlsplit(url)
        base = urlsplit(self.base)
        if (p.scheme, p.netloc) != (base.scheme, base.netloc) or p.fragment or not re.fullmatch(r"/api/v1/courses(?:/[0-9]+/assignments)?", p.path):
            raise CanvasError("Refused an unexpected API URL.")
        # Do not allow API options that mark submissions as read.
        query = parse_qs(p.query)
        if set(query) - {"enrollment_type", "enrollment_state", "per_page", "page", "include[]", "override_assignment_dates"} or any(v != "submission" for v in query.get("include[]", [])):
            raise CanvasError("Refused unexpected API parameters.")
        request = Request(url, headers={"Authorization": "Bearer " + self.token,
            "Accept": "application/json+canvas-string-ids"}, method="GET")
        try:
            with self.opener.open(request, timeout=20) as response:
                data = json.load(response)
                link = response.headers.get("Link", "")
        except HTTPError as e:
            messages = {401: "Canvas token was rejected or expired.", 403: "Canvas denied access. Check token permissions.", 429: "Canvas rate limit reached. Try again later."}
            raise CanvasError(messages.get(e.code, "Canvas request failed (HTTP %d)." % e.code)) from None
        except (URLError, TimeoutError):
            raise CanvasError("Unable to reach Canvas. Check your connection and site URL.") from None
        if not isinstance(data, list):
            raise CanvasError("Canvas returned an unexpected response.")
        next_url = None
        for part in link.split(","):
            match = re.search(r'<([^>]+)>;\s*rel="next"', part)
            if match:
                next_url = urljoin(url, match.group(1))
        return data, next_url

    def pages(self, path, params):
        url = self.base + path + "?" + urlencode(params)
        seen = set()
        while url:
            if url in seen or len(seen) >= 1000:
                raise CanvasError("Canvas pagination did not finish.")
            seen.add(url)
            rows, url = self.get(url)
            yield from rows


def submission_status(assignment):
    sub = assignment.get("submission")
    if not isinstance(sub, dict):
        return "Unknown"
    if sub.get("excused"):
        return "Excused"
    if sub.get("redo_request"):
        return "Resubmission requested"
    if sub.get("submitted_at") or sub.get("workflow_state") in ("submitted", "pending_review"):
        return "Submitted"
    if sub.get("workflow_state") == "graded":
        return "Graded"  # A teacher can grade work without an online submission.
    if set(assignment.get("submission_types", [])) & {"none", "on_paper"}:
        return "No online submission"
    return "Not submitted"


def collect(client, now=None):
    now = now or datetime.now(timezone.utc)
    end = now + timedelta(days=7)
    rows, warnings = [], []
    courses = client.pages("/api/v1/courses", {"enrollment_type": "student", "enrollment_state": "active", "per_page": 100})
    for course in courses:
        cid = str(course["id"])
        if not cid.isdecimal():
            raise CanvasError("Canvas returned an invalid course ID.")
        name = course.get("name", "Course " + cid)
        try:
            assignments = client.pages("/api/v1/courses/" + cid + "/assignments", {"include[]": "submission", "override_assignment_dates": "true", "per_page": 100})
            for assignment in assignments:
                due = assignment.get("due_at")
                if not due:
                    continue
                date = datetime.fromisoformat(due.replace("Z", "+00:00"))
                if not now <= date <= end or assignment.get("published") is False:
                    continue
                if (assignment.get("submission") or {}).get("assignment_visible") is False:
                    continue
                aid = str(assignment["id"])
                if not aid.isdecimal():
                    raise CanvasError("Canvas returned an invalid assignment ID.")
                rows.append({"id": cid + ":" + aid, "name": assignment["name"], "course": name,
                    "due_at": date.astimezone(timezone.utc).isoformat(), "status": submission_status(assignment),
                    "url": client.base + "/courses/" + cid + "/assignments/" + aid})
        except CanvasError as e:
            warnings.append(name + ": " + str(e))
    rows.sort(key=lambda row: (row["due_at"], row["course"], row["name"]))
    return {"ok": True, "assignments": rows, "warnings": warnings, "updated_at": now.isoformat()}


def configure():
    path = config_path()
    base = origin(input("Canvas site URL: ").strip())
    token = getpass.getpass("Canvas API token (hidden): ").strip()
    if not token or "\n" in token or "\r" in token:
        raise CanvasError("A valid token is required.")
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    # O_EXCL avoids silently replacing existing credentials or following symlinks.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as out:
        json.dump({"url": base, "token": token}, out)
        out.write("\n")
    print("Saved private configuration to " + str(path))


def read_config():
    path = config_path()
    if path.stat().st_mode & 0o077:
        raise CanvasError("Credential file must be private. Run chmod 600 on " + str(path))
    config = json.loads(path.read_text())
    config["url"] = origin(config["url"])
    validate_token(config["token"])
    return config


def validate_token(token):
    if not isinstance(token, str) or not token.strip() or any(ord(c) < 33 or ord(c) > 126 for c in token):
        raise CanvasError("Enter a valid Canvas access token without spaces or line breaks.")


def settings_info():
    try:
        config = read_config()
    except FileNotFoundError:
        return {"ok": True, "configured": False, "url": ""}
    # The saved token is never sent back to the UI.
    return {"ok": True, "configured": True, "url": config["url"]}


def save_settings(data):
    base = origin(data["url"].strip())
    token = data.get("token", "").strip()
    if not token:
        try:
            existing = read_config()
        except FileNotFoundError:
            raise CanvasError("Enter your Canvas access token.") from None
        if existing["url"] != base:
            raise CanvasError("Enter a new token when changing the Canvas site.")
        token = existing["token"]
    validate_token(token)
    # Verify access before replacing working credentials. GET only, no Canvas writes.
    client = Client(base, token)
    client.get(base + "/api/v1/courses?enrollment_type=student&per_page=1")
    path = config_path()
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".config-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as out:
            json.dump({"url": base, "token": token}, out)
            out.write("\n")
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return {"ok": True, "configured": True, "url": base}


def refresh_timeout(*_):
    raise CanvasError("Canvas refresh timed out.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--configure", action="store_true", help="save credentials locally using a hidden token prompt")
    modes.add_argument("--settings-info", action="store_true", help="return configuration status without the token")
    modes.add_argument("--save-settings", action="store_true", help="validate and save settings supplied as JSON on stdin")
    args = parser.parse_args()
    try:
        if args.configure:
            configure()
            return
        signal.signal(signal.SIGALRM, refresh_timeout)
        signal.alarm(120)
        if args.settings_info:
            result = settings_info()
        elif args.save_settings:
            result = save_settings(json.loads(sys.stdin.readline(16384)))
        else:
            config = read_config()
            result = collect(Client(config["url"], config["token"]))
        print(json.dumps(result))
    except FileNotFoundError:
        print(json.dumps({"ok": False, "needs_setup": True, "error": "Connect your Canvas account to get started."}))
    except FileExistsError:
        print("Configuration already exists; edit it locally to change credentials.", file=sys.stderr)
        sys.exit(1)
    except CanvasError as e:
        print(json.dumps({"ok": False, "error": str(e)}))
    except (ValueError, KeyError, TypeError, OSError):
        print(json.dumps({"ok": False, "error": "Could not read Canvas data or configuration. Check the configuration and retry."}))


if __name__ == "__main__":
    main()
