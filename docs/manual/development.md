# Development

[Manual](README.md) · [Install](install.md) · [Configuration](configuration.md) · [Wired mode](wired-mode.md) · [Troubleshooting](troubleshooting.md) · [FAQ](faq.md) · [How it works](how-it-works.md) · [Development](development.md)

```sh
make build   # build/sidecar-keeper
make test    # 45 behaviour tests against a fake SidecarLauncher, no iPad needed (~40 s)
make check   # build + test + bash -n + shellcheck + plist lint; run before pushing
make package # release bundle with universal binaries, in dist/
```

CI runs on GitHub-hosted runners for every push and pull request: the same build and
tests on macOS 14, 15 and 26, a real install and uninstall on each (from source and from a
release bundle with the compiler disabled), and shellcheck on Linux. Pushing a `v*` tag
runs the release workflow, which builds the bundle, installs it on all three macOS
versions, and only then publishes it. The tests run the real watcher binary, so its real gates apply: locally, run them
with the screen unlocked and the lid open.
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
