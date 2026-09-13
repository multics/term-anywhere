# Term Anywhere requirements

Status: approved scope for implementation. Minimum OS: iOS/iPadOS 26 and macOS 26. The current Mac build supports Apple Silicon.

## Purpose

Provide a personal remote terminal on iPhone and iPad. Support the user's selected hosts from the Mac SSH configuration, including direct SSH and SSH through AWS Systems Manager. The app must connect independently of the Mac after setup.

Provide a native Mac configuration app to manage hosts, SSH keys, and static AWS profiles. Give each type a sidebar destination. Provide import tools and a visible sync status. Keep mobile terminal preferences editable. Do not include an embedded terminal on Mac. Detect installed terminal applications, including Terminal and Ghostty, at launch. Let the user choose a local default in Settings. Connect opens that application with the saved host settings. A host does not need an existing local SSH alias. Use the same iCloud settings store as the phone and tablet. Use iCloud Keychain for SSH keys and AWS profiles by default. Permit an explicit device-only choice.

## Required behavior

- Support Light, Dark, and System appearance for the app UI and terminal. Default to System. Save and sync this preference through iCloud.
- Follow Apple Human Interface Guidelines. Use native controls, adaptive iPhone/iPad layouts, readable terminal text, and accessible labels.
- Support SSH keys, including encrypted private keys. Store credentials in the device Keychain. Verify server host keys before authentication.
- Azure managed access and GCP support are deferred at the user’s request. Existing direct SSH to Azure VMs remains supported.
- Support the current AIxC and NR SSM connection pattern: AWS authorization, an AWS-StartSSHSession tunnel, then SSH authentication.
- Provide a visible terminal toolbar control to hide and restore the keyboard on iPhone and iPad without closing the connection or clearing output.
- Allow multiple open terminal tabs for one host. Each tab retains its connection and output. Use an on-demand session panel, with no permanent tab strip. Closing a tab must leave its remote tmux session running.
- Provide a system keyboard with Esc, Ctrl, Tab, arrows, and a More menu. Support hardware keyboards, Chinese composition, copy/paste, and terminal resizing.
- Support vertical touch scrolling through local scrollback, negotiated application mouse-wheel input, and server-side tmux history. Preserve text selection. Do not send shell-history keys for a normal-shell scroll or change global tmux settings. Cancel queued remote scrolling on tab switch, disconnect, keyboard input, and app inactivity.
- Honor the remote application's mouse mode for taps. A tap on a tmux pane must reach tmux as a mouse press and release, including when the keyboard is hidden. Preserve long-press local text selection and send no mouse input when the remote application disables it.
- Support an optional named tmux session per saved connection. Reconnect to the same session after a connection failure. Never replay buffered input into a new connection.
- The running app must query each connected server for its effective tmux prefix and bindings after attachment and reconnection. Keep mappings separate per connection. Provide manual refresh. This is not a development-time import of tmux settings.
- Put tmux controls in a dedicated terminal toolbar menu. Put Zoom pane and Next/Previous window first in that menu and the keyboard More menu. Use detected server bindings and preserve terminal space.
- Map only understood, unambiguous tmux bindings. Keep ordinary terminal keys and a manual prefix fallback when detection fails.
- Show disconnected and connecting states in a translucent overlay across the terminal area. Center status and recovery controls. Keep terminal dimensions unchanged when the overlay appears or disappears. Keep errors, host-key verification, and passphrase entry available.
- Retain the terminal screen after a network interruption, with an accurate status. After an explicit Disconnect, return to Hosts, hide the keyboard, dismiss session tools, and discard the closed terminal UI. Do not reconnect until the user selects the host again. Do not promise continuous execution while iOS suspends the app or survival of remote processes after server restart.
- Support host editing, selected-host settings import, private-key import, AWS credential entry/import, and basic session switching.
- On iPhone and iPad, a right swipe exposes Edit and Duplicate. A left swipe exposes Disconnect for an active connection and Remove. Disable full-swipe actions on the left-swipe edge. Confirm removal. Provide context-menu actions on all platforms; omit in-app Disconnect on Mac.
- Duplicate a host with a new ID and independent tmux selection. Retain credential references. Show the session name in each host row. Save and sync the host order after a drag. Keep removal records so an offline device cannot restore a removed host.
- Start new hosts with an empty tmux session field. After SSH authentication, query that server and offer its existing sessions, a plain shell, and explicit session creation. Remember the choice per host entry. Attach directly when the saved session exists; prompt when it is missing. Permit changing or resetting the choice.
- After connection, give the terminal the available space below one compact navigation bar. Put connection tools in a menu and frequent input controls near the keyboard.
- On iPhone, request landscape after the terminal connects. Keep iPad orientation under user control.
- Sync saved host definitions and terminal preferences through iCloud. Include tmux session/socket settings, manual prefix, SSH key names, and AWS profile names. Keep local copies for offline use.
- Sync imported SSH private keys and AWS profiles through iCloud Keychain by default. Migrate existing local credentials unless the user has explicitly selected device-only storage. This replaces the earlier local-only and opt-in policies. Permit device-only storage before import and for existing credentials.
- Keep passphrases, server fingerprint trust, terminal output, and active connections on each device. Do not put secret values in iCloud configuration records.
- Preserve local credentials during migration failures and name conflicts. Show each credential’s storage location. Keep a local copy before removing a shared copy. Explain that removal can affect other devices.
- Refresh available credentials when the app becomes active, when the credential view opens, and on manual refresh. Do not claim that a successful Keychain write confirms delivery to another device.
- Merge edits to different hosts. For competing edits to one host, use the newer record. Pause further sync writes when Apple reports an iCloud account change until the user selects how to continue. Do not interrupt an active terminal when cloud settings arrive.
- On the Mac, preview selected aliases with system OpenSSH before importing them. Read the user's chosen SSH configuration without changing it. Import selected AWS profiles into the Mac Keychain; do not execute SSO, role-assumption, or credential-process flows during import.

