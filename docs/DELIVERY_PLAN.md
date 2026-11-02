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

- Feature 21: Remove the unused keyboard shortcut row. Keep the existing toolbar menus for occasional tmux and terminal controls. Implemented; removed the accessory buttons, repeat timer, and duplicate menu updates. All 20 retained input and tab checks passed on iPhone Simulator. The replacement no-accessory check also passed after its fixture was corrected to avoid treating a SwiftUI accessibility element as a UIView. The rendered tmux toolbar was inspected. The signed app is installed on iPhone 17 Pro Max. The final combined build passes all 24 hosted tests on the physical iPhone, including the no-accessory check.
- Feature 22: Show uncommitted Pinyin locally during composition. Send only committed text to the server. Check editing, candidate commit, cancellation, and keyboard dismissal. Implemented a temporary local preview at the cursor. A forwarding input delegate observes marked-text updates without changing terminal output or consuming UIKit callbacks. All 24 input, tab, and composition tests pass on iPhone Simulator. All four selected iPad Simulator checks pass. The preview render was inspected. The signed app is installed and launched on iPhone 17 Pro Max. All 24 hosted tests also pass on the physical iPhone after restarting the device test run. Manual Pinyin candidate selection remains unverified because the computer-use tool cannot access Simulator.

## Feature 23: Touch drag to resize tmux panes

- Request: Resize split-pane borders with a mouse-like touch drag.
- Decision: Use a two-finger drag to send a left-button press, motion, and release. Keep one-finger scrolling, taps, and long-press selection. This avoids guessing border positions from terminal text.
- Scope: Follow the remote mouse protocol and tmux bindings. Do not change server options. Release an active drag on cancellation or when leaving the view; never replay input after reconnect.
- Acceptance: Correct horizontal and vertical drag coordinates and event order; no wheel events during resize; no drag input when mouse motion is off or local selection is active; lifecycle cleanup; isolated tmux resize evidence; relevant tests, signed deployment, one feature commit and push.
- Status: Implemented; validation in progress. The isolated local tmux check passed horizontal resize (50 to 57 columns), vertical resize (14 to 18 rows), and release behavior. The first hosted run exposed a crash: SwiftTerm calls mouseModeChanged during initialization, before getTerminal is available. The guard now reads terminal state only when a drag is active. Stopped the crash-loop test runs, installed the corrected signed build, and launched it on iPhone; process readback confirms it is running. Validation: 35 automated tests pass on both iPhone Simulator and physical iPhone 17 Pro Max; one opt-in manual gesture test is skipped. The 11 iPad Simulator gesture tests pass, with the same opt-in skip. Logs: `.build/pane-drag-verified-simulator.log`, `.build/pane-drag-verified-iphone.log`, `.build/pane-drag-ipad.log`, and `.build/pane-drag-tmux.log`. The signed build is installed on iPhone. Manual two-finger border targeting remains unverified; next action is a user gesture check on a tmux session with mouse mode enabled. Physical iPad deployment remains blocked by device unavailability. Earlier manual Pinyin selection and deferred physical iPad checks remain open.

## Feature 24: Keep the screen awake while active

- Request: Do not auto-lock while the app is active.
- Scope: iPhone and iPad, including Hosts and terminal screens. Disable the app idle timer while its scene is active; restore normal auto-lock when inactive or in the background. Manual device locking stays available.
- Acceptance: Apply on initial appearance and each lifecycle transition; verify the native idle-timer state, build, deploy, commit, and push.
- Status: Implemented. The native idle-timer lifecycle test passes on iPhone Simulator and physical iPhone 17 Pro Max. Signed build passes and is installed on iPhone. The subsequent background-time build launched successfully with this change included. The iPad Simulator retry passed both idle-timer and background-task lifecycle tests. Physical iPad deployment and earlier manual Pinyin and pane-drag checks remain open.

## Feature 25: Preserve connections across brief screen locks

