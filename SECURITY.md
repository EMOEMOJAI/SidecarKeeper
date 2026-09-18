# Security

Please report vulnerabilities privately through
[GitHub's private vulnerability reporting](https://github.com/EMOEMOJAI/SidecarKeeper/security/advisories/new),
not in a public issue. You can expect a first reply within a week.

In scope: the watcher, `install.sh`, `uninstall.sh`, and the LaunchAgent they create. Things
worth reporting include the installer or uninstaller touching files outside the install
prefix, injection through device names, paths or environment variables, and anything that
runs with more privilege than a per-user LaunchAgent.

SidecarKeeper never uses `sudo`, makes no network requests at runtime, and collects no data.

What you are trusting depends on how you install:

- **Release install (the one-liner or the downloaded bundle).** Two prebuilt binaries are
  installed. They are built by GitHub Actions from the tagged source, ad-hoc signed and
  **not notarized**, and the installer removes the macOS quarantine flag from them so they can
  run, which also means macOS does not prompt before they do. The `install.sh` attached to a
  release carries the SHA-256 of that release's archive and refuses anything else. Each
  release file also has a build provenance attestation, which the installer does not check
  for you: `gh attestation verify SidecarKeeper.tar.gz --repo EMOEMOJAI/SidecarKeeper`.
- **Source install (from a git clone).** Both binaries are compiled on your Mac. The
  installer fetches one pinned commit of
  [SidecarLauncher](https://github.com/Ocasio-J/SidecarLauncher) and builds it locally.

Either way you are trusting this repository and its GitHub account. Issues in SidecarLauncher
or in Apple's private `SidecarCore` framework belong upstream.

Only the latest release is supported.
