# Active delivery plan

Updated: 2026-09-11. This file tracks the user's active requests. Each feature follows the project rule: test, deploy, then commit. One commit contains one feature.

## Delivered

- iPhone and iPad SSH terminal with direct SSH and AWS SSM transport.
- Keyboard controls and server-specific tmux shortcut detection on connection and reconnection.
- iCloud host and preference sync.
- Private GitHub repository and signed development deployments.
- App icon from the requested logo subagent; source and design notes are in APP_ICON.md.
- iCloud Keychain by default for SSH keys and AWS profiles, with explicit local storage and conflict protection. Commit: `4e5ad9f`. Actual synthetic credential delivery from Mac to iPhone and iPad passed.

## Feature checkpoints

| Order | Feature | Required result | Current status |
| --- | --- | --- | --- |
| 1 | Mac configuration companion | Separate host, SSH key, and AWS profile views; import tools; compact sync status; no embedded terminal; mobile terminal preferences remain editable | Delivered: 19 core tests, 14 iOS Simulator tests, and 10 Mac Keychain tests pass. Signed app installed and running; host editor, SSH Keys, AWS Profiles, and Mobile Terminal settings inspected |
| 2 | Explicit disconnect cleanup | Return to Hosts; hide the keyboard; dismiss session tools; discard the closed terminal's UI state; do not reconnect automatically | Delivered: 17 iOS Simulator tests passed, including removal from the visible UI and no automatic recreation. Installed and launched on iPhone and iPad |
| 3 | Mac external terminal connection | Detect installed Terminal and Ghostty at launch; choose a device-local default in Settings; Connect opens the selected app using the saved host and credential settings; support hosts without a local SSH alias | Delivered: 23 core tests pass. Terminal and Ghostty execute synthetic commands. Read-only direct SSH and AWS SSM checks pass with saved Keychain credentials. Signed Mac app installed and running; Connect and both default-terminal choices inspected |
| 4 | Host row actions | Right swipe Edit; left swipe Disconnect and Remove; no trailing full-swipe action; confirmation before synced removal; context-menu equivalents; prevent removed hosts from returning after offline sync | Draft built and tested; not deployed |
| 5 | Duplicate and order hosts | Add Duplicate beside Edit; copy connection and credential references into a new ID; use an independent session choice; show session names; save and sync dragged order | Draft built and tested; not deployed |
| 6 | Discover and remember tmux sessions | Empty default instead of mobile; query the connected server; show session choices and a plain-shell option; remember each entry's choice; prompt when a saved session is missing; keep runtime shortcut detection | Draft built and tested; live selection flow not yet verified or deployed |
| 7 | Compact terminal layout | One compact navigation bar; terminal uses the remaining space; connection tools in a menu; frequent input controls near the keyboard; no buttons over terminal output | Draft built; not deployed |
| 8 | iPhone landscape | Request landscape after connection; leave iPad orientation under user control | Required; not deployed |

Network interruptions must keep the terminal screen for recovery. Explicit disconnect closes the local terminal. Removing or duplicating a host must not remove or copy its credential values. Existing credentials are referenced by name.

Existing work has been preserved while it is divided into separate feature checkpoints. Build success alone is not deployment evidence.

## Audit findings

At the start of the audit, the installed Mac app was still the terminal version from the prior delivery. The configuration companion has now been tested, installed, and inspected. Earlier drafts for the other changes are preserved in a Git stash and a local checkpoint. They are not part of the installed build.

The requirements and design previously contained two stale rules: a Mac terminal and retention of the screen after every disconnect. The current requirements remove the Mac terminal and distinguish explicit disconnect from network loss. The session chooser is in scope; a full tmux window and pane manager remains out of scope.

The external-terminal request adds a Mac Connect action. It replaces the earlier restriction on all Mac connection controls, while retaining the restriction on an embedded Mac terminal. Terminal selection is local because installed applications differ between Macs.
