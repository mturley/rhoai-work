---
name: open-odh
description: Open the odh-dashboard repo in a new VS Code window with an independent Claude Code session.
---

Open the odh-dashboard repo in a new editor window, unsetting the `CLAUDECODE` environment variable so the new window gets its own independent Claude Code session instead of inheriting this one.

Detect the editor (check Cursor before VS Code, since Cursor is a VS Code fork and may also set `VSCODE_*` variables):

1. **Cursor**: `CURSOR_CHANNEL` is set, or `__CFBundleIdentifier` contains "cursor"
   - `env -u CLAUDECODE cursor --new-window /Users/mturley/git/rhoai-work/opendatahub-io/odh-dashboard`
2. **VS Code**: `VSCODE_PID` is set, or `TERM_PROGRAM` is "vscode"
   - `env -u CLAUDECODE code --new-window /Users/mturley/git/rhoai-work/opendatahub-io/odh-dashboard`
3. **Neither detected**: Ask the user which editor to use.

Tell the user the window has been opened.