## Scope limits

Avoid overengineering. Reuse terminal and SSH libraries. Use concrete transports for the approved cloud providers, local storage, and Apple's iCloud key-value store for the small configuration set. Do not add a custom keyboard, offline command editor, full SSH-config parser on iOS, full tmux window/pane management UI, Mosh, SFTP, a custom sync service, gateway, or credential-provider framework.

Use macOS OpenSSH to resolve selected host settings for initial import. Do not ship the user's private hosts or credentials in the application bundle or source control. Do not modify remote shell or tmux configuration as part of connecting.

Keep the GitHub repository public. Before publication, scan tracked files and Git history for credentials. Exclude private connection fixtures, environment files, SSH keys, AWS credentials, and signing files from Git. Enable GitHub secret scanning and push protection. Use only synthetic credentials or published test vectors in tests.

## Acceptance

Build for iPhone and iPad. Run protocol and parsing tests. Test an actual direct SSH connection and both AWS profile paths where credentials and access permit. Test tmux remapping and reconnection, including no input replay. Run the app in an iOS Simulator and inspect the visible UI. Record any physical-device, signing, network, or compatibility checks that remain incomplete.

Test offline configuration merges, competing host edits, settings persistence, and invalid cloud data. Verify actual iCloud transfer between two signed-in devices when an iCloud-enabled provisioning profile is available. Unit tests do not prove that transfer. Test selected-credential migration, same-name conflicts, shared updates, removal from iCloud, and local fingerprint trust in signed app hosts. Use synthetic data for cross-device credential tests.

Implementation decisions are in [DESIGN.md](DESIGN.md). Keep local planning notes that contain private environment details out of source control.

Delivery state, including requirements that are not yet deployed, is tracked in [docs/DELIVERY_PLAN.md](docs/DELIVERY_PLAN.md). Follow the test, deploy, then commit sequence in [AGENTS.md](AGENTS.md).
