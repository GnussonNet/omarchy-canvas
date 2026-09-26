# Validation

Validated on the development machine, 2026-09-26:

- `python3 -m unittest discover -s tests -v`: 14 tests passed, including private
  credential storage, token retention, replacement, and failed connection checks.
- `omarchy plugin validate .`: passed.
- Qt 6 `qmllint`: imports resolved using a temporary import root with `qs`
  pointing to `/usr/share/omarchy/shell`. No syntax or unresolved-import errors.
  Remaining warnings concern runtime QObject properties and Quickshell's
  `QProcess::ExitStatus` type metadata.

Not yet verified: live Canvas responses, on-desktop rendering, onboarding/settings interactions,
browser launch, and install/remove lifecycle. These need local installation and
Canvas credentials. No real Canvas API request was made during development.
