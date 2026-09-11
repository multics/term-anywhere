# Terminal input and touch scrolling

## Diagnosis

The app has three input layers: UIKit gestures, the SwiftTerm terminal emulator, and the remote program reached through SSH. SSH transports bytes. It does not define a scroll command. Output escape sequences tell the emulator which screen buffer and mouse protocol the remote program uses.

The current app sets `allowMouseReporting` to false. In the pinned SwiftTerm iOS implementation, a mouse pan is a button drag, not a wheel event. A selection pan can send cursor keys when mouse reporting is disabled. Enabling that flag alone therefore does not provide the required touch-scroll behavior.

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

Remote scroll requests must be bounded and serialized. Drop pending input when a tab closes, switches away, or loses its connection. Never replay scroll input after reconnection. Remote errors must leave the terminal available for keyboard input.

## Validation

Check local history without transmitted bytes, mouse-wheel encoding and coordinates, application cursor mode, disabled alternate scrolling, text selection, and tmux routing. Check isolated tmux sessions with mouse on and off, a custom prefix, and independent panes. Confirm that closing or switching a tab clears pending scroll work. Use physical-device lifecycle tests and a real SSH/SSM check in addition to Simulator tests.

On 2026-09-11, all 36 core tests passed. All 20 hosted input, tab, and scroll tests passed in Simulator and on the physical iPhone. A live AWS SSM check passed with tmux 3.4 on an isolated socket: mouse-off history, mouse-on wheel input, return to the prompt, cancellation before input, separate tab output, and retained sessions after closing and reconnecting. The test removed only its isolated tmux server.

These hosted checks test input routing and native view state. They do not replace a manual finger-gesture check. The Mac UI was unavailable for the Simulator gesture inspection. The signed update is installed on both devices and launched on iPhone. The physical iPad test and launch are blocked while the device is locked. Manually started nested tmux sessions in a plain-shell tab are not identified by this routing; application mouse reporting can still handle their wheel input.

## Sources

- [SwiftTerm iOS terminal implementation](https://github.com/migueldeicaza/SwiftTerm/blob/main/Sources/SwiftTerm/iOS/iOSTerminalView.swift). The local pinned checkout is the implementation authority for this app.
- [Xterm control sequences](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html): mouse-wheel encoding and Alternate Scroll mode.
- [tmux manual](https://man.openbsd.org/tmux): pane history, copy mode, mouse events, and targeted commands.
