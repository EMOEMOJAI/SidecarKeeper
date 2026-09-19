#!/bin/bash
# SidecarKeeper installer. Installs sidecar-keeper and SidecarLauncher (upstream, MIT) under
# ~/.sidecarkeeper/bin and loads a per-user LaunchAgent. Never needs sudo. Safe to re-run.
#
# It works three ways, chosen automatically:
#   release bundle   run from an unpacked release: installs the prebuilt universal binaries.
#                    Needs nothing but macOS.
#   one-liner        run with no files beside it (bash -c "$(curl ...)"): downloads the release
#                    bundle, verifies its SHA-256, and runs the installer inside it.
#   source checkout  run from a git clone: builds both binaries with swiftc. Needs the Xcode
#                    Command Line Tools and git.
set -euo pipefail
[ -n "${BASH_VERSION:-}" ] || { echo "error: run this installer with bash" >&2; exit 2; }

ORIG_ARGS=("$@")
# Filled in by the release workflow in the install.sh attached to a release, so that the
# one-liner fetches exactly that release and checks it against a hash it carries itself.
BUNDLE_VERSION=""
BUNDLE_SHA256=""
RELEASES="https://github.com/EMOEMOJAI/SidecarKeeper/releases"

UPSTREAM_REPO="https://github.com/Ocasio-J/SidecarLauncher.git"
# Pinned so an install always builds code that was reviewed. Override to test a newer upstream.
UPSTREAM_REF="${SIDECARLAUNCHER_REF:-4b7a9df950a64239b2a073428f0390fc16934a9e}"
case "$UPSTREAM_REF" in
  *[!0-9a-f]*|"") echo "error: SIDECARLAUNCHER_REF must be a full 40-character commit SHA" >&2; exit 2 ;;
esac
[ "${#UPSTREAM_REF}" -eq 40 ] || { echo "error: SIDECARLAUNCHER_REF must be a full 40-character commit SHA" >&2; exit 2; }
LABEL="com.sidecarkeeper.agent"
PREFIX="${SIDECARKEEPER_PREFIX:-$HOME/.sidecarkeeper}"
DEVICE=""
LINK=1
WIRED=0

usage() {
  cat <<'USAGE'
usage: install.sh [--device "My iPad"] [--wired] [--prefix DIR] [--no-link]

  --device NAME   iPad to keep connected. Default: the only reachable one, or ask.
  --wired         Experimental: connect over the USB cable only.
  --prefix DIR    Install directory. Default: ~/.sidecarkeeper
  --no-link       Do not link the sidecar-keeper command onto PATH.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEVICE="${2:?--device needs a value}"; shift 2 ;;
    --prefix) PREFIX="${2:?--prefix needs a value}"; shift 2 ;;
    --no-link) LINK=0; shift ;;
    --wired) WIRED=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }
case "$DEVICE" in *$'\n'*) die "--device must not contain a newline" ;; esac
# The prefix is a directory that uninstall.sh deletes wholesale, so it must be ours alone.
case "${PREFIX%/}" in
  ""|"$HOME"|/usr|/usr/local|/opt|/opt/homebrew|/Applications|/Library|/System|/bin|/sbin|/etc|/var|/tmp)
    die "--prefix must be a dedicated directory such as ~/.sidecarkeeper, not $PREFIX" ;;
  /*) ;;
  *) die "--prefix must be an absolute path" ;;
esac
if [ -e "$PREFIX" ] && [ ! -f "$PREFIX/.sidecarkeeper" ] && [ -n "$(ls -A "$PREFIX" 2>/dev/null)" ]; then
  die "$PREFIX already exists and was not created by SidecarKeeper; choose an empty or new directory"
fi
[ "$(uname -s)" = Darwin ] || die "SidecarKeeper only runs on macOS"
[ "$(id -u)" -ne 0 ] || die "run as your normal user, not with sudo: the LaunchAgent is per-user"

# Work out how we were started. Under `bash -c "$(curl ...)"` there is no script file at all.
SELF="${BASH_SOURCE[0]:-}"
# Only a file really called install.sh counts. This keeps a stray name resolved against the
# current directory from ever selecting a bin/ folder to install from.
case "${SELF##*/}" in install.sh) ;; *) SELF="" ;; esac
REPO_DIR=""
if [ -n "$SELF" ] && [ -f "$SELF" ]; then REPO_DIR="$(cd "$(dirname "$SELF")" && pwd)"; fi
if [ -n "$REPO_DIR" ] && [ -x "$REPO_DIR/bin/sidecar-keeper" ] && [ -x "$REPO_DIR/bin/SidecarLauncher" ]; then
  MODE=bundle
elif [ -n "$REPO_DIR" ] && [ -f "$REPO_DIR/Sources/SidecarKeeper/main.swift" ]; then
  MODE=source
  command -v git >/dev/null || die "git not found"
  if ! command -v swiftc >/dev/null || ! xcode-select -p >/dev/null 2>&1; then
    die "swiftc not found. Install the Command Line Tools (xcode-select --install), or use the prebuilt release: $RELEASES/latest"
  fi