- Request: Avoid losing the network connection a few seconds after locking the phone.
- Findings: The app does not explicitly close SSH on lock. It already has SSH keepalives and foreground connection probes, but it requests no background execution time. iOS can suspend arbitrary SSH sockets; indefinite locked-screen connectivity cannot be guaranteed.
- Scope: Request one finite background grace period for an active connection; release it on foreground, disconnect, or system expiry. Do not renew it indefinitely or change server settings. Preserve existing reconnect and tmux attachment behavior; never replay typed input.
- Acceptance: Verify grace-period lifecycle and expiry cleanup, existing foreground recovery paths, relevant tests, deployment, commit, and push. Actual duration while locked remains system-controlled.
- Status: Implemented. Each active connection requests background time once per foreground/background cycle. Foreground return, explicit disconnect, connection failure, or OS expiry releases the assertion. Expiry does not force-close a healthy socket. Validation: all 26 input, tab, and lifecycle tests pass on iPhone Simulator and physical iPhone 17 Pro Max. Both selected iPad Simulator lifecycle checks pass. Signed build is installed on iPhone. Evidence: `.build/background-grace-simulator.log`, `.build/background-grace-iphone.log`, and `.build/background-grace-ipad.log`. A real SSH connection through a timed physical screen lock remains unverified; next action is a brief-lock network check on an active session. The duration is controlled by iOS, not promised by the app.

## Feature 26: Show Hosts when the workspace is empty

- Request: Open the left navigation sidebar when the app opens to an empty workspace.
- Scope: Show Hosts on launch with no selected terminal and after the last selected session closes. Continue hiding the sidebar when a host is selected.
- Acceptance: Verify initial empty-workspace navigation on iPhone and iPad, preserve host-selection behavior, deploy, commit, and push.
- Status: Implemented: request the sidebar after the native split view mounts when no terminal is selected. A fixed initial visibility value was ignored by the native prominent-detail style; the initial-launch regression reproduced that behavior. The mounted request passes the launch, selection, and disconnect test on iPhone Simulator. All three navigation and terminal-geometry checks pass on physical iPhone 17 Pro Max and iPad Simulator. Signed combined build is installed on iPhone. Final normal launch succeeded after the user unlocked the phone. Process readback and a second check after 10 seconds show the same running process (PID 3451). Evidence: `.build/final-ready-launch.log` and `.build/final-ready-processes-recheck.log`. The launch blocker is resolved. Evidence: `.build/initial-sidebar-mount-simulator.log`, `.build/initial-sidebar-iphone.log`, and `.build/initial-sidebar-ipad.log`. Physical iPad deployment remains deferred.

## Feature 27: Explicit pane resize mode

- User confirmation: All previous non-iPad checks passed, including Pinyin input, pane dragging, brief-lock connectivity, and normal launch. This is user-reported evidence; no lock duration was measured. Earlier manual-check entries are superseded by this confirmation. Physical iPad deployment and checks remain deferred.
- Request: Make border targeting easier than a two-finger drag.
- Decision: Double-tap to toggle resize mode. In this mode, drag with one finger; show a persistent Done resizing button. Keep normal scrolling outside the mode and retain two-finger dragging. Require remote mouse-motion reporting.
- Acceptance: No remote click from the mode toggle; correct press/motion/release; mode cleanup on selection, background, disconnect, and view departure; relevant tests, iPhone deployment, commit and push.
- Status: Implemented and deployed to iPhone 17 Pro Max. All 40 automated tests pass on iPhone Simulator and physical iPhone (one opt-in interactive test skipped). All 13 automated gesture tests pass on iPad Simulator (same skip). The isolated tmux test passes horizontal and vertical resize and release checks. Signed build and whitespace checks pass. Normal device launch succeeds. Evidence: `.build/resize-mode-simulator.log`, `.build/resize-mode-iphone.log`, `.build/resize-mode-ipad-simulator.log`, `.build/resize-mode-build.log`, `.build/resize-mode-install.log`, and `.build/resize-mode-launch.log`. Manual double-tap and one-finger border targeting remain open for user feedback on the installed app. Physical iPad deployment remains deferred.

## Feature 27 follow-up: Selection steals resize gestures

