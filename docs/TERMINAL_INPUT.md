# Terminal input and touch scrolling

## Diagnosis

The app has three input layers: UIKit gestures, the SwiftTerm terminal emulator, and the remote program reached through SSH. SSH transports bytes. It does not define a scroll command. Output escape sequences tell the emulator which screen buffer and mouse protocol the remote program uses.

The original app set `allowMouseReporting` to false. In the pinned SwiftTerm iOS implementation, a mouse pan is a button drag, not a wheel event. A selection pan can send cursor keys when mouse reporting is disabled. Enabling that flag alone therefore does not provide the required touch-scroll behavior. The first scroll change supplied wheel input separately but left ordinary taps blocked. The pane-tap fix removes that global restriction and follows the remote mouse mode.

Normal terminal history belongs to the local scroll view. A full-screen program usually uses the alternate buffer. tmux owns its pane history on the server; local scrollback cannot recover that history from screen redraws. These cases require different input routes.

## Input contract

| Context | Vertical drag behavior |
| --- | --- |
| Text selection is active | Keep selection-handle behavior; do not send remote scrolling input |
| Remote program requests mouse input | Send wheel events at the touch position, using the negotiated terminal mouse encoding |
| tmux tab without mouse reporting | Query the active pane of that tab's exact session. Use tmux copy-mode commands for history; use cursor input only for a pane in an alternate screen |
| Alternate screen outside tmux | Follow the terminal's Alternate Scroll mode; send cursor input only when that mode is enabled |
| Normal shell without mouse reporting | Scroll local output with the native scroll view; send no keys to the shell |

In an app-selected tmux tab, a horizontal drag moves that client's viewport with `refresh-client -L/-R`. Lock the axis when the gesture starts. Do not send horizontal arrow keys or mouse-wheel events to the pane. Other tabs retain their existing horizontal gesture behavior. Keep tap-to-type and long-press selection. Preserve Chinese composition, one-shot modifiers, bracketed paste, and the keyboard hide/show control. A drag must not submit a command, navigate shell command history, or change global tmux options.

When the remote program requests mouse input, a tap sends its cell coordinates as a press and release. The tap keeps a hidden keyboard hidden. With mouse mode off, use native tap-to-type. Long press opens the local selection menu; active local selection suppresses remote mouse input. Follow live mouse-mode changes instead of reading or changing the server's configuration file.

Remote scroll requests must be bounded and serialized. Drop pending input when a tab closes, switches away, or loses its connection. Never replay scroll input after reconnection. Remote errors must leave the terminal available for keyboard input.

## Wide tmux windows

Keep the existing tmux window-size policy. Horizontal panning changes only the visible portion of the window for the app's client. It does not resize the window, change the desktop client's viewport, or detach other clients. Drag left to reveal columns on the right. Use **tmux controls → Follow tmux cursor** to restore automatic cursor tracking. tmux resets the viewport when its current window changes.

Before starting tmux, the remote shell reports its PTY path in a one-time OSC marker with a random connection token. The SSH reader removes this marker across arbitrary read boundaries. The shell then uses `exec`, so tmux uses that same PTY. All viewport commands target this exact client, including when several devices use the same session. A missing identity produces a scrolling error rather than guessing a client. Plain-shell connections do not use this handshake.

Coalesce movement for 40 ms and serialize remote requests. Clear pending movement on background, tab departure, disconnect, terminal input, or entry into pane resize mode. An already executing SSH request can finish; never replay queued movement on reconnect. Selection and explicit pane resize mode take priority over horizontal panning. Network round trips still affect redraw latency.

Existing pane-border snapping rejects windows whose geometry does not match the local grid. This feature does not add pane-border resizing for oversized windows. Normal tmux mouse events retain client coordinates; tmux translates them to its viewport. Manually starting tmux inside a plain-shell tab does not enable this app-specific route.

