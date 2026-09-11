# Term Anywhere requirements

Status: approved scope for implementation. Minimum OS: iOS/iPadOS 26 and macOS 26. The current Mac build supports Apple Silicon.

## Purpose

Provide a personal remote terminal on iPhone and iPad. Support the user's selected hosts from the Mac SSH configuration, including direct SSH and SSH through AWS Systems Manager. The app must connect independently of the Mac after setup.

Provide a native Mac app to configure hosts, import SSH keys and static AWS profiles, and open remote terminals. Use the same iCloud settings store as the phone and tablet. Use iCloud Keychain for SSH keys and AWS profiles by default. Permit an explicit device-only choice.

## Required behavior

- Follow Apple Human Interface Guidelines. Use native controls, adaptive iPhone/iPad layouts, readable terminal text, and accessible labels.
- Support SSH keys, including encrypted private keys. Store credentials in the device Keychain. Verify server host keys before authentication.
- Support the current AIxC and NR SSM connection pattern: AWS authorization, an AWS-StartSSHSession tunnel, then SSH authentication.
- Provide a system keyboard with Esc, Ctrl, Tab, arrows, and a More menu. Support hardware keyboards, Chinese composition, copy/paste, and terminal resizing.
- Support an optional named tmux session per saved connection. Reconnect to the same session after a connection failure. Never replay buffered input into a new connection.
- The running app must query each connected server for its effective tmux prefix and bindings after attachment and reconnection. Keep mappings separate per connection. Provide manual refresh. This is not a development-time import of tmux settings.
- Map only understood, unambiguous tmux bindings. Keep ordinary terminal keys and a manual prefix fallback when detection fails.
- Retain a disconnected screen with an accurate status. Do not promise continuous execution while iOS suspends the app or survival of remote processes after server restart.
- Support host editing, selected-host settings import, private-key import, AWS credential entry/import, and basic session switching.
- Sync saved host definitions and terminal preferences through iCloud. Include tmux session/socket settings, manual prefix, SSH key names, and AWS profile names. Keep local copies for offline use.
- Sync imported SSH private keys and AWS profiles through iCloud Keychain by default. Migrate existing local credentials unless the user has explicitly selected device-only storage. This replaces the earlier local-only and opt-in policies. Permit device-only storage before import and for existing credentials.
- Keep passphrases, server fingerprint trust, terminal output, and active connections on each device. Do not put secret values in iCloud configuration records.
- Preserve local credentials during migration failures and name conflicts. Show each credential’s storage location. Keep a local copy before removing a shared copy. Explain that removal can affect other devices.
- Refresh available credentials when the app becomes active, when the credential view opens, and on manual refresh. Do not claim that a successful Keychain write confirms delivery to another device.
- Merge edits to different hosts. For competing edits to one host, use the newer record. Pause further sync writes when Apple reports an iCloud account change until the user selects how to continue. Do not interrupt an active terminal when cloud settings arrive.
- On the Mac, preview selected aliases with system OpenSSH before importing them. Read the user's chosen SSH configuration without changing it. Import selected AWS profiles into the Mac Keychain; do not execute SSO, role-assumption, or credential-process flows during import.

## Scope limits

Avoid overengineering. Reuse terminal and SSH libraries. Use two concrete transports, local storage, and Apple's iCloud key-value store for the small configuration set. Do not add a custom keyboard, offline command editor, full SSH-config parser on iOS, tmux management UI, Mosh, SFTP, a custom sync service, gateway, or credential-provider framework.

Use macOS OpenSSH to resolve selected host settings for initial import. Do not ship the user's private hosts or credentials in the application bundle or source control. Do not modify remote shell or tmux configuration as part of connecting.

## Acceptance

Build for iPhone and iPad. Run protocol and parsing tests. Test an actual direct SSH connection and both AWS profile paths where credentials and access permit. Test tmux remapping and reconnection, including no input replay. Run the app in an iOS Simulator and inspect the visible UI. Record any physical-device, signing, network, or compatibility checks that remain incomplete.

Test offline configuration merges, competing host edits, settings persistence, and invalid cloud data. Verify actual iCloud transfer between two signed-in devices when an iCloud-enabled provisioning profile is available. Unit tests do not prove that transfer. Test selected-credential migration, same-name conflicts, shared updates, removal from iCloud, and local fingerprint trust in signed app hosts. Use synthetic data for cross-device credential tests.

The original investigation, alternatives, and sources are in [PROPOSAL.md](PROPOSAL.md). Implementation decisions are in [DESIGN.md](DESIGN.md).