- Report: After entering resize mode, dragging over text still selects text instead of resizing. Reopens the manual interaction check from feature 27.
- Finding: Native selection gestures remain enabled during resize mode. Remote tmux also selects text if a mouse drag starts inside a pane rather than on its border; determine which path the user sees.
- Acceptance: Resize mode suppresses competing local selection gestures and restores their prior state on exit; resolve the current server layout and snap remote presses to borders so drags over text do not start tmux selection; retain existing cleanup and remote drag protocol; tests, device installation, commit and push.
- Decision: User confirmed that Done resizing stays visible and both local iOS selection and remote tmux selection occur. The fix now also queries the selected server session layout per drag, starts the remote press on the nearest internal border, and preserves the finger movement offset. Missing layouts and cancelled queries send no input. Physical iPad checks remain deferred.

- Validation and delivery: All 43 automated tests pass on both iPhone Simulator and physical iPhone 17 Pro Max; one opt-in interactive test is skipped per run. All 16 automated gesture tests pass on iPad Simulator, with the same skip. The isolated tmux check passes both border directions and confirms no copy-mode selection after border dragging. Signed build passes; installed and normally launched on iPhone. Evidence: `.build/resize-selection-simulator.log`, `.build/resize-selection-iphone.log`, `.build/resize-selection-ipad-simulator.log`, `.build/resize-selection-build.log`, `.build/resize-selection-install.log`, and `.build/resize-selection-launch.log`. Manual slow-drag and snapping comfort on the user's remote tmux session remain open for feedback. Physical iPad deployment remains deferred.

## Feature 27 follow-up: Continuous movement and persistent mode

- Report: Border movement does not follow the finger; finger release exits resize mode. Both remain open despite the earlier automated checks.
- Finding: The local tmux PTY emits mouse-reporting disable/enable sequences during redraw. The current mouseModeChanged handler ends the drag and exits the explicit mode at the intermediate disabled state.
- Acceptance: Preserve resize mode and an active drag across redraw negotiation; verify multiple border updates before release, another drag without re-entering the mode, explicit exit, and lifecycle cancellation. Run relevant tests, deploy to iPhone, commit and push. Physical iPad remains deferred.
- Status: The new regression failed on the previous code: the mode exited and subsequent motion bytes were missing. Implemented preservation across mode negotiation, including split network reads; no motion is sent while reporting is disabled. Explicit double-tap exit stays available while reporting is off. The local tmux check now verifies two live border positions before release in both directions. Validation in progress.

- Added requirement: Do not enable double-tap resize in an ordinary terminal. Entry is now gated by an active, app-selected tmux attachment, not mouse reporting alone. Returning to a disconnected/plain-terminal state revokes availability and ends the mode. Test ordinary terminal mouse reporting, tmux enablement, and availability removal.

- Validation and delivery: The new redraw regression fails on the previous code and passes after the correction. All 45 automated checks pass on iPhone Simulator and physical iPhone 17 Pro Max; each run skips one opt-in interactive test. All 18 automated gesture checks pass on iPad Simulator, with the same skip. The isolated tmux check verifies multiple border positions before finger release in both directions and no text selection. Signed build and whitespace checks pass. The changed app is installed and normally launched on iPhone. Evidence: `.build/resize-continuous-repro.log`, `.build/resize-continuous-simulator.log`, `.build/resize-continuous-iphone.log`, `.build/resize-continuous-ipad-simulator.log`, `.build/resize-continuous-build.log`, `.build/resize-continuous-install.log`, and `.build/resize-continuous-launch.log`. Manual confirmation of finger tracking and persistent mode on the user's server remains open; physical iPad remains deferred.

## Feature 27 follow-up: Resize latency and tracking