Reference: [tmux refresh-client](https://man.openbsd.org/tmux.1#refresh-client).

## Validation history

Check local history without transmitted bytes, mouse-wheel encoding and coordinates, application cursor mode, disabled alternate scrolling, text selection, and tmux routing. Check isolated tmux sessions with mouse on and off, a custom prefix, and independent panes. Confirm that closing or switching a tab clears pending scroll work. Use physical-device lifecycle tests and a real SSH/SSM check in addition to Simulator tests.

On 2026-09-11, all 36 core tests passed. All 20 hosted input, tab, and scroll tests passed in Simulator and on the physical iPhone. A live AWS SSM check passed with tmux 3.4 on an isolated socket: mouse-off history, mouse-on wheel input, return to the prompt, cancellation before input, separate tab output, and retained sessions after closing and reconnecting. The test removed only its isolated tmux server.

These hosted checks test input routing and native view state. They do not replace a manual finger-gesture check. The Mac UI was unavailable for the Simulator gesture inspection. The signed update is installed on both devices and launched on iPhone. The physical iPad test and launch are blocked while the device is locked. Manually started nested tmux sessions in a plain-shell tab are not identified by this routing; application mouse reporting can still handle their wheel input.

Pane-tap validation on 2026-09-12: all 23 automated regressions passed in Simulator and on the physical iPhone (the separate interactive check skips by default), including mouse enable/disable transitions, SGR coordinates, X10 press-only input, hidden keyboard focus, and local selection during output. A computer-use tap passed through the real UIKit gesture recognizers and produced press/release events without showing the keyboard. An isolated live tmux test over AWS SSM confirmed that clicking the second pane made it active; wheel scrolling and retained sessions also passed. The computer-use drag attempt produced clicks instead of a continuous pan and did not complete the scroll check; it is not recorded as a gesture pass.

## Sources

- [SwiftTerm iOS terminal implementation](https://github.com/migueldeicaza/SwiftTerm/blob/main/Sources/SwiftTerm/iOS/iOSTerminalView.swift). The local pinned checkout is the implementation authority for this app.
- [Xterm control sequences](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html): mouse-wheel encoding and Alternate Scroll mode.
- [tmux manual](https://man.openbsd.org/tmux): pane history, copy mode, mouse events, and targeted commands.

## Local text composition

SwiftTerm stores marked text but does not draw it. The app displays a temporary native label near the cursor. The label stays within the visible terminal area above the docked keyboard. It does not change the terminal grid or output buffer.

A forwarding input delegate observes marked-text changes and retains the native delegate callbacks. Candidate commit uses SwiftTerm's input path. Backspace edits marked text locally, including selections and complete Unicode characters. It must not send Backspace for text that was never sent to the server. Leaving the terminal clears uncommitted text.

Hosted tests cover the visible preview with the software keyboard, local editing, candidate text commit, cancellation, keyboard dismissal, Unicode deletion, and native delegate forwarding. These tests call the text-input APIs directly. They do not replace a manual Pinyin candidate-selection check.

Validation on 2026-09-18: All 24 input, tab, and composition tests pass on iPhone Simulator and physical iPhone 17 Pro Max. Four selected iPad Simulator checks pass. The preview render was inspected. The signed combined build is installed on iPhone. Physical iPad deployment remains deferred because the device is unavailable.

## Two-finger pane-border drag

One finger scrolls. Two fingers send a left-button drag at their midpoint. Start with that midpoint on the border. This works in horizontal and vertical directions when the server requests button-motion or all-motion mouse reporting. tmux must have mouse mode and a border-drag binding. The app does not enable mouse mode or replace server bindings.

The initial press uses the pan origin, before UIKit's recognition threshold. Motion uses the negotiated terminal encoding. Release occurs on completion, cancellation, local selection, backgrounding, tab changes, or view removal. Connection loss drops local drag state without replay. Active drags suppress wheel input. No terminal resize or keyboard focus change is required.

Run `python3 Scripts/check-pane-drag.py` with tmux installed to test both border directions and release behavior on an isolated local server. The check removes only its own server. Hosted tests cover encoded input, mode transitions, local selection, coordinate bounds, and cancellation. Manual two-finger gesture validation remains separate.

Implementation constraint: SwiftTerm can call mouseModeChanged during initialization. Do not read getTerminal from that callback before initialization has completed. Drag cleanup must first check that a drag exists.

Validation on 2026-09-18: 35 automated tests pass on both iPhone Simulator and physical iPhone 17 Pro Max; the opt-in interactive tap test is skipped. All 11 automated gesture tests pass on iPad Simulator. The isolated tmux test confirms horizontal and vertical resizing and release behavior. The final signed build is installed on iPhone. Actual two-finger border targeting and physical iPad deployment remain open.

## Explicit pane resize mode

Double-tap the terminal to enter or leave resize mode. In this mode, drag a border with one finger. The toolbar shows Done resizing. Taps and scroll input stay local while the mode is active. Outside the mode, one finger scrolls and two fingers can drag. The double-tap recognizer takes priority over terminal taps, so the mode toggle does not send a remote click.

The mode requires remote mouse-motion reporting. Selection, window removal, view departure, background entry, and disconnect end the mode. Release a held mouse button before normal cleanup, but do not send a release after connection loss. Mode changes do not resize the terminal grid.

The user confirmed all prior non-iPad manual checks on 2026-09-18. Physical iPad deployment remains deferred. The new resize-mode interaction needs its own validation.

Resize-mode validation: 40 automated tests pass on both iPhone Simulator and physical iPhone; 13 automated gesture tests pass on iPad Simulator. Each run skips the opt-in interactive test. The signed build is installed and launched on iPhone. Manual double-tap recognition and border targeting remain separate checks.

### Selection conflict correction

User testing found both local selection and remote tmux selection in resize mode. Suspend enabled native selection taps, long presses, and competing pans during the mode, then restore their previous state. Keep the resize drag and mode toggle enabled.

For each resize-mode drag, query the selected tmux session on the connected server. Use the current pane rectangles to choose the nearest internal border. Start the mouse press at that border and add the finger displacement to subsequent motion. Account for a top status bar and reject zoomed, unsplit, or mismatched-size layouts. This requires a tmux session selected through the app. Two-finger dragging outside resize mode retains its original mouse behavior.

A missing layout must not fall back to a press over text. Cancelling or ending a drag cancels the pending query result, so it cannot send delayed input. Query errors appear in Session and terminal tools. Manual selection-conflict validation remains separate from the automated checks.

Correction validation: 43 automated tests pass on iPhone Simulator and physical iPhone; 16 gesture tests pass on iPad Simulator. The interactive test is skipped. The signed correction is installed and launched on iPhone. User confirmation of the corrected physical gesture remains pending.

### Continuous resize and persistent mode

Mouse-reporting negotiation must not exit the user-selected resize mode. Local tmux output confirms that redraws can disable and re-enable reporting. Preserve the held drag across these transitions; pause motion output while reporting is disabled and continue with the next movement once enabled. Finger release ends only the drag. The mode remains active for another drag until explicit exit or lifecycle cleanup. Double-tap exit also works while reporting is disabled.

The regression reproduces the previous mode exit and missing motion with the observed tmux sequences, including a split network read. The local tmux check verifies two intermediate border positions before release, horizontally and vertically.

Resize-mode entry requires a live tmux attachment selected in the app. Remote mouse reporting alone does not enable it in an ordinary terminal. Revoking this availability ends resize mode.

Validation: The old code fails the redraw regression; the corrected code passes. All 45 automated iPhone checks and 18 iPad Simulator gesture checks pass, with the opt-in interactive test skipped. The signed build is installed and launched on iPhone. Physical gesture confirmation on the user's remote session remains pending.

### Resize responsiveness

Read the layout when resize mode opens and refresh it after a drag ends. The toolbar shows preparation while the read is pending. A prepared drag reuses that result without another SSH query. Exit and connection cleanup discard it; missing data never falls back to pressing text.

Send motion only when the target terminal cell changes. Preserve the first motion and final release. Pane dimensions use terminal cells, so resizing changes in whole columns or rows. Hold the keyboard viewport translation while a drag is active or waiting for its border; restore cursor-following after release. This prevents server cursor redraws from changing the touch coordinate mapping. Network latency still affects when a remote redraw arrives.

Responsiveness validation: 48 automated checks pass on iPhone Simulator and physical iPhone; 21 selected checks pass on iPad Simulator, with one interactive-test skip in each run. Tests cover prepared layout reuse and invalidation, 120 sub-cell movements without duplicate mouse events, final release order, and fixed viewport translation during a drag. The signed app is installed and launched on iPhone. Real-network latency and physical gesture feel have not been measured.

### One-finger scroll ownership

Do not make a one-finger pan wait for the two-finger mouse-drag recognizer to fail. That recognizer can remain possible until finger release. Limit both native history scrolling and custom remote scrolling to one finger. Outside resize mode, two fingers belong to mouse dragging. Inside resize mode, disable the competing scrolling recognizers as before. Retain native scrolling as the fallback when the remote-scroll recognizer rejects local-history input.

## Toolbar-free terminal

The detail view hides its navigation bar. A floating side control opens Hosts and sessions or toggles the keyboard. The sidebar contains the current host's open tabs, server-session discovery and creation, Disconnect, terminal preferences, and tmux controls. Server-session navigation stays inside the sidebar. The existing prominent-detail split view overlays the terminal without changing its grid. Pane resize mode has a temporary floating exit button.

## Floating keys

Use a native eight-key overlay for Esc, Tab, Ctrl, Shift and arrows. A native More menu contains Home, End, Page Up/Down, Alt/Meta, New line (Ctrl+J), Ctrl+C, and Paste. Keep the 44-point drag handle separate from the 44-point key buttons. Dragging updates position directly and sends no input. Store normalized position on the device; constrain placement to safe bounds and avoid the keyboard. The controls are siblings of the terminal, so touches outside them retain terminal scrolling and resizing.

Shift and Ctrl can be armed for one key or held across presses. Alt/Meta is a one-shot menu toggle. Modifiers combine and apply to palette keys or the next ASCII character from the system keyboard. Use SwiftTerm’s existing control/meta text encoding; prefix ESC for combined Ctrl+Alt in legacy mode. Shift+Return and New line send Ctrl+J rather than Return. Starting IME composition clears shortcut modifiers, and multi-character/Unicode commits remain text. Paste uses the existing local clipboard and multiline-paste confirmation path, never Ctrl+V. Repeated arrow input begins after 400 ms and repeats every 75 ms. Stop on touch release, cancellation, hide, background, tab departure, or disconnect. Clear all modifiers on those lifecycle transitions. Esc, Tab, New line, and Ctrl+C do not repeat. Native button actions do not summon the software keyboard.

Use normal or application cursor sequences as negotiated. Shift arrows use CSI 1;2 plus the direction letter. Respect enhanced keyboard disambiguation and event reporting for applications that request them, including Esc press/release. The isolated `Scripts/check-floating-keys.py` verifies 20 plain and modified key sequences against tmux key bindings, including Ctrl+J. This verifies protocol delivery, not actions within the user's live Codex session.

The sidebar toggle sets the current tab's visibility and the device default for new tabs. Existing tabs keep their values. Default to visible when no preference exists. Palette visibility and movement do not change terminal layout constraints.

Initial six-key validation: 52 automated checks pass on Simulator and both physical devices, with the opt-in interactive test skipped. Native-button tests verify a tap sends Esc once, Shift latch and held combinations, cursor modes, enhanced Esc events, repeated-arrow cancellation, 44-point targets, visibility, and stable terminal rows/columns. Geometry tests and a software-keyboard check verify safe positioning. Rendered screenshots were inspected. Isolated tmux accepts all nine arrow, Shift-arrow, and Esc cases. Both devices have the signed build and pass normal launch/process readback. Live Codex behavior and physical drag comfort remain user checks.