else
  MODE=bootstrap
fi

BIN_DIR="$PREFIX/bin"
LOG_DIR="$HOME/Library/Logs"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
TMP="${TMPDIR:-/tmp}"
BUILD_DIR="$(mktemp -d "${TMP%/}/sidecarkeeper.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

if [ "$MODE" = bootstrap ]; then
  [ -z "${SIDECARKEEPER_NO_BOOTSTRAP:-}" ] || die "the downloaded bundle is incomplete (no prebuilt binaries in it)"
  if [ -n "$BUNDLE_VERSION" ]; then url="$RELEASES/download/v$BUNDLE_VERSION/SidecarKeeper.tar.gz"
  else url="$RELEASES/latest/download/SidecarKeeper.tar.gz"; fi
  echo "==> Downloading ${BUNDLE_VERSION:+v$BUNDLE_VERSION }release bundle"
  fetch() { curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 --retry 2 "$1"; }
  fetch "$url" > "$BUILD_DIR/bundle.tar.gz" || die "download failed: $url"
  want="$BUNDLE_SHA256"
  if [ -z "$want" ]; then
    # This copy carries no hash of its own (it did not come from a release), so the checksum
    # is fetched from the same place as the archive and only detects a corrupted download.
    echo "    note: unpinned installer, checksum taken from the release itself" >&2
    want="$(fetch "$url.sha256" | awk '{print $1}')" || die "could not fetch the checksum"
  fi
  got="$(shasum -a 256 "$BUILD_DIR/bundle.tar.gz" | awk '{print $1}')"
  if [ -z "$want" ] || [ "$got" != "$want" ]; then die "checksum mismatch: expected ${want:-<none>}, got $got"; fi
  echo "    sha256 ok"
  tar -xzf "$BUILD_DIR/bundle.tar.gz" -C "$BUILD_DIR"
  [ -f "$BUILD_DIR/SidecarKeeper/install.sh" ] || die "unexpected bundle layout"
  # Bash 3.2 (the macOS default) treats an empty array as unset under `set -u`.
  SIDECARKEEPER_NO_BOOTSTRAP=1 bash "$BUILD_DIR/SidecarKeeper/install.sh" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
  exit $?
fi

if [ "$MODE" = bundle ]; then
  echo "==> Using the prebuilt binaries in $REPO_DIR/bin"
  cp "$REPO_DIR/bin/SidecarLauncher" "$BUILD_DIR/SidecarLauncher.bin"
  cp "$REPO_DIR/bin/sidecar-keeper" "$BUILD_DIR/sidecar-keeper"
  # A browser download is quarantined, and macOS refuses to run quarantined binaries that are
  # not notarized. Removing the flag from these two copies is what lets them run; it also
  # means macOS will not ask before they do.
  xattr -d com.apple.quarantine "$BUILD_DIR/SidecarLauncher.bin" "$BUILD_DIR/sidecar-keeper" 2>/dev/null || true
else
echo "==> Building SidecarLauncher (${UPSTREAM_REF:0:12})"
git init -q "$BUILD_DIR/SidecarLauncher"
git -C "$BUILD_DIR/SidecarLauncher" fetch -q --depth 1 "$UPSTREAM_REPO" "$UPSTREAM_REF" \
  || die "could not fetch $UPSTREAM_REF from $UPSTREAM_REPO"
git -C "$BUILD_DIR/SidecarLauncher" checkout -q FETCH_HEAD
swiftc -O "$BUILD_DIR/SidecarLauncher/SidecarLauncher/main.swift" -o "$BUILD_DIR/SidecarLauncher.bin"

echo "==> Building sidecar-keeper"
swiftc -O -framework AppKit "$REPO_DIR/Sources/SidecarKeeper/main.swift" -o "$BUILD_DIR/sidecar-keeper"

codesign -s - -f "$BUILD_DIR/SidecarLauncher.bin" "$BUILD_DIR/sidecar-keeper" >/dev/null 2>&1 \
  || echo "warning: ad-hoc codesign failed; continuing with unsigned binaries" >&2
fi

echo "==> Looking for reachable Sidecar devices"
DEVICES="$("$BUILD_DIR/SidecarLauncher.bin" devices 2>/dev/null | grep -v '^No sidecar capable devices detected$' || true)"
COUNT=$(grep -c . <<<"$DEVICES" || true)
if [ -n "$DEVICES" ]; then printf '    %s\n' "$DEVICES" | sed 's/^    \(.\)/    - \1/'; else echo "    (none)"; fi