- User confirms resizing now works and mode persists, but dragging has about one second of startup delay and uneven tracking.
- Findings: Each drag waits for session resolution and a layout query over SSH. Motion sends repeat cells; the SSH writer drains one queued buffer per poll. Keyboard cursor-following can translate the terminal during server redraws.
- Decision: Preload layout on mode entry and refresh after release; show preparation state. Deduplicate cell-level motion and hold the keyboard viewport still during a drag. Preserve fresh server layout, cancellation, tmux-only entry, and explicit mode exit.
- Acceptance: Prepared drags need no new layout query; no repeated motion for the same cell; changing cells and final release remain ordered; stable viewport during dragging; relevant checks, iPhone deployment, commit and push. Physical iPad remains deferred.
- Status: Implemented. Layout preparation starts on mode entry and refreshes after release; a toolbar progress indicator shows pending preparation. Prepared drags reuse the result. Cell-level motion deduplication and a fixed viewport during active dragging pass targeted regressions. All 48 automated checks pass on iPhone Simulator and physical iPhone 17 Pro Max; one opt-in interactive test is skipped. All 21 selected automated iPad Simulator checks pass, with the same skip. Signed build and whitespace checks pass. Installed and normally launched on iPhone. Evidence: `.build/resize-responsive-simulator.log`, `.build/resize-responsive-iphone.log`, `.build/resize-responsive-ipad-simulator.log`, `.build/resize-responsive-build.log`, `.build/resize-responsive-install.log`, and `.build/resize-responsive-launch.log`. Actual network latency and subjective finger tracking on the user’s server remain unmeasured; next check is hands-on use of the installed build. Physical iPad deployment remains deferred.

## Feature 28: Disconnect first in the Connection menu

- Request: Put Disconnect first and remove the gray connection-status row.
- Implementation: Move the existing current-tab close/disconnect action to the first row and label it Disconnect. Remove the status text and duplicate Close tab row. Reuse the existing session cleanup behavior.
- Acceptance: Review menu order, run existing disconnect/tab checks, deploy to iPhone, commit and push. Physical iPad remains deferred; prior resize responsiveness hands-on check remains open.
- Status: Implemented. Source review confirms Disconnect is the first action and the status row is removed. All seven existing disconnect and tab checks pass on iPhone Simulator and physical iPhone 17 Pro Max. Signed build and whitespace checks pass. Installed and normally launched on iPhone. Evidence: `.build/disconnect-menu-simulator.log`, `.build/disconnect-menu-iphone.log`, `.build/disconnect-menu-build.log`, `.build/disconnect-menu-install.log`, and `.build/disconnect-menu-launch.log`. Physical iPad deployment and the prior manual resize-responsiveness check remain deferred/open respectively.

## iPad update (2026-10-25)

- Request: Update Term Anywhere on the physical iPad.
- Scope: Deploy current source revision 8232a90, including the previously deferred iPad changes; preserve installed app data.
- Acceptance: Signed build, device installation, normal launch and process readback; relevant hosted iPad checks if reachable. Keep manual resize feel separate from automated evidence.
- Status: Signed build from 8232a90 passes with Xcode 27.1 after installing the missing Metal Toolchain. The physical iPad mini (6th generation), iPadOS 27.0.1, is connected and unlocked. The update is installed over the existing app and normal launch succeeded. All 48 automated terminal, input, lifecycle, navigation, and tab checks passed on the physical iPad; the opt-in interactive test was skipped. Normal launch after testing and process readback pass. The prior physical iPad installation blocker is resolved; hands-on resize feel and the newly reported swipe-scrolling issue remain open. Additional evidence: `.build/ipad-update-tests.log`, `.build/ipad-update-final-launch.log`, `.build/ipad-update-processes.log`. Evidence: `.build/ipad-update-build.log`, `.build/ipad-update-install.log`, `.build/ipad-update-launch.log`.

## Feature 29: Restore one-finger terminal scrolling

- Request: Vertical one-finger swipes do not scroll terminal output, especially in tmux. Match mouse-wheel scrolling on Mac.
- Scope: Normal buffer, tmux mouse reporting and tmux fallback; preserve pane resize mode and text selection.
- Acceptance: Reproduce gesture ownership failure; fix one-finger scroll delivery, validate local/remote scroll behavior, deploy to iPad, commit and push.
- Finding: Both local and remote one-finger pans require the two-finger mouse pan to fail. The two-finger recognizer can remain possible during a one-finger gesture and delay scrolling until release. Remove these dependencies; limit local and remote scroll pans to one finger. Explicit resize mode already disables competing scroll pans. Existing routing tests cover local history, mouse wheel, tmux fallback, alternate screen, and selection.
- Status: Implemented and installed on the physical iPad mini. All 48 automated gesture, input, navigation, lifecycle, and tab checks pass; the opt-in interactive test was skipped. Signed test build, install, normal launch, and process readback pass. Evidence: `.build/ipad-scroll-tests.log`, `.build/ipad-scroll-install.log`, `.build/ipad-scroll-launch.log`, `.build/ipad-scroll-processes.log`. Actual one-finger swiping on the user’s tmux server remains open for hands-on confirmation; hosted tests do not synthesize finger input. The iPhone subsequently received this correction; see the iPhone 27 update record below.

