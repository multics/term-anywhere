# Term Anywhere design

Status: first development build. See README.md for completed checks and remaining validation.

## Structure

- `App`: SwiftUI host list and forms, UIKit/SwiftTerm terminal, accessory keys, and connection state shown to the user.
- `Sources/TermCore`: saved connection models, Keychain storage, SSH session lifetime, AWS signing and SSM transport, and tmux binding detection.
- `Sources/CSSH`: a small bridge to libssh2. SSH operations run on a serial worker queue.
- `Scripts`: reproducible native dependency builds and selected-host export. The app needs no Mac process at runtime.
- `Tests`: focused protocol, binding, and credential-storage tests. A macOS connection-check executable uses the same connection code as the app.

Use SwiftTerm for terminal rendering and input-method support. Use pinned libssh2 and OpenSSL for SSH. The native build script produces libraries for iPhone, Simulator, and macOS. Keep generated dependencies and private setup files out of version control.

## Connection paths

Direct SSH opens a TCP socket. SSM signs an AWS StartSession request, opens the returned data channel, and carries SSH bytes over a local socket pair. libssh2 consumes the same ordered byte stream in either case. The SSM adapter handles message validation, sequence numbers, acknowledgements, and bounded queues. Unsupported handshake requirements fail explicitly.

Verify the SSH host-key fingerprint before sending a private-key signature. Store trust separately from private keys. A new key needs a fingerprint decision; a changed key must stop the connection. Private keys and AWS secrets reside in device-only Keychain entries. No terminal content or secrets enter diagnostic logs.

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

Store credentials and fingerprint trust only in the existing device Keychain. Cloud records contain credential names, not their values. A second device needs its own imported keys, AWS credentials, and fingerprint decisions. Read effective tmux bindings from the server after each connection; do not sync a stale binding cache.

Observe the key-value store's account-change notification. Pause further reads and writes when it arrives, and retain that pause across app launches. Keep local settings. An explicit merge action resumes sync. This is a guard on app writes, not a cancellation of transfers already queued by Apple. Account-switch behavior still needs a device test.

Do not gate key-value storage on `ubiquityIdentityToken`; that token describes document-container availability. Key-value storage accepts local updates and transfers them when an account becomes available. See [Apple's storage API comparison](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/iCloudFundametals.html). `synchronize()` does not confirm that another device received data; the UI must not claim that it does. See [Apple's synchronization API](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore/synchronize()).

Incoming host changes do not interrupt a live connection. Close that app session and reopen the host to use its new connection settings. Terminal preferences update the existing views. Host deletion remains outside the current interface, so no deletion records are required yet.

The Xcode entitlement enables iCloud key-value storage. Actual transfer requires a development team and a provisioning profile that permits this capability. See [Apple's iCloud setup instructions](https://developer.apple.com/documentation/xcode/configuring-icloud-services).

## Validation record

Implementation and validation results are in [README.md](README.md). The icon uses a mint terminal prompt and an open teal ring. Its source and design record are in [APP_ICON.md](APP_ICON.md).
