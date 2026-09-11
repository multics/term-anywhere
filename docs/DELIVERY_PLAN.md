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
| 4 | Host row actions | Right swipe Edit; left swipe Disconnect and Remove; no trailing full-swipe action; confirmation before synced removal; context-menu equivalents; prevent removed hosts from returning after offline sync | Delivered: 26 core tests, iOS Simulator tests, and Mac tests pass. Signed apps installed and launched on Mac, iPhone, and iPad |
| 5 | Duplicate hosts and session labels | Add Duplicate beside Edit; copy connection and credential references into a new ID; use an independent session choice; show session names | Delivered: 27 core tests and iOS/Mac tests pass. Installed on all three devices; Mac row actions and distinct session labels inspected |
| 6 | Order hosts | Drag rows to reorder; save and sync the order | Delivered: 29 core tests and iOS/Mac tests pass. Installed on Mac and iPhone. The iPad received this change with the tmux update after its OS update; 20 active device tests pass |
| 7 | Discover and remember tmux sessions | Empty default instead of mobile; query the connected server; show session choices and a plain-shell option; remember each entry's choice; prompt when a saved session is missing; keep runtime shortcut detection | Delivered: 31 core tests pass. Selection, cancellation, and disconnect tests pass in Simulator and on iPad. Direct SSH and AWS SSM session queries, isolated tmux attachment, shortcut detection, and reconnect checks pass. Signed apps installed and launched on all three devices; Mac session labels inspected |
| 8 | Compact terminal layout | One compact navigation bar; terminal uses the remaining space; connection tools in a menu; frequent input controls near the keyboard; no buttons over terminal output | Delivered: 10 terminal input and lifecycle tests pass. The rendered connected iPhone layout was inspected. The native sidebar hides on host selection and returns after disconnect. Signed update installed and launched on iPhone and iPad |
| 9 | iPhone landscape | Request landscape after connection; leave iPad orientation under user control | Implemented and installed on both devices. Physical iPhone rotation and disconnect pass after the terminal wrapper observes session changes. Physical iPad confirms no forced rotation. The final navigation-transition refinement passes all 10 Simulator terminal tests; its additional iPhone run was deferred when the phone locked again |
| 10 | Appearance | Light, Dark, and System modes for app and terminal; default to System; save and sync the preference | New additive request; not implemented |

Network interruptions must keep the terminal screen for recovery. Explicit disconnect closes the local terminal. Removing or duplicating a host must not remove or copy its credential values. Existing credentials are referenced by name.

Existing work has been preserved while it is divided into separate feature checkpoints. Build success alone is not deployment evidence.

## Audit findings

At the start of the audit, the installed Mac app was still the terminal version from the prior delivery. The configuration companion has now been tested, installed, and inspected. Earlier drafts for the other changes are preserved in a Git stash and a local checkpoint. They are not part of the installed build.

The requirements and design previously contained two stale rules: a Mac terminal and retention of the screen after every disconnect. The current requirements remove the Mac terminal and distinguish explicit disconnect from network loss. The session chooser is in scope; a full tmux window and pane manager remains out of scope.

The external-terminal request adds a Mac Connect action. It replaces the earlier restriction on all Mac connection controls, while retaining the restriction on an embedded Mac terminal. Terminal selection is local because installed applications differ between Macs.

## Current device availability

The iPad is ready after its update to iPadOS 26.6.2. Its 20 active hosted tests pass, with two opt-in tests skipped. The current signed app is installed and launched on both mobile devices.

## Configuration cleanup

Cleared the exact tmux session value mobile from 15 saved host records on Mac. Other named sessions remain. Updated record revisions and reopened the signed app to reconcile iCloud. Readback from both mobile app containers confirms 15 empty session values, no mobile values, and the other named session retained. Private host data and the backup stay outside Git.

## iCloud callback fix

A Mac runtime sample identified a deadlock between the main thread and Apple's KVS callback queue. Cloud notification handling now moves to MainActor. The background-notification regression passes on Mac and Simulator; all 12 active Mac tests pass. The signed fix is installed on all three devices and the Mac app responds normally.
