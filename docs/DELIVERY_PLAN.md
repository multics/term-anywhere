# Active delivery plan

Updated: 2026-09-11. This file tracks the user's active requests. Each feature follows the project rule: test, deploy, then commit. One commit contains one feature.

## Delivered

- iPhone and iPad SSH terminal with direct SSH and AWS SSM transport.
- Keyboard controls and server-specific tmux shortcut detection on connection and reconnection.
- iCloud host and preference sync.
- Public GitHub repository with secret scanning and push protection; signed development deployments.
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
| 9 | iPhone landscape | Request landscape after connection; leave iPad orientation under user control | Implemented and installed on both devices. Physical iPhone rotation and disconnect pass after the terminal wrapper observes session changes. Physical iPad confirms no forced rotation. The final navigation-transition refinement passes all 10 Simulator terminal tests and the physical iPhone lifecycle test in the appearance validation run |
| 10 | Appearance | Light, Dark, and System modes for app and terminal; default to System; save and sync the preference | Delivered: 33 core tests and 12 active Mac tests pass. Appearance and terminal lifecycle tests pass on both physical devices. The native Mac theme picker and light/dark terminal renders were inspected. Dark and restored System preferences transferred from Mac to iPad. Signed apps installed and launched on all three devices |
| 11 | Google Cloud managed SSH access | Deferred by the user: no GCP host is available | Removed from the active queue on 2026-09-11 |
| 12 | Azure managed SSH access | Deferred by the user on 2026-09-11 | Removed from the active queue; the unshipped draft is outside Git |
| 13 | Visible keyboard dismissal | A terminal toolbar button hides the keyboard and brings it back on iPhone and iPad | Delivered: all 12 Simulator terminal tests pass. The hide/restore lifecycle test passes on both physical devices and retains the session and output. The iPad render with the keyboard hidden was inspected. The signed update is installed and launched on iPhone and iPad |

| 14 | Multiple session tabs per host | Keep independent tabs; show an on-demand panel; preserve keyboard state; close local tabs without deleting remote sessions | Delivered: 16 input and tab tests pass in Simulator and on iPad; all 5 tab tests pass on iPhone. Live SSM checks confirm independent output and remote session retention after closing a tab. Signed update installed and launched on both devices |
| 15 | Terminal touch scrolling | Diagnose gesture routing, scrollback, full-screen applications, and tmux copy mode before fixing the input path | Implemented and installed on both devices. All 36 core tests and 20 hosted tests in Simulator and on iPhone pass. Live SSM checks cover mouse-off history, mouse-on wheel input, return to the prompt, and cancelled input. iPhone launch verified. iPad tests and launch are blocked by its lock; manual finger-gesture verification remains open. See TERMINAL_INPUT.md |
| 16 | Respect tmux mouse mode for pane taps | Forward taps using the remote mouse mode; select panes with the keyboard hidden; retain local long-press selection | 23 automated regressions passed in Simulator and on iPhone; the separate interactive tap check passed in Simulator. A live SSM test confirmed selection of the touched tmux pane. Signed fix installed and launched on iPhone. iPad deployment and checks remain pending because the device is unreachable |

| 17 | Frequent tmux controls | Dedicated toolbar menu with Zoom pane and Next/Previous window first; the keyboard More menu uses the same order and detected bindings | Implemented: 36 core tests and 24 active hosted tests pass on iPhone, iPhone Simulator, and iPad Simulator; one interactive tap test is opt-in and skipped in each run. The iPhone landscape and iPad portrait toolbar renders were inspected. Signed update installed and launched on iPhone. Physical iPad deployment and checks remain pending because developer tools cannot find the device |

| 18 | Connection overlay | Center status and recovery controls over a full-size terminal; use a transparent tint so previous output remains readable | Implemented, installed, and launched on iPhone. The transparent version passes 25 active Simulator input, tab, and gesture tests; the opt-in interactive tap test is skipped. Separate Light and Dark overlay tests and the iPad Simulator geometry check pass. Rendered previews were inspected. The preceding overlay revision also passed 25 active iPhone tests after fixture orientation cleanup. Physical iPad deployment stays deferred because the user does not have the device available |

Repository recreation is complete. The new public repository contains only the cleaned history. Secret scanning and push protection are enabled. Anonymous checks of the old proposal page, raw-file URL, and API URL return HTTP 404. Broader app validation limits remain in README.md.

Network interruptions must keep the terminal screen for recovery. Explicit disconnect closes the local terminal. Removing or duplicating a host must not remove or copy its credential values. Existing credentials are referenced by name.

Existing work has been preserved while it is divided into separate feature checkpoints. Build success alone is not deployment evidence.

## Audit findings

At the start of the audit, the installed Mac app was still the terminal version from the prior delivery. The configuration companion has now been tested, installed, and inspected. Earlier drafts for the other changes are preserved in a Git stash and a local checkpoint. They are not part of the installed build.

