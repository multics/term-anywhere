# Term Anywhere

A personal SSH terminal for iPhone, iPad, and Mac. Minimum OS: iOS/iPadOS 26 and macOS 26. The current Mac build supports Apple Silicon. This is a development build.

The app supports direct SSH and SSH through AWS Systems Manager. It uses private keys, device Keychain storage, and server fingerprint checks. It can attach to a named tmux session and read that server's active prefix and bindings on each connection. The keyboard adds Esc, one-shot Ctrl, Tab, arrows, symbols, and detected tmux actions.

Host settings and terminal preferences also sync through iCloud. Credentials remain on each device.

Read [REQUIREMENTS.md](REQUIREMENTS.md) for scope, [DESIGN.md](DESIGN.md) for implementation decisions, and [PROPOSAL.md](PROPOSAL.md) for the original investigation and references. See [APP_ICON.md](APP_ICON.md) for the logo design.

## Build

Use an Apple Silicon Mac with full Xcode 26, its iOS Simulator runtime, CMake, Python 3, and XcodeGen. Select full Xcode with `xcode-select`. Install the Metal Toolchain if Xcode requests it.

```sh
python3 Scripts/prepare-native.py
xcodegen generate
xcodebuild -project TermAnywhere.xcodeproj -scheme TermAnywhere \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData -skipPackagePluginValidation build
```

The native build script fetches pinned dependencies. It builds arm64 libraries for iOS, Simulator, and macOS. Intel Macs are outside this build setup. SwiftTerm's reviewed build plugin reads its Git revision and generates build metadata. The command skips Xcode's separate plugin approval prompt for that build only.

Keep Simulator signing enabled. Its ad-hoc signature supplies the entitlement needed for Keychain access. `CODE_SIGNING_ALLOWED=NO` produces an app that cannot use Keychain in the tested Simulator.

For a physical device, open `TermAnywhere.xcodeproj`, select your development team on the app target, and run it on the paired device. Xcode needs a signed-in account and a matching provisioning profile. The unsigned device artifact cannot be installed as supplied.

