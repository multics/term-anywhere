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

Keep horizontal drags out of the scroll handler. Keep tap-to-type and long-press selection. Preserve Chinese composition, one-shot modifiers, bracketed paste, and the keyboard hide/show control. A drag must not submit a command, navigate shell command history, or change global tmux options.

When the remote program requests mouse input, a tap sends its cell coordinates as a press and release. The tap keeps a hidden keyboard hidden. With mouse mode off, use native tap-to-type. Long press opens the local selection menu; active local selection suppresses remote mouse input. Follow live mouse-mode changes instead of reading or changing the server's configuration file.

Remote scroll requests must be bounded and serialized. Drop pending input when a tab closes, switches away, or loses its connection. Never replay scroll input after reconnection. Remote errors must leave the terminal available for keyboard input.

## Validation

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
