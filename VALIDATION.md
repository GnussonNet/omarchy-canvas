# Validation

Validated on the development machine, 2026-10-08:

- `python3 -m unittest discover -s tests -v`: 36 tests passed. Coverage includes
  private credential storage and atomic replacement, failed connection checks,
  selected-course fetching, date windows, total and partial refresh failures,
  interrupted pagination, malformed API responses and configuration, blank
  disallowed parameters, route changes and pagination loops, and large selections.
  The deadline window includes the entire final local calendar day; regression
  coverage checks the exclusive midnight boundary and a Stockholm daylight-saving
  change where the current local date differs from UTC.
  Tests use synthetic responses and never contact Canvas.
- `omarchy plugin validate .`: passed.
- Qt 6 `qmllint` on every QML file: exited successfully using a temporary import
  root with `qs` pointing to `/usr/share/omarchy/shell`. No syntax or unresolved
  import errors. Remaining warnings concern dynamic QObject properties and
  Quickshell's `QProcess::ExitStatus` type metadata.
- Isolated Quickshell smoke test on the Wayland session: the bar widget and its
  panel loaded, missing configuration produced the expected setup message, and
  Settings instantiated successfully. The test used an empty temporary config,
  kept the panel closed, and exited after three seconds. Scanner warnings concern
  the temporary import layout; no QML component creation errors occurred.
- `git diff --check`: passed.

## Remaining release checks

Live Canvas responses and the complete interactive flow remain unverified:
connecting with a valid/expired token, choosing and saving courses, keyboard
input and focus, scrolling on a small display, browser links, outside-click and
Escape dismissal, closing during connection/save, multi-monitor behavior, and
plugin install/update/disable/remove lifecycle. These require a configured
Canvas account and an interactive desktop check. Component loading and mocked
API tests do not establish these results.

No real Canvas API request was made during this review, and the installed plugin
and desktop configuration were not changed.
