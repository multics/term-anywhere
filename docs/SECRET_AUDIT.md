# Public repository credential audit

Date: 2026-09-11 (America/Los_Angeles).
Repository: `multics/term-anywhere`.
Source baseline: `fae935fb7350984342f1a789758fae0f66c1285e`.

## Result

No real keys, tokens, passwords, or other credentials were found in the checked source and history. The repository is now public. GitHub reports that secret scanning and push protection are enabled. The first secret-alert query returned an empty list.

## Checked scope

- Refreshed the origin refs and checked the remote branch, tag, and pull-request refs. The remote had one branch (`main`), with 17 commits, and no tags or pull-request refs. The checkout was not shallow.
- Scanned all 81 tracked files from the working tree with Gitleaks 8.30.1.
- Ran `gitleaks git . --log-opts='--all --full-history' --redact=100 --ignore-gitleaks-allow`. It scanned 17 commits with no findings.
- Extracted and scanned all 214 distinct Git blobs reachable from all local refs. This covers complete file content, including unchanged content and deleted historical files. These refs reached 19 commits: the 17 published commits and two local stash commits. The stash was not published.
- Scanned commit messages separately.
- Checked historical paths for credential files. Checked private-key markers, common provider token formats, and credential-like string assignments. Reviewed the matches: synthetic test values and the published AWS signing test vector in `TermCoreTests.swift`.
- Queried GitHub releases, Actions runs, and Actions artifacts. All were empty. The repository had no open issues, and its wiki was disabled.

All Gitleaks scans returned zero findings. Reports used full secret redaction and stayed in a private local temporary directory.

## Prevention

The Git ignore rules exclude environment files, SSH and AWS configuration directories, common private-key filenames, key containers, signing profiles, host exports, and private connection fixtures. Synthetic `.env.example` files remain permitted. Checks confirmed that representative private paths are ignored and no tracked file matches the ignore rules.

GitHub secret scanning and push protection are enabled. Test credentials must remain synthetic or published test vectors. Do not add real credentials to examples, test fixtures, logs, screenshots, or build assets. Keep local host data under `.local/`.

Before a push, run a fully redacted history scan:

```sh
gitleaks git . --log-opts='--all --full-history' --redact=100 --ignore-gitleaks-allow
```

To check staged changes before a commit:

```sh
gitleaks git . --pre-commit --staged --redact=100 --ignore-gitleaks-allow
```

## Limits

This is a credential exposure check, not a general application security audit. Detection patterns cannot prove that every possible secret is absent. GitHub scanning can continue after publication. The empty alert response is an initial observation.

Ignored local build output, private host files, device containers, and Keychain contents were not scanned or published. Unreachable Git objects and remote refs that GitHub does not advertise are outside the checked scope. Ignore rules do not remove previously tracked data or stop a forced add. A real credential found in published history must be revoked or rotated; deleting the current file is not sufficient.

This change affects repository controls and documentation. No app executable changed, so device deployment does not apply.
