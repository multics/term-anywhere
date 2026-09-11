# Term Anywhere design

Status: first development build. See README.md for completed checks and remaining validation.

## Structure

- `App`: SwiftUI host list and forms, UIKit/SwiftTerm terminal, accessory keys, and connection state shown to the user.
- `MacApp`: native Mac host editor, SSH/AWS import previews, and AppKit/SwiftTerm terminal. The Mac target shares the app store, connection lifetime, credentials form, settings, and configuration sync with iOS.
- `Sources/TermCore`: saved connection models, Keychain storage, SSH session lifetime, AWS signing and SSM transport, and tmux binding detection.
- `Sources/CSSH`: a small bridge to libssh2. SSH operations run on a serial worker queue.
- `Scripts`: reproducible native dependency builds and selected-host export. The app needs no Mac process at runtime.
- `Tests`: focused protocol, binding, and credential-storage tests. A macOS connection-check executable uses the same connection code as the app.

Use SwiftTerm for terminal rendering and input-method support. Use pinned libssh2 and OpenSSL for SSH. The native build script produces libraries for iPhone, Simulator, and macOS. Keep generated dependencies and private setup files out of version control.

## Connection paths

Direct SSH opens a TCP socket. SSM signs an AWS StartSession request, opens the returned data channel, and carries SSH bytes over a local socket pair. libssh2 consumes the same ordered byte stream in either case. The SSM adapter handles message validation, sequence numbers, acknowledgements, and bounded queues. Unsupported handshake requirements fail explicitly.

Verify the SSH host-key fingerprint before sending a private-key signature. Store trust separately from private keys. A new key needs a fingerprint decision; a changed key must stop the connection. Private keys and AWS secrets use iCloud Keychain by default, with an explicit local-storage option. No terminal content or secrets enter diagnostic logs.

## Terminal input

The terminal view owns the system input method. Marked text stays local until committed. The accessory row uses fixed Esc, Ctrl, Tab, arrow, and More controls. Ctrl is one-shot. Terminal library key methods preserve application-cursor behavior. App shortcuts use Command; Control combinations go to the terminal.

Use UIKit keyboard-aware layout and send the terminal's new row/column count to the PTY. Keep the remote host visible. Give each session its own terminal view, connection object, and tmux mapping.

## Runtime tmux adaptation

After attaching to the configured session, use a separate SSH execution channel to query the same user's tmux socket. Read the session's effective prefix and root/prefix bindings. Map only recognized built-in actions with supported key encodings. Show the resolved sequence in the More menu.

Resolve the exact session name from `list-sessions` to its numeric session ID. Use that ID for queries and recovery. This avoids name-prefix matches and works with the tested tmux 3.4 servers. Drain stdout and stderr on query channels and close command input. Limit the query size and duration.

Re-query on every connection and reconnection, and on manual Refresh. Do not parse `.tmux.conf`, start a file watcher, change bindings, or guess plugin scripts. Missing, ambiguous, or unsupported mappings remain unavailable. A manual prefix remains possible. Nested tmux and custom key-table chains are outside the current scope.

## Recovery

Initial connection can create or attach to a named session. Recovery must attach to the existing session; it must not silently create a replacement. Keep the last terminal screen while disconnected. Discard unsent keystrokes on connection loss. Retry transient failures with bounded delays while active. Stop for trust or credential decisions and explicit disconnects.

App state is independent of transient SwiftUI view creation. On return to the foreground, check the connection and reconnect if needed. Remote tmux retains remote programs; the app retains only local connection references. Closing the app's session does not kill the remote tmux session.

## iCloud configuration

