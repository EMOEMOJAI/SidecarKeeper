#!/bin/bash
# Re-renders the PNG/ICO files from the SVG sources using headless Chrome.
#   assets/render.sh
set -euo pipefail
cd "$(dirname "$0")"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[ -x "$CHROME" ] || { echo "Chrome not found; set CHROME=/path/to/chrome" >&2; exit 1; }
TMP="${TMPDIR:-/tmp}"; WORK="$(mktemp -d "${TMP%/}/sk-assets.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

# render SVG WIDTH HEIGHT OUT [css-color]
render() {
  local svg="$1" w="$2" h="$3" out="$4" color="${5:-#000}"
  # Inline the SVG so currentColor works. Chrome clamps tiny windows, so small art is
  # centred in a 500 px window and sips (which crops from the centre) trims it after.
  { printf '<!doctype html><html><body style="margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:transparent;color:%s">' "$color"
    sed -e "s/<svg /<svg style=\"display:block;flex:none;width:${w}px;height:${h}px\" /" "$svg"
    printf '</body></html>'; } > "$WORK/page.html"
  local W=$(( w < 500 ? 500 : w )) H=$(( h < 500 ? 500 : h ))
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color=00000000 --window-size="$W,$H" \
    --screenshot="$WORK/shot.png" "file://$WORK/page.html" >/dev/null 2>&1
  sips -c "$h" "$w" "$WORK/shot.png" --out "$out" >/dev/null
  echo "  $out"
}

render icon.svg 1024 1024 icon-1024.png
render icon.svg 256 256 icon-256.png
render favicon.svg 16 16 favicon-16.png
render favicon.svg 32 32 favicon-32.png
render favicon.svg 48 48 favicon-48.png
render favicon.svg 180 180 apple-touch-icon.png
render icon-mono.svg 663 576 icon-mono-white.png "#fff"
render social-preview.svg 1280 640 social-preview.png

# Root copy: some editors and tools look for favicon.svg in the project root first.
cp favicon.svg ../favicon.svg; echo "  ../favicon.svg"

# The website in docs/ serves its own copies.
sync_docs() { for f in favicon.svg favicon.ico apple-touch-icon.png icon.svg social-preview.png; do cp "$f" "../docs/$f"; done; echo "  ../docs/ (5 files)"; }

# favicon.ico: PNG-compressed entries, 16/32/48.
python3 - <<'PY'
import struct
sizes=[16,32,48]; blobs=[open(f"favicon-{s}.png","rb").read() for s in sizes]
out=struct.pack("<HHH",0,1,len(sizes)); off=6+16*len(sizes)
for s,b in zip(sizes,blobs):
    out+=struct.pack("<BBBBHHII",s,s,0,0,1,32,len(b),off); off+=len(b)
open("favicon.ico","wb").write(out+b"".join(blobs)); print("  favicon.ico")
PY
sync_docs