if [ -z "$DEVICE" ]; then
  if [ "$COUNT" -eq 1 ]; then
    DEVICE="$DEVICES"
  elif [ "$COUNT" -gt 1 ] && [ -t 0 ]; then
    echo "Which one should stay connected?"
    OLD_IFS="$IFS"; IFS=$'\n'; set -f   # split on newlines only, and never glob a name like "iPad *"
    # shellcheck disable=SC2086
    select choice in $DEVICES; do [ -n "$choice" ] && { DEVICE="$choice"; break; }; done
    set +f; IFS="$OLD_IFS"
    [ -n "$DEVICE" ] || die "no device chosen"
  elif [ "$COUNT" -gt 1 ]; then
    die "several devices found; re-run with --device \"<name>\""
  else
    die "no Sidecar device is reachable. Unlock the iPad, keep it nearby or plug it in via USB, check it uses the same Apple ID, then re-run (or pass --device \"<name>\" to install anyway)"
  fi
elif ! grep -qixF -- "$DEVICE" <<<"$DEVICES"; then
  echo "warning: \"$DEVICE\" is not reachable right now; installing anyway. The watcher matches" >&2
  echo "         names ignoring case and apostrophe style, and waits until the device appears." >&2
fi
echo "    using \"$DEVICE\""

EXTRA_ARGS=""
if [ "$WIRED" -eq 1 ]; then
  EXTRA_ARGS="<string>--wired</string>"
  echo "==> Wired-only mode (experimental)"
  if "$BUILD_DIR/sidecar-keeper" status | grep -q "attached by cable"; then
    echo "    iPad detected on USB"
  else
    echo "warning: no iPad detected on USB. In wired mode the watcher stays idle until the cable" >&2
    echo "         is plugged in. If it is plugged in now, see https://github.com/EMOEMOJAI/SidecarKeeper/blob/main/docs/manual/wired-mode.md" >&2
  fi
fi

echo "==> Installing to $BIN_DIR"
mkdir -p "$BIN_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"
install -m 755 "$BUILD_DIR/SidecarLauncher.bin" "$BIN_DIR/SidecarLauncher"
install -m 755 "$BUILD_DIR/sidecar-keeper" "$BIN_DIR/sidecar-keeper"
# Marker that uninstall.sh requires before it will delete this directory.
echo "SidecarKeeper install directory. Removed by uninstall.sh." > "$PREFIX/.sidecarkeeper"
# Keep the uninstaller with the install, so it is there after a release bundle is deleted.
install -m 755 "$REPO_DIR/uninstall.sh" "$PREFIX/uninstall.sh"

echo "==> Writing LaunchAgent $PLIST"
# Every value is escaped for XML, then for the sed replacement (\, & and the | delimiter).
xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }
# Render beside the target and lint before touching the running agent, so a failure here
# leaves an existing install untouched.
sed -e "s|@@BIN_DIR@@|$(esc "$(xml "$BIN_DIR")")|g" -e "s|@@LOG_DIR@@|$(esc "$(xml "$LOG_DIR")")|g" \
    -e "s|@@DEVICE@@|$(esc "$(xml "$DEVICE")")|g" -e "s|<!--@@EXTRA_ARGS@@-->|$(esc "$EXTRA_ARGS")|" \
  "$REPO_DIR/launchd/com.sidecarkeeper.plist.template" > "$PLIST.tmp"
plutil -lint -s "$PLIST.tmp" || { rm -f "$PLIST.tmp"; die "generated plist is invalid"; }
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)/$LABEL" || true
fi
mv -f "$PLIST.tmp" "$PLIST"
launchctl bootstrap "gui/$(id -u)" "$PLIST"

# Put `sidecar-keeper` on PATH when a user-writable bin directory is already on it.
CMD="$BIN_DIR/sidecar-keeper"
if [ "$LINK" -eq 1 ]; then
  for d in "$HOME/.local/bin" "$HOME/bin" /opt/homebrew/bin /usr/local/bin; do
    case ":$PATH:" in *":$d:"*) ;; *) continue ;; esac
    if [ ! -d "$d" ] || [ ! -w "$d" ]; then continue; fi
    if [ -L "$d/sidecar-keeper" ] && [ "$(readlink "$d/sidecar-keeper")" != "$BIN_DIR/sidecar-keeper" ]; then
      echo "note: $d/sidecar-keeper belongs to something else, left alone" >&2; continue
    fi
    if [ ! -e "$d/sidecar-keeper" ] || [ -L "$d/sidecar-keeper" ]; then
      ln -sfn "$BIN_DIR/sidecar-keeper" "$d/sidecar-keeper"
      echo "$d/sidecar-keeper" > "$PREFIX/symlink"
      CMD="sidecar-keeper"
      break
    fi
  done
fi

cat <<MSG

SidecarKeeper is running for "$DEVICE"$( [ "$WIRED" -eq 1 ] && echo " (wired only)" ).

  $CMD status     agent state and recent log lines
  $CMD pause      stop reconnecting (when you disconnect Sidecar on purpose)
  $CMD resume     start again
  tail -f $LOG_DIR/sidecar-keeper.log
  $PREFIX/uninstall.sh

Optional: keep the Mac awake with the lid closed on AC power (Sidecar still
drops while the lid is closed, but reconnects as soon as it is opened):
  sudo pmset -c disablesleep 1      (undo with: sudo pmset -c disablesleep 0)
MSG