## iPhone 27 update (2026-10-25)

- Request: Install the same current app on iPhone 27.
- Scope: Deploy the signed c55c232 build already verified on physical iPad, preserving app data.
- Acceptance: Successful installation, normal launch, and process readback. Manual swipe behavior remains separate.
- Status: Installed signed app revision c55c232 on iPhone 27, normally launched, and verified running process 33058. Evidence: `.build/iphone27-update-install.log`, `.build/iphone27-update-launch.log`, `.build/iphone27-update-processes.log`. Reused the unchanged build with 48 automated checks passed on physical iPad; no additional iPhone test suite was run for this deployment-only task. Hands-on swipe and resize responsiveness checks remain open on both devices.

## Proposed feature 30: Floating keys and sidebar sessions (2026-11-02)

- Request: Propose draggable floating Shift, arrow, and Esc controls, visible by default with a show/hide switch; move session selection from the top into the side to maximize terminal space. Proposal only; no app implementation requested yet.
- Current layout: TerminalScreen owns a top toolbar; TerminalWorkspaceScreen presents SessionPanel as an iPhone landscape side overlay or an iPad popover. HostListView already owns the Hosts sidebar.
- Proposal: One compact movable palette with a dedicated drag handle, Esc, one-shot Shift and an arrow cluster. Tap Shift then an arrow for a one-handed combination; hold Shift plus an arrow also works. Long-press arrows repeat; release, hide, disconnect, and session changes stop repeat and clear modifiers. Do not infer Codex from terminal text. Validate actual terminal key encoding through tmux and in Codex before claiming compatibility.
- Visibility: Default on for new preferences. Remember visibility per local session tab while open; save a device-level default and palette position. Sidebar provides a persistent Floating keys toggle even when the palette is hidden. Confine the palette to safe bounds and move it above the keyboard without resizing the terminal grid.
- Navigation: Integrate open session tabs under their host in the existing left sidebar. Show current tab and connection state, with Open session and New session actions under the host. Opening/closing the sidebar overlays the terminal without changing rows or columns. Remove the terminal top toolbar after its controls have accessible destinations. Keep a small side overlay for sidebar and keyboard access; put connection/tmux tools in the sidebar, retaining Disconnect as the first connection action. Empty workspace still opens Hosts automatically.
- Design limits: Floating controls obscure a small area but reserve no terminal rows. Use approximately 44-point touch targets. Drag handle movement must not send keys or trigger scroll/pane resizing. Do not capture terminal swipes outside the controls. Keep an explicit exit control available in pane resize mode when removing the toolbar.
- Acceptance if implemented: Stable grid during all overlay/keyboard transitions; accurate drag with safe positioning; modifier/repeat cleanup; correct arrow/Shift-arrow/Esc bytes and physical Codex/tmux behavior; session switching and recovery; deployment to iPad and iPhone 27, separate feature commits.
- Status: Approved for implementation. Deliver in two steps: (30a) toolbar-free terminal with sidebar sessions/tools and floating navigation; (30b) draggable key palette with modifier/repeat behavior. Test and deploy each to iPad and iPhone 27 before its commit. Prior manual scroll/resize checks remain open.

### Feature 30a: Toolbar-free terminal and sidebar sessions

