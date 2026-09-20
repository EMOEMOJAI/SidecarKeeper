# Contributing

Bug reports and fixes are welcome. Include your macOS version, Mac model family, USB or
Wi-Fi connection, `sidecar-keeper status` output and relevant log lines from
`~/Library/Logs/sidecar-keeper.log`. Remove device names you would rather not share.
Report vulnerabilities through [Security](SECURITY.md).

## Build and test

Requires macOS, git and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/EMOEMOJAI/SidecarKeeper.git
cd SidecarKeeper
make build   # build/sidecar-keeper
make test    # behaviour tests using a fake launcher; no iPad required
make check   # build, tests, script lint, plist validation and documentation links
```

Run `make check` before opening a pull request. Behaviour changes need a test in
`tests/run.sh` that fails without the change. Keep the project dependency-free and in one
Swift file. Read [AGENTS.md](AGENTS.md) for the project rules and platform constraints.

Failed connect attempts show notifications, so preserve every connection gate. Never use
real Sidecar connect or disconnect calls in tests; follow the fake-launcher setup in
`tests/run.sh`, with temporary log, state and USB-probe paths.

CI builds and tests on Apple silicon and Intel, and checks source and release installs.
Weekly checks also exercise the public installer and report upstream changes.

## Maintenance

- **Upstream:** run `make upstream` to check the pinned SidecarLauncher commit. Read the
  upstream diff before changing `UPSTREAM_REF` in `install.sh`, then run `make check`.
  `SIDECARLAUNCHER_REF=<full SHA> ./install.sh` selects a different commit for a source install.
- **Releases:** update `version` in `main.swift` and add a matching section in
  `CHANGELOG.md`. Run `make check`, push the changes, then push `vx.y.z`. GitHub Actions
  builds, verifies and publishes the binaries; never attach locally built binaries.
  `make package` creates a local bundle for testing.
- **Icons:** edit the SVGs in `assets/`, then run `assets/render.sh` (requires Google Chrome,
  Python 3 and `sips`). Keep the root `favicon.svg` in sync with `assets/favicon.svg`.
