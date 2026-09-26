# Omarchy Canvas

A read-only Canvas widget for the right side of the Omarchy Quattro bar.
Click **Canvas** to see assignments due from now through the next 7 × 24 hours,
sorted by deadline, across your active student enrollments. Submitted assignments
stay visible. Each row opens the assignment in your default browser.

## Requirements

- Omarchy with the Quattro shell and `omarchy plugin` commands.
- Python 3 (standard library only; no pip dependencies).
- A Canvas HTTPS site and a personal API access token with permission to read
  your courses and assignments. Your school may restrict token creation.
- A browser logged into your Canvas account to follow assignment links.

## Install

Install from [GnussonNet/omarchy-canvas](https://github.com/GnussonNet/omarchy-canvas):

```sh
omarchy plugin add https://github.com/GnussonNet/omarchy-canvas.git --enable
omarchy bar move canvas.assignments --section right
python3 ~/.config/omarchy/plugins/canvas.assignments/canvas.py --configure
```

The plugin ID is `canvas.assignments`; `omarchy.*` IDs are reserved for built-ins.
The manifest defaults to the right section of your existing bar. A top bar places
it at the top right. This plugin does not move the bar itself.

Create a token in Canvas under **Account → Settings → Approved Integrations →
New Access Token**, if your institution allows it. Use the interactive setup
above to enter the Canvas site root and hidden token. Never put a token in a
Git repository, shell command, screenshot, or issue.

Setup writes `$XDG_CONFIG_HOME/omarchy-canvas/config.json` (normally
`~/.config/omarchy-canvas/config.json`) with mode `0600`, outside the plugin
repository. Existing configuration is not overwritten. Edit that file locally
to rotate credentials; the next refresh reads it again. Its shape is:

```json
{"url": "https://school.instructure.com", "token": "YOUR_PRIVATE_TOKEN"}
```

## Behavior

- Refreshes every five minutes, when opened, and with the Refresh button.
- Shows your personalized due dates in the desktop's local timezone.
- Includes submitted work; excludes overdue work, undated assignments,
  unpublished/hidden assignments, and courses without an active student enrollment.
- Labels: Submitted, Not submitted, Graded, Excused, Resubmission requested,
  No online submission, or Unknown when Canvas supplies no submission data.
  Graded alone does not prove an online submission was made.
- A `!` indicates an error or an incomplete result. Previous results remain on
  connection failure, with the last successful refresh time visible. They may
  be stale. Partial course failures are displayed explicitly.
- Click an assignment to open it; Escape or clicking outside closes the panel.
- External-tool submission status depends on what that tool reports to Canvas.

## Read-only guarantees and privacy

The reader permits only `GET /api/v1/courses` and
`GET /api/v1/courses/:id/assignments`, with an explicit parameter allowlist.
It includes your submission status but never requests `read_status` (which can
mark submissions as read). There are no submit, upload, edit, delete, or grading
operations. Pagination is checked against the same HTTPS origin and allowed
routes; redirects are refused so credentials cannot follow them elsewhere.

The plugin never passes the token on the command line, to QML, or to the browser.
It uses no telemetry, persistent assignment cache, background service, installer
hook, privileged command, or remote build. Assignment data is held in shell
memory. Omarchy plugins run unsandboxed with your user permissions.

A personal access token may itself have write permissions; the plugin does not
use them. Where your administrator supports scoped tokens, request only the GET
scopes for the two routes above. Opening a browser page can produce normal Canvas
page-view activity; any actions you take in the browser are separate from this
read-only plugin.

## Develop and verify

```sh
python3 -m unittest discover -s tests -v
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml
python3 canvas.py
```

On Arch, `qmllint` may be at `/usr/lib/qt6/bin/qmllint`. Stock qmllint may not
resolve Quickshell's runtime `qs.*` imports; distinguish import warnings from
actual QML errors. Check the live shell log after installing:

```sh
omarchy-shell shell summon canvas.assignments '{}'
omarchy-shell shell hide canvas.assignments
qs log -p /usr/share/omarchy/shell --tail 100
```

Also check scrolling, browser links, Escape, disable/re-enable and shell restart.
Tests use synthetic responses and never contact Canvas.

## Repository and marketplace

The root manifest, README and MIT license follow the
[development guide](https://plugins.omarchy.org/develop.html) and
[publishing guide](https://plugins.omarchy.org/publish.html).
The source repository is [GnussonNet/omarchy-canvas](https://github.com/GnussonNet/omarchy-canvas).
Marketplace listing is optional; submit the repository URL through the publishing
guide's issue form if desired.
Direct Git installation does not require a marketplace listing.

## Remove

```sh
omarchy plugin remove canvas.assignments
```

Removal leaves your private configuration intact. Delete
`~/.config/omarchy-canvas/config.json` manually and revoke the token in Canvas
if you no longer need it.

API references: [Assignments](https://developerdocs.instructure.com/services/canvas/resources/assignments),
[Courses](https://developerdocs.instructure.com/services/canvas/resources/courses),
[Submissions](https://developerdocs.instructure.com/services/canvas/resources/submissions),
[Pagination](https://developerdocs.instructure.com/services/canvas/basics/file.pagination).