- Implemented: Hide the detail navigation bar; keep floating sidebar/keyboard buttons and temporary pane-resize exit controls. Reuse the existing session list in the Hosts sidebar, with server-session navigation contained in that sidebar. Move connection, terminal, and tmux tools there.
- Verified: 29 simulator tests pass. Seven focused navigation/tab tests pass on each physical device. The final sidebar formatting correction passes the geometry test on Simulator and iPad; rendered Simulator sidebar inspected. The terminal begins at the safe-area top and retains rows/columns while the sidebar opens.
- Delivered: Final signed build installed and normally launched on iPad and iPhone 27. Evidence: `.build/fullscreen-simulator.log`, `.build/fullscreen-render.log`, `.build/fullscreen-ipad.log`, `.build/fullscreen-ipad-final.log`, `.build/fullscreen-iphone.log`, `.build/fullscreen-iphone-install.log`, `.build/fullscreen-ipad-launch.log`, `.build/fullscreen-iphone-launch.log`.
- Next: Implement feature 30b floating keys; preserve prior manual gesture checks.

### Feature 30b: Floating six-key palette

- Implementation: Native material palette with 44-point Esc, Shift and arrow buttons, plus a separate drag handle. Shift supports one-shot taps and held combinations. Arrows repeat after a short hold. Use negotiated normal/application cursor and enhanced keyboard sequences. Default visible; sidebar toggle stores the device default, and existing tabs retain their individual visibility. Store normalized device-local position; constrain to safe bounds and avoid the keyboard.
- Cleanup: Release stops repeat. Hide, background, tab departure, and disconnect clear Shift/repeat. Moving the palette sends no keys. Palette overlays the coordinator without changing terminal constraints.
- Status: Implemented and deployed. All 52 automated checks pass on Simulator, physical iPhone 27, and physical iPad; one opt-in gesture test is skipped in each run. The final Esc label sizing and real keyboard-boundary assertions pass a focused Simulator rerun and the full iPad run. Rendered palette and sidebar screenshots inspected. Isolated tmux recognizes all nine plain/Shift-arrow/Esc cases. Final signed app installed and normally launched on both devices, with running-process readback. Evidence: `.build/floating-keys-simulator.log`, `.build/floating-keys-iphone.log`, `.build/floating-keys-ipad.log`, `.build/floating-keys-render.log`, `.build/floating-keys-tmux.log`, `.build/floating-keys-iphone-install.log`, `.build/floating-keys-iphone-launch.log`, `.build/floating-keys-ipad-launch.log`, and the corresponding `-processes.log` files.
- Remaining manual checks: Actual drag comfort, session/sidebar interactions, and key combinations in the user’s live Codex session. Protocol tests verify key delivery but do not establish application-specific Codex actions. Earlier manual scrolling/resize responsiveness checks remain open.

## Feature 31: Native tmux horizontal panning (2026-11-02)

- Report: The iPad shows a desktop-width tmux window with columns outside the visible screen.
- Updated scope: Preserve the existing server window width. Implement horizontal scrolling only if complexity is low; otherwise defer. This replaces the initial proposal to fix the width by resizing the shared window.
- Findings: The app already requests a PTY using the local terminal grid and forwards grid changes. This does not establish the affected server's actual window-size policy. tmux provides per-client viewport movement with refresh-client -L/-R and cursor-follow restoration with -c (https://man.openbsd.org/tmux.1#refresh-client). The current app tracks session/pane identity, not its exact attached tmux client. Existing touch routing supports vertical scrolling and pane resizing.
- Assessment: Reliable horizontal dragging is moderate complexity: identify the exact mobile client, coalesce remote viewport commands, arbitrate horizontal/vertical gestures, and adjust pane hit testing for viewport offsets. Simply wrapping the terminal in a horizontal scroll view cannot recover columns omitted from the client display by tmux.
- Decision: Subsequently approved: use tmux's native viewport support. Add one-finger horizontal panning targeted to this connection's tmux client, preserve window-size policy and other clients' viewports, and retain existing vertical scroll/selection/resize routing. Do not extend border snapping to oversized windows as part of this change.
- Implemented: A private startup marker captures the terminal PTY before exec starts tmux. Filter the marker across SSH read boundaries. Horizontal gestures use refresh-client -L/-R for that exact client; coalesce requests and clear queued input on lifecycle changes. Sidebar tmux controls offers Follow tmux cursor (-c). Plain shells and nested tmux started manually retain their prior behavior.
- Verified: All 38 core tests pass. All 53 automated hosted checks pass on Simulator, physical iPad, and physical iPhone 27; the opt-in manual gesture check is skipped. The final batch-cancellation guard and selection-priority assertion pass the full 53-check iPad rerun. An isolated two-client tmux check verifies both pan directions, edge clamping, cursor-follow restoration, PTY identity, unchanged desktop viewport, and unchanged window dimensions. Evidence: `.build/tmux-pan-core-all.log`, `.build/tmux-pan-simulator.log`, `.build/tmux-pan-ipad.log`, `.build/tmux-pan-iphone.log`, `.build/tmux-pan-ipad-final.log`, `.build/tmux-pan-native.log`.
- Delivered: Final signed app installed and normally launched on both devices. Evidence: `.build/tmux-pan-{ipad,iphone}-final-install.log`, `-final-launch.log`, and `-final-processes.log`.
- Remaining: Hands-on swipe responsiveness on the user's live server is unverified. Earlier manual checks remain open. Extra floating keys (Ctrl, Tab, and optional expanded controls) remain a research proposal; no implementation was requested in that research turn.

