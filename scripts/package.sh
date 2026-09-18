#!/bin/bash
# Builds the release bundle into dist/:
#   SidecarKeeper.tar.gz         prebuilt universal binaries + installer, needs nothing but macOS
#   SidecarKeeper.tar.gz.sha256
#   install.sh                   the one-liner entry point, stamped with this version and hash
# Run by the release workflow on a GitHub runner. Safe to run locally to try a bundle out.
set -euo pipefail
cd "$(dirname "$0")/.."

MIN_MACOS=14.2
VERSION="$(sed -n 's/^let version = "\(.*\)"$/\1/p' Sources/SidecarKeeper/main.swift)"
# shellcheck disable=SC2016  # the ${...} is literal text being matched, not an expansion
REF="$(sed -n 's/^UPSTREAM_REF="${SIDECARLAUNCHER_REF:-\([0-9a-f]\{40\}\)}"$/\1/p' install.sh)"
[ -n "$VERSION" ] && [ -n "$REF" ] || { echo "could not read version or upstream ref" >&2; exit 1; }
echo "==> SidecarKeeper $VERSION, SidecarLauncher ${REF:0:12}, macOS $MIN_MACOS+, arm64 + x86_64"

TMP="${TMPDIR:-/tmp}"; WORK="$(mktemp -d "${TMP%/}/sk-package.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/SidecarKeeper"; mkdir -p "$STAGE/bin" "$STAGE/launchd"

# universal SRC OUT [swiftc flags...]: one slice per architecture, joined and ad-hoc signed.
universal() {
  local src="$1" out="$2" arch; shift 2
  for arch in arm64 x86_64; do
    # -file-prefix-map keeps the build machine's paths out of the binary.
    swiftc -O -target "$arch-apple-macos$MIN_MACOS" -file-prefix-map "$(dirname "$src")=." \
      "$@" "$src" -o "$WORK/$(basename "$out").$arch"
  done
  lipo -create -output "$out" "$WORK/$(basename "$out").arm64" "$WORK/$(basename "$out").x86_64"
  codesign -s - -f "$out" 2>/dev/null
}

git init -q "$WORK/upstream"
git -C "$WORK/upstream" fetch -q --depth 1 https://github.com/Ocasio-J/SidecarLauncher.git "$REF"
git -C "$WORK/upstream" checkout -q FETCH_HEAD
universal "$WORK/upstream/SidecarLauncher/main.swift" "$STAGE/bin/SidecarLauncher"
universal "$PWD/Sources/SidecarKeeper/main.swift" "$STAGE/bin/sidecar-keeper" -warnings-as-errors -framework AppKit

[ "$("$STAGE/bin/sidecar-keeper" --version)" = "$VERSION" ] || { echo "binary version mismatch" >&2; exit 1; }
for b in sidecar-keeper SidecarLauncher; do
  [ "$(lipo -archs "$STAGE/bin/$b")" = "x86_64 arm64" ] || { echo "$b is not universal" >&2; exit 1; }
done

cp install.sh uninstall.sh LICENSE README.md CHANGELOG.md "$STAGE/"
cp launchd/com.sidecarkeeper.plist.template "$STAGE/launchd/"
cp "$WORK/upstream/LICENSE" "$STAGE/LICENSE-SidecarLauncher"
cat > "$STAGE/START-HERE.txt" <<TXT
SidecarKeeper $VERSION

Open Terminal, drag install.sh into the window, and press Return.
Unlock your iPad first. To remove it later: ~/.sidecarkeeper/uninstall.sh

Documentation: https://github.com/EMOEMOJAI/SidecarKeeper
TXT

rm -rf dist; mkdir dist
# No owner names, no timestamps from this machine's clock order, no macOS metadata files.
COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata --uid 0 --gid 0 --uname root --gname wheel \
  -czf dist/SidecarKeeper.tar.gz -C "$WORK" SidecarKeeper
SHA="$(shasum -a 256 dist/SidecarKeeper.tar.gz | awk '{print $1}')"
echo "$SHA  SidecarKeeper.tar.gz" > dist/SidecarKeeper.tar.gz.sha256
sed -e "s/^BUNDLE_VERSION=\"\"$/BUNDLE_VERSION=\"$VERSION\"/" -e "s/^BUNDLE_SHA256=\"\"$/BUNDLE_SHA256=\"$SHA\"/" install.sh > dist/install.sh
grep -q "^BUNDLE_SHA256=\"$SHA\"$" dist/install.sh || { echo "stamping failed" >&2; exit 1; }
chmod +x dist/install.sh
echo "==> dist/"; (cd dist && wc -c SidecarKeeper.tar.gz SidecarKeeper.tar.gz.sha256 install.sh | sed 's/^/    /'); echo "    sha256 $SHA"
