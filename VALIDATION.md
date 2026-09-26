# Validation

Validated on the development machine, 2026-09-26:

- `python3 -m unittest discover -s tests -v`: 20 tests passed, including private
  credential storage, token retention, failed connection checks, selected-course
  requests, empty selections, and migration without network requests.
- `omarchy plugin validate .`: passed.
- Qt 6 `qmllint`: imports resolved using a temporary import root with `qs`
  pointing to `/usr/share/omarchy/shell`. No syntax or unresolved-import errors.
  Remaining warnings concern runtime QObject properties and Quickshell's
  `QProcess::ExitStatus` type metadata.

- Live desktop check: after restarting the shell, the installed assignments
  panel displays both the settings gear and the setup button. Reinstalling alone
  had left the previous UI loaded in the running shell.

Not yet verified: live Canvas responses, onboarding/settings interactions,
browser launch, and install/remove lifecycle. These need local installation and
Canvas credentials. No real Canvas API request was made during development.