## Feature 32: Expanded floating keyboard and cursor follow

- Request: The user approved the extra-key proposal and requested a cursor-follow button on the floating keyboard.
- Scope: Esc, Tab, Ctrl, Shift, and four arrows on the main palette. A header button runs the existing per-client tmux cursor-follow action; disable it outside an app-selected live tmux session. A native More menu contains Home, End, Page Up/Down, Alt/Meta, New line (Ctrl+J), Ctrl+C, and local Paste. Keep drag, visibility, geometry, and existing sidebar access.
- Input: Support one-shot and held modifiers; consume Ctrl/Alt with the next software-keyboard ASCII character. Preserve IME composition and Unicode input without applying shortcut modifiers. Encode negotiated terminal keys; stop repeats and clear all modifiers on lifecycle changes. Distinguish local Paste from sending Ctrl+V to the server.
- Acceptance: Key encoding and modifier lifecycle tests, native control/geometry checks, isolated tmux key checks, and deployment to iPad and iPhone 27 before commit/push. Live remote Codex bindings and subjective touch comfort remain separate checks.
- Status: Implementation and validation in progress. This approval activates the previously proposed key expansion. Prior manual checks remain open.
- Scope correction: The user then rejected horizontal panning and requested device-fitting terminal dimensions. Remove the now-unneeded floating cursor-follow action from this feature. Finish the approved keyboard expansion, then deliver the sizing change as a separate feature.
- Validation: All 56 automated hosted checks pass on Simulator and both devices, with one opt-in manual gesture test skipped. Final removal of the superseded cursor-follow button passes the full iPad and iPhone runs. The isolated tmux test accepts all 20 key sequences. Native targets, menu contents, software-keyboard Ctrl/Alt, held/one-shot modifiers, Pinyin composition, enhanced keys, lifecycle cleanup, and stable grid checks pass. Rendered light Simulator and final dark iPad palettes inspected.
- Delivery: Final signed keyboard build installed on iPad and iPhone 27. Physical tests pass, but the iPad locked before the final normal launch; normal launch is pending unlock and must not be reported as verified. Evidence: `.build/expanded-keys-simulator-final.log`, `.build/expanded-keys-ipad-final.log`, `.build/expanded-keys-iphone.log`, `.build/expanded-keys-tmux.log`, `.build/expanded-keys-{ipad,iphone}-install.log`, and corresponding launch logs. Live Codex custom bindings and physical key comfort remain manual checks.

## Feature 33: Fit tmux windows to mobile devices

- Request: Remove horizontal panning. iPhone and iPad must show terminal lines within their visible width.
- Scope: Replace native viewport panning with automatic tmux sizing suitable for attached clients. Keep the local grid matched to device bounds and stable during keyboard/sidebar overlays. Shared tmux windows have shared dimensions, so fitting smaller clients can reflow the desktop view. Remove cursor-follow controls made unnecessary by this change.
- Status: Queued immediately after feature 32; supersedes feature 31 horizontal panning. Verify multiple-client sizing, local geometry, and both physical devices before commit/push.
