# Changelog

## Unreleased

- `pause --for 1h` pauses reconnection for a duration, preserving the expiry across
  watcher restarts. Plain `pause` remains indefinite; `resume` ends either kind early.
- `status` shows the watcher's latest observed state, retry eligibility countdown and
  last successful reconnection. Stopped or stale observations are identified explicitly.

## 1.3.1

No functional change: the watcher and the installer are identical to 1.3.0, so there is
nothing to hunt for if you are already running it. Released to exercise the release pipeline
end to end, including the step that installs the published release through the public
one-liner on Apple silicon and Intel.

- Documentation: Intel Macs are now built, tested and installed by CI on real hardware, so
  the README no longer calls them untested.
- Project: the weekly CI run reports when the pinned SidecarLauncher commit falls behind
  upstream, opens a tracking issue once per upstream commit, and never fails the build for it.

## 1.3.0

- Settings file. Every option can now be set in
  `~/Library/Application Support/SidecarKeeper/config`, one `name = value` per line, so a
  watcher started by `brew services` can be told which iPad to use or to use wired mode.
  `sidecar-keeper config --init` creates a commented template and `sidecar-keeper config`
  shows what is in effect. Command-line flags win over the file.
- A mistake in the settings file is reported in the log with its line number, and the watcher
  stays idle until it is fixed, rather than guess which iPad to connect.
- The pause flag moved to the same directory, so it no longer lives inside the install
  directory. A pause made by an older version is still honoured.
- `uninstall.sh` keeps your settings unless you pass `--purge`.

## 1.2.1

- `sidecar-keeper status` recognises an agent started by `brew services`, names which
  agent is loaded, and warns when two watchers are loaded at once.
- Homebrew: `brew install emoemojai/tap/sidecarkeeper`.

## 1.2.0

- Prebuilt releases. A release now ships universal binaries for Apple silicon and Intel, so
  installing needs nothing but macOS: no Xcode Command Line Tools, no git, no compiler.
- One-line install from Terminal. The installer downloads the release bundle and checks its
  SHA-256 before running anything from it.
- Release binaries are built by GitHub Actions and carry a build provenance attestation.
- The uninstaller is copied into the install directory as `~/.sidecarkeeper/uninstall.sh`.
- Installing from a git clone still builds from source, as before.

## 1.1.1

- The watcher asks the session whether it is locked before every attempt, instead of relying
  only on lock notifications, which are best-effort.
- An unwritable log path now exits with an error instead of running without a log. Missing
  log directories are created.
- `--interval`, `--settle` and `--timeout` reject non-finite and absurd values.
- Launcher error text is never mistaken for a device name.
- CI on GitHub-hosted runners: macOS 14, 15 and 26, including a real install and uninstall.

## 1.1.0

First public release.

- Event-driven watcher: reconnects Sidecar after display sleep, lock, lid close or a dropped
  link, and only attempts a connect when one can succeed.
- `sidecar-keeper pause`, `resume` and `status`.
- Experimental wired-only mode (`--wired`) with USB cable detection and recovery after a
  replug.
- A hung SidecarLauncher call is killed after a timeout and cannot wedge the watcher.
- Device names match regardless of case or apostrophe style.
- Installer builds SidecarLauncher from source at a pinned commit, needs no `sudo`, and is
  safe to re-run. The uninstaller removes only what the installer created.
