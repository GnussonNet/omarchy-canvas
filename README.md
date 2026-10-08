# Omarchy Canvas

A read-only Canvas widget for the right side of the Omarchy Quattro bar.
Click the **󰥔 deadline counter** to see assignments due from now through the end of the day
7 calendar days ahead by default (Thursday includes all of next Thursday),
sorted by deadline, from the courses you choose. Submitted assignments
stay visible. Each row opens the assignment in your default browser.
The bar counter includes only **Not submitted** assignments; submitted titles
are struck through in the list.
The agenda groups tasks by due date, with course colors, status badges, and
urgency badges for outstanding tasks due within 24 hours. Use Up/Down to select
a task, Enter to open it, and R to refresh.

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
```

The plugin ID is `canvas.assignments`; `omarchy.*` IDs are reserved for built-ins.
The manifest defaults to the right section of your existing bar. A top bar places
it at the top right. This plugin does not move the bar itself.

Setup happens entirely in the plugin—no terminal credential command is needed.

1. Click the **󰥔 deadline counter** in the bar, then the **settings gear** at the top right.
2. Enter your Canvas site URL and access token, then click **Connect**.
3. Once connected, the settings page lists all your active student courses.
4. Choose **Days ahead** (1–90, default 7) and check the courses you want.
5. Click **Save settings** at the bottom to return to assignments.

The panel has two pages: assignments and settings. Use the gear to revisit
settings and **Back** at the top to return without saving course changes.
The connection form is collapsed once connected; use **Edit connection** to
change the site or token. The course list scrolls while Back and Save remain visible.
Connecting saves validated credentials and the course list; assignment fetching
begins only after you save your course selection. Existing configurations also
need this course-selection step after updating.

Create a token in Canvas under **Account → Settings → Approved Integrations →
New Access Token**, if your institution allows it. The token field is masked.
Never put a token in a Git repository, shell command, screenshot, or issue.

Open the **󰥔 deadline counter → settings gear** later to update the connection or look-ahead period. Leave the token blank
to keep the saved token for the same site; changing the site requires a token.
**Connect** replaces credentials only after the course list loads successfully.
It refreshes the course list and asks you to confirm your selection. Course
choices are preserved when reconnecting with the same URL and token. A new token
or site resets the selection. Assignment-access errors appear separately when
assignments load.

Setup writes `$XDG_CONFIG_HOME/omarchy-canvas/config.json` (normally
`~/.config/omarchy-canvas/config.json`) with mode `0600`, outside the plugin
repository. Settings updates replace this file atomically with the same private
permissions. Like a `.env` file, it is plain text, not encrypted: other programs
running as your user can read it. The graphical form does not change that storage
model. The file also stores course IDs, course names, and your selection.

## Update

```sh
omarchy plugin update canvas.assignments
```

Then open **⚙**, connect, and choose your courses.

If an update or reinstall still shows the old panel without the settings gear,
restart the shell to clear its loaded QML components:

```sh
omarchy restart shell
```

This briefly restarts the bar and shell UI; it does not remove Canvas credentials.

## Behavior

- Refreshes on startup, after saving course choices, every five minutes, and with
  the Refresh button. Opening the panel displays current results immediately.
- Regular refreshes fetch assignments only for selected courses; they do not
  reload the course list or visit unselected courses. Selecting no courses pauses
  assignment fetching. Opening Settings cancels an ongoing refresh.
- Requests time out after 20 seconds each, with a 60-second overall limit.
- Shows your personalized due dates in the desktop's local timezone.
- The deadline window ends at local midnight after the final day, including
  daylight-saving changes. Deadlines exactly at that midnight belong to the
  following day and are excluded.
- Includes submitted work; excludes overdue work, undated assignments,
  unpublished/hidden assignments, and courses without an active student enrollment.
- Labels: Submitted, Not submitted, Graded, Excused, Resubmission requested,
  No online submission, or Unknown when Canvas supplies no submission data.
  Graded alone does not prove an online submission was made.
- A `!` indicates an error or an incomplete result. Previous results remain on
  connection failure, with the last successful refresh time visible. They may
  be stale. If every selected course fails, previous results and their timestamp
  remain visible. Partial course failures are displayed explicitly; assignments
  from a failed or incompletely paginated course are omitted from that refresh.
- Click an assignment to open it; Escape or clicking outside closes the panel.
- External-tool submission status depends on what that tool reports to Canvas.

## Read-only guarantees and privacy

The reader permits only `GET /api/v1/courses` and
`GET /api/v1/courses/:id/assignments`, with an explicit parameter allowlist.
It includes your submission status but never requests `read_status` (which can
mark submissions as read). There are no submit, upload, edit, delete, or grading
operations. Pagination is checked against the same HTTPS origin and allowed
routes; redirects are refused so credentials cannot follow them elsewhere.

The saved token is never read back into QML. A newly entered token briefly lives
in the masked form, is sent to Python through standard input, and is cleared
from the form when sent or when the panel closes. It is never passed on the
command line or to the browser, or included in helper responses or logs.
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
qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml Settings.qml
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

Also check the settings gear, connecting, course selection, failed connection checks, text-field
keyboard input, scrolling, browser links, Escape, disable/re-enable and shell restart.
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
