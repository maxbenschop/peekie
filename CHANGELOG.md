# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Check for Updates…** in the menu bar icon and the Peekie menu. It asks GitHub for the latest release only when you choose it.
- A confirmation before saved notes are deleted when **Save notes between launches** is turned off.

### Changed
- The menu bar icon is on by default. It is the easiest way to reach Settings and quit.
- The first launch always opens Settings, even right after a restart.
- Settings and the README mention that Alfred also uses `⌥Space`, and how to pick a different shortcut.
- Peekie no longer turns on **Launch at login** by itself. Turn it on in Settings if you want it.
- The inline maths result colour now adapts to light mode so it stays readable.
- Release builds use the hardened runtime, and the release workflow signs and notarizes when Developer ID secrets are configured.
- The About panel shows a copyright line.

### Fixed
- VoiceOver read every global shortcut button as "New note shortcut".
- `scripts/test.sh` kept the pipe open for five minutes after the tests finished when its output was captured.

## [1.1.0] - 2026-10-01

### Changed
- Checklist items are now interactive: click a box to check or uncheck it, independent of the rest of the line.

### Added
- Inline maths results are shown in their own colour, separate from the rest of the line.

## [1.0.1] - 2026-09-25

### Changed
- New app icon and menu bar icon, designed as a matching pair. There are no functional changes.
- Refreshed the README banner and social preview to match.

## [1.0.0] - 2026-09-25

First public release.

### Added
- Translucent, floating notes opened with a global shortcut, with adjustable blur and opacity.
- Quick capture of the current selection, and a shortcut to show or hide all notes.
- Light, dark and system appearance, plus support for Reduce Transparency, Increase Contrast and Reduce Motion.
- Bold, italic, underline, text colours, per-note zoom, find, and clickable links.
- Bullet lists, checklists, fenced code blocks with syntax colours, inline maths, and images.
- Temporary notes by default, reopening the last closed note, and optional saving between launches.
- Save and export as text, Markdown, RTF and RTFD, plus share and print.
- Keep on top, click-away behaviour (stay, fade or hide), an optional menu bar icon and launch at login.
- Rebindable shortcuts.

[Unreleased]: https://github.com/maxbenschop/peekie/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/maxbenschop/peekie/releases/tag/v1.1.0
[1.0.1]: https://github.com/maxbenschop/peekie/releases/tag/v1.0.1
[1.0.0]: https://github.com/maxbenschop/peekie/releases/tag/v1.0.0