Use `NSUbiquitousKeyValueStore` for this small set of settings. No CloudKit database or app server is needed. Apple limits this store to 1 MB and 1024 keys; the app leaves a margin and stops uploads above 900 KB or 1000 keys. Local saves still work. See [Apple's key-value storage guidance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UserDefaults/StoringPreferenceDatainiCloud/StoringPreferenceDatainiCloud.html).

Each host has one versioned key. Terminal font size and Option-as-Meta share one preferences record. A record has a modification date and a random revision ID. The newer date wins; the revision ID breaks ties in a consistent way. Different hosts merge independently. A local edit advances beyond that record's last known date. Concurrent edits still depend on device clocks; this design has no edit-history interface.

Save the complete local configuration atomically before publishing. Merge external notifications and cached cloud records before uploading. Do not upload default preferences at first launch. Migrate the previous `hosts.json` with an old timestamp so an existing cloud edit takes priority. Keep that original file as a local migration backup. Use the versioned local file on later launches.

Store credential names, but never secret values, in configuration records. Sync credential values through the separate iCloud Keychain path below, except for explicit device-only choices. Each device makes its own fingerprint decisions. Read effective tmux bindings from the server after each connection; do not sync a stale binding cache.

Observe the key-value store's account-change notification. Pause further reads and writes when it arrives, and retain that pause across app launches. Keep local settings. An explicit merge action resumes sync. This is a guard on app writes, not a cancellation of transfers already queued by Apple. Account-switch behavior still needs a device test.

Do not gate key-value storage on `ubiquityIdentityToken`; that token describes document-container availability. Key-value storage accepts local updates and transfers them when an account becomes available. See [Apple's storage API comparison](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/iCloudFundametals.html). `synchronize()` does not confirm that another device received data; the UI must not claim that it does. See [Apple's synchronization API](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore/synchronize()).

Incoming host changes do not interrupt a live connection. Close that app session and reopen the host to use its new connection settings. Terminal preferences update the existing views. Host deletion remains outside the current interface, so no deletion records are required yet.

The Xcode entitlement enables iCloud key-value storage. Actual transfer requires a development team and a provisioning profile that permits this capability. See [Apple's iCloud setup instructions](https://developer.apple.com/documentation/xcode/configuring-icloud-services).

## Mac configuration workflow

The Mac bundle ID is `me.tianyong.term-anywhere.mac`. Its key-value store entitlement explicitly uses the iOS store, `$(TeamIdentifierPrefix)me.tianyong.term-anywhere`. Local settings reside in `~/Library/Application Support/TermAnywhere/`. Use the same host IDs as the existing Python export to avoid duplicate imports.

The import sheet lists explicit aliases in the selected SSH config. Users can type names from Include files. `/usr/bin/ssh -G -F <config> <alias>` resolves each preview, including its Include files. The app only recognizes the supported direct and SSM connection patterns; it never executes ProxyCommand text. As with normal OpenSSH config loading, a trusted local `Match exec` directive can run during resolution. Use only trusted SSH config files.

The SSH key picker opens `.ssh` and shows hidden files. An empty destination name uses the key's filename. The AWS import sheet reads static profiles, displays only their names, and saves only selected entries to the Mac Keychain. It accepts a session token but has no credential-refresh service. Imported credential values do not enter configuration records. New imports use iCloud Keychain unless the user turns off sync before import. Replacements preserve the existing storage choice, including iCloud Keychain when enabled.

Use a single native Mac window with a sidebar, host form, and terminal view. Preserve the shared SSH/SSM and tmux recovery code. Use AppKit input, selection, and copy/paste. Show a confirmation sheet for pastes with line breaks or control characters. Keep remote clipboard requests disabled through the terminal delegate defaults.

This personal development build runs without App Sandbox so system OpenSSH can resolve the user's existing local configuration. It is signed with hardened runtime and the iCloud entitlement. This is not a Mac App Store or notarized distribution build.

## Validation record

Implementation and validation results are in [README.md](README.md). The icon uses a mint terminal prompt and an open teal ring. Its source and design record are in [APP_ICON.md](APP_ICON.md).


## iCloud Keychain by default

Use the Security framework with two explicit storage scopes. Local queries exclude synchronizable items. On iOS, use the original app access group. On macOS, retain access to the original login Keychain so existing credentials remain readable. The shared scope uses `kSecAttrSynchronizable = true`, `kSecAttrAccessibleWhenUnlocked`, and the common access group `$(AppIdentifierPrefix)me.tianyong.term-anywhere.shared`. On macOS, this scope uses the data protection Keychain. Keep each app’s original group first in its entitlements. Read the expanded group names from Info.plist; do not hardcode a developer team in the Swift library.

Only `key:` and `aws:` items can enter the shared scope. They remain generic-password items: private-key bytes or encoded AWS credentials, including a session token when supplied. This change does not add certificate-identity import, passphrase storage, SSO, or automatic credential renewal. Server fingerprint items use the local scope.

New imports use iCloud Keychain by default. The import switches permit device-only storage for new items. Replacements preserve the effective storage choice. On launch and refresh, migrate existing local credentials unless they have an explicit device-only marker. The marker uses a separate local Keychain item under `device-only:<credential account>`; it contains no credential value and never syncs. Write this marker before saving a new device-only credential, so a failed save cannot cause a later automatic upload. The menu beside a saved credential can change its storage choice.

For migration, copy the value to the shared scope, read it back, and only then delete the local item. Never overwrite a different shared value during migration. If both scopes contain the name, use the local copy and show both locations. Keep failed migrations visible in the credential view and continue with other credentials. An explicit **Use iCloud copy on this device** action deletes the separate local copy. The user can also import the local value under another name. Existing host references still use credential names.

Replacing a saved credential preserves its effective scope. An update to a shared credential can reach other devices. To remove a credential from iCloud, first retain the effective value locally, save its device-only marker, and then delete the shared item. Enabling sync removes the marker. Confirm this action in the UI because other devices can lose access when the deletion arrives. Separate local copies remain. This operation does not revoke server access and cannot erase a copy already exported or held by an active connection.

Keychain does not provide an app-level transaction across devices. Concurrent shared edits and delivery order are controlled by Apple. A migration readback confirms a local Keychain operation, not remote delivery. The UI labels storage choice, not sync completion. Refresh the credential list on activation, on opening the credential view, or with **Refresh credentials**. Do not add polling or a custom synchronization service to the app.

Use the same Apple Account and enable Passwords & Keychain in iCloud settings on each device. iCloud Keychain manages its own account state; the configuration store’s account-change pause does not pause Keychain. Explicit device-only credentials remain local. Credentials that follow the default policy can migrate into the currently active account. An offline shared item can remain usable while Apple queues an update. Test account switching and long offline periods separately.

Apple references: [Keychain synchronization attributes](https://developer.apple.com/documentation/security/ksecattrsynchronizable), [shared access groups](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps), and [macOS Keychain implementations](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains).

### Verification

`SharedAppTests/KeychainSyncTests.swift` runs in both signed app hosts. It checks legacy migration, shared updates, name collisions, identical copies, migration failure, removal from iCloud, and local fingerprint trust. The tests use synthetic values in a unique service and remove them and their local-choice markers after each test. They also check default migration, default sync, explicit local imports, and persistent device-only choices.

`KeychainTransferTests` is an opt-in test for actual delivery. Write `keychain-transfer.json` with a fresh UUID in `id` and an `operation` of `publish`, `verify`, or `cleanup`. On Mac, place it beside the built app. On iOS, copy it to the app’s Documents directory with `devicectl device copy to`. Run only `KeychainTransferTests` in the corresponding scheme. The test consumes the fixture. Publish on one device, verify on another, then run cleanup on the publisher. The test uses a separate service and synthetic key and AWS payloads. Compare decoded AWS fields because JSON field order has no meaning. It never reads the app’s real credential service. A receiver waits at most 30 seconds; a failure can mean that delivery is delayed or iCloud Keychain is unavailable.
