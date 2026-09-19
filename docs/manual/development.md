# Development

[Manual](README.md) · [Install](install.md) · [Configuration](configuration.md) · [Wired mode](wired-mode.md) · [Troubleshooting](troubleshooting.md) · [FAQ](faq.md) · [How it works](how-it-works.md) · [Development](development.md)

```sh
make build   # build/sidecar-keeper
make test    # 56 behaviour tests against a fake SidecarLauncher, no iPad needed (~40 s)
make check   # build + test + bash -n + shellcheck + plist lint; run before pushing
make package # release bundle with universal binaries, in dist/
```

CI runs on GitHub-hosted runners for every push and pull request, and once a week. It
builds with warnings as errors and runs the tests on macOS 15 and 26 on Apple silicon, on
macOS 15 on a real Intel Mac, and on macOS 14 for as long as GitHub offers that runner (it
retires on 2 November 2026, and until then its result is reported but does not block). Each
runner also does a real install and uninstall, from source and from a release bundle with the
compiler disabled. The weekly run additionally installs the latest release through the
public one-liner. Linux runs shellcheck and a check of the links in the docs.

The weekly run also compares the SidecarLauncher commit that `install.sh` pins against
upstream, and opens an issue when it has fallen behind. The pin never moves by itself, which
is deliberate, so this is the only thing that would notice an upstream fix. Run it yourself
with `make upstream`. Taking an update means reading the upstream diff, changing
`UPSTREAM_REF` in `install.sh`, running `make check`, and releasing; the Homebrew formula
follows the pin on its own.

Pushing a `v*` tag runs the release workflow. It builds the bundle, installs it on every
runner above, publishes, and then installs the published release through the one-liner on
Apple silicon and Intel as a final check.

`SIDECARLAUNCHER_REF=<full 40-character sha> ./install.sh` builds a different upstream commit.

The icon, favicon and social preview are hand-written SVG in `assets/`. After editing
one, run `assets/render.sh` to regenerate the PNG and ICO files (needs Google Chrome,
`python3` and `sips`). The `favicon.svg` in the repo root is a copy of
`assets/favicon.svg`, kept there because some editors and tools look for a project icon
at that path.

Run it in the foreground against your existing install to experiment:

```sh
build/sidecar-keeper --launcher ~/.sidecarkeeper/bin/SidecarLauncher --log /tmp/sk.log --interval 5
```