The requirements and design previously contained two stale rules: a Mac terminal and retention of the screen after every disconnect. The current requirements remove the Mac terminal and distinguish explicit disconnect from network loss. The session chooser is in scope; a full tmux window and pane manager remains out of scope.

The external-terminal request adds a Mac Connect action. It replaces the earlier restriction on all Mac connection controls, while retaining the restriction on an embedded Mac terminal. Terminal selection is local because installed applications differ between Macs.

## Current device availability

As of 2026-09-12, the iPhone is reachable. The transparent connection overlay is installed and launched. Simulator checks cover the final appearance and unchanged terminal dimensions. The physical iPad is not available to the user, so its deployment stays deferred without further unlock requests. Its last installed version includes touch scrolling. Pane-tap, tmux-controls, and connection-overlay deployment and device checks remain open, along with manual finger scrolling.

## Configuration cleanup

Cleared the exact tmux session value mobile from 15 saved host records on Mac. Other named sessions remain. Updated record revisions and reopened the signed app to reconcile iCloud. Readback from both mobile app containers confirms 15 empty session values, no mobile values, and the other named session retained. Private host data and the backup stay outside Git.

## iCloud callback fix

A Mac runtime sample identified a deadlock between the main thread and Apple's KVS callback queue. Cloud notification handling now moves to MainActor. The background-notification regression passes on Mac and Simulator; all 12 active Mac tests pass. The signed fix is installed on all three devices and the Mac app responds normally.

## Public repository credential check

On 2026-09-11, scanned the 81 tracked files and all 214 distinct file versions reachable from local Git refs. The refs included 17 published commits and two local stash commits. Gitleaks 8.30.1 found no secrets. Credential-like test literals were synthetic data or a published AWS signing test vector. Commit messages also passed. GitHub had no pull-request refs, releases, Actions runs, or Actions artifacts.

Added ignore rules for credential files, signing files, and private fixtures. The exclusion checks pass. GitHub visibility is now public; secret scanning and push protection are enabled. The initial GitHub secret-alert query returned no alerts. See [SECRET_AUDIT.md](SECRET_AUDIT.md) for scope and limits. This task changes repository settings and documentation only; no app build or device deployment is required.

## Local proposal privacy

The proposal contains private environment details and must stay local. It is now untracked and ignored regardless of filename letter case. Links from public documents are removed. The local file is unchanged. This change does not affect app code or installed builds.

The earlier credential audit checked for secrets; it did not establish that the documents were suitable for public release. With user approval, published rewritten history using an explicit force-with-lease check. A fresh GitHub clone confirms that the proposal is absent from all 19 commits. Gitleaks reports no findings. The local main branch uses the cleaned history. A recovery bundle and the existing stash remain local. Do not publish old recovery refs or merge old history.

The user authorized deletion and recreation after an old commit URL remained accessible. Deleted the original GitHub repository and created a new public repository with the same name. Restored only the 19 cleaned commits on main. A fresh clone confirms that the proposal is absent from every commit; Gitleaks reports no findings. Anonymous checks of the old proposal page, raw-file URL, and API URL all return HTTP 404. The repository ID changed, confirming recreation. Secret scanning and push protection are enabled. The local proposal is unchanged and ignored. Existing app work remains local. The support request was not sent.

## Stable terminal layout and fixed iPhone orientation (2026-09-18)

- Feature 19: Keep terminal rows and columns unchanged when the keyboard or Hosts sidebar opens. Use an overlaid native sidebar. Keep a full-size terminal behind the keyboard and move its viewport only when the cursor needs space. Hide the keyboard to see the full screen. Implemented. All 20 input and tab tests pass on iPhone Simulator. Both keyboard and sidebar tests pass on iPad Simulator. The keyboard test checks software-keyboard presence, stable rows and columns, output retention, and cursor visibility. The signed device build passes. The final signed app is installed and launched on iPhone 17 Pro Max. The 20-test physical run passed 19 tests; the light overlay test was interrupted by a portrait rotation. A focused rerun of the overlay, keyboard, and sidebar tests passed all three. Physical iPad deployment remains deferred because the device is unavailable.
- Feature 20: Fix the iPhone app to landscape right, including Hosts and terminal screens. Do not rotate when the phone moves. Keep iPad orientation under user control. Implemented with a single supported iPhone orientation in the app manifest and project generator settings. Removed session-specific orientation requests and restoration. All 21 input, tab, and orientation tests pass on both iPhone Simulator and physical iPhone 17 Pro Max. The OS rejects portrait and opposite-landscape requests. All three iPad Simulator checks pass, including support for all four orientations. The signed app is installed and launched on iPhone. Physical iPad deployment remains deferred.
- Preserve the earlier deferred physical iPad checks. The iPad is still unavailable on 2026-09-18.

- Feature 21: Remove the unused keyboard shortcut row. Keep the existing toolbar menus for occasional tmux and terminal controls. Pending implementation.
- Feature 22: Show uncommitted Pinyin locally during composition. Send only committed text to the server. Check editing, candidate commit, cancellation, and keyboard dismissal. Pending feature 21.