Enable **iCloud → Key-value storage** for the app's identifier and provisioning profile. The project already contains the required entitlement. Keep the same team and bundle identifier on both devices. See [Apple's iCloud configuration instructions](https://developer.apple.com/documentation/xcode/configuring-icloud-services).

## Set up connections

### On the Mac

Open `~/Applications/Term Anywhere.app`.

1. Select **Import → Read SSH config**. Review the aliases and select **Preview hosts**. Select the hosts to import. You can type additional aliases from Include files. OpenSSH resolves their effective settings.
2. Open **Keys and AWS profiles**. Select **Import private key**; the picker opens `.ssh` and shows hidden files. Use the key name from the host settings, or leave the name empty to use the filename.
3. Select **Import AWS profiles from this Mac** and choose the static profiles to save. Their values stay in the Mac Keychain. You can also enter a profile manually.
4. Select a host to edit it. **Save** writes the settings locally and to the shared iCloud store. **Open terminal** saves the host and starts a connection.

The Mac uses the same iCloud settings store as iPhone and iPad. SSH keys, AWS secrets, and trust decisions still need separate setup on each device. The Mac import does not modify `.ssh/config` or `.aws/credentials`. Use trusted SSH config files: OpenSSH can evaluate local `Match exec` directives while resolving them.

Build the signed Mac app after preparing the native dependencies:

```sh
xcodegen generate
xcodebuild -project TermAnywhere.xcodeproj -scheme TermAnywhereMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData-mac \
  -skipPackagePluginValidation -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

The product is `DerivedData-mac/Build/Products/Debug/Term Anywhere.app`. This personal development build uses hardened runtime without App Sandbox. It is not a notarized distribution package.

### On iPhone and iPad

1. On the Mac, export explicit settings for selected SSH aliases:

   ```sh
   python3 Scripts/export-hosts.py HOST_ALIAS ANOTHER_ALIAS \
     --output .local/hosts.json --tmux-session mobile
   ```

2. Transfer the JSON through Files and select **Import connections** in the app. The export contains host settings and key names. It contains no private keys or AWS credentials.
3. Open **Keys and AWS**. Import each private key under the name shown in its host settings. For an SSM host, enter AWS credentials under the matching profile name. A session token is optional. Replace temporary credentials when they expire.
4. Open a host. Compare its fingerprint with a trusted source before you accept it. Enter a key passphrase when requested.
5. Use the host's context menu to edit it. An empty tmux session field opens a plain shell. An empty tmux socket field uses the server's default socket.

The export script uses macOS `ssh -G`; it does not run imported proxy commands. It supports the observed `AWS-StartSSHSession` pattern and rejects other proxy commands and ProxyJump. It does not implement all OpenSSH settings. Review the resulting host, user, port, key, profile, and region before import. Local VPN access must already work on the device where required.

After a tmux connection, the app queries the effective settings through a separate SSH channel. It does not read or modify a local development-time copy of `.tmux.conf`. It supports a small set of clear built-in mappings. Scripts, ambiguous bindings, and custom key-table chains remain unavailable. The More menu includes a manual prefix fallback and Refresh.

Connection recovery attaches to the saved tmux session. It does not create a replacement when that session has disappeared. Unsent input is discarded. iOS suspension can break the connection; tmux retains programs on the server while the app reconnects.

## iCloud behavior

Open **+ → Settings and iCloud** to see the sync status and change terminal preferences. Sign in to the same iCloud account on both devices. Host addresses, users, ports, credential names, AWS regions, tmux settings, text size, and Option-as-Meta sync. SSH keys, AWS credentials, passphrases, fingerprint trust, active connections, and terminal output do not sync.

Local changes remain saved without a network. Different hosts merge independently. A newer edit wins when two devices change the same host; dates use the device clocks, with a stable tie-break rule. When Apple reports an iCloud account change, the app pauses further sync writes until you select **Merge settings**. Apple's service controls transfers already queued. Cloud edits do not interrupt a live terminal; close and reopen that app session to use updated connection settings.

Apple schedules delivery, so **Check iCloud** does not guarantee immediate transfer. The device build now has an iCloud-enabled provisioning profile. Actual transfer between two signed-in devices is not yet verified. Local merge tests are verified separately.

## Validation results

Validation date: 2026-09-11. Toolchain: Xcode 26.6, Swift 6.3.3. Simulator runtime: iOS 26.5.

| Check | Result |
| --- | --- |
| macOS core tests | 19 passed: includes configuration merges and native SSH/AWS import checks |
| Native Mac app | Signed build launched; existing iCloud host appeared without import; live SSH preview resolved direct, AIxC SSM, and NR SSM examples; AWS profile preview and SSH key picker inspected |
| Hosted iOS tests | Latest run: four input/Keychain tests passed; live connection test skipped without its private fixture. Earlier live run passed direct SSH and both AWS profile paths |
| Actual iCloud transfer | Not yet verified between two signed-in devices; the installed build includes the iCloud entitlement |
| Actual remote tmux checks | Direct SSH and both SSM paths passed with tmux 3.4; custom prefix/binding detection, separate query channel, and retained state after reconnect |
| Input checks | Chinese marked text stays local until commit; Ctrl is one-shot; cursor mode and terminal dimensions pass |
| Simulator launch | App launched on iPhone 17 Pro and iPad Pro 11-inch; native host layouts inspected |
| Device build | arm64 iOS development signing passed with the Yong Tian team; profile covers both test devices |
| Physical installation | Installed and launched on iPhone 17 Pro Max (iOS 26.6.2) and iPad mini 6 (iPadOS 26.6) |

Run the core tests:

```sh
swift test
```

Run hosted iOS tests on an available Simulator:

```sh
xcodebuild -project TermAnywhere.xcodeproj -scheme TermAnywhere \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData -skipPackagePluginValidation test
```

The live iOS connection test skips unless a private fixture is placed in the Simulator's Documents directory. It deletes the fixture before connecting. Credentials are never test bundle resources. The completed live run used one direct target and one target from each of the AIxC and NR profiles.

The macOS `connection-check` executable uses the same transport code. Its optional `--tmux-check` creates a dedicated temporary tmux socket and removes that test server when complete. It does not change the user's tmux configuration.

## Remaining validation and limits

- Physical keyboard layouts, floating keyboards, VoiceOver, window resizing, and sustained output performance still need device checks. Simulator input tests do not replace those checks.
- Wi-Fi/cellular changes, long background suspension, expired credentials, encrypted-key failure cases, changed host keys, and remote reboot behavior need a broader device test pass.
- AWS credentials are entered directly. SSO login, credential refresh, KMS session handshakes, and other AWS partitions are not implemented.
- The app has host editing, iCloud configuration sync, and session switching. It has no credential sync, SFTP, Mosh, jump-host support, or general SSH-config interpreter. Saved credentials can be replaced under the same name; a deletion interface is not yet present.
- Terminal output is not saved across app termination. Scrollback stays in the terminal view. High-volume rendering has not been load-tested.

## Local artifacts

- `dist/TermAnywhere-Simulator.app`: runnable arm64 Simulator app.
- `dist/Term Anywhere.app`: signed Mac app; installed at `~/Applications/Term Anywhere.app`.
- `dist/TermAnywhere-iOS.app`: signed development app for the registered test devices.
- `dist/TermAnywhere-iOS-unsigned.app`: device build, requires signing before installation.
- `dist/design/term-anywhere-app-icon.png`: original generated logo.
- `.local/hosts.json`: selected private host settings prepared on this Mac, excluded from source control.

Build outputs, private setup files, and test fixtures are excluded from Git. Dependency versions and licenses are recorded in [THIRD_PARTY.md](THIRD_PARTY.md).
