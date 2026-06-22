#!/usr/bin/env bash
#
# Regenerate optimized gallery assets + manifest for chuckgarrett.com.
#
# Usage:  drop full-resolution photos into ./originals/  then run:
#           bash build-gallery.sh
#
# For each source image it writes:
#   photos/<name>.webp          full size  (max 1200px long edge, q80)
#   photos/thumbs/<name>.webp   thumbnail  (max  500px long edge, q72)
# and rewrites photos.json, PRESERVING any caption/alt text you've edited there.
# New photos are appended with an empty caption for you to fill in.
#
# The hero image (HERO below) gets a full size but no thumbnail and is kept
# out of the gallery manifest. Requires: cwebp, sips, python3.

set -eo pipefail
cd "$(dirname "$0")"

SRC="originals"
OUT="photos"
THUMBS="photos/thumbs"
HERO="chuck-and-colin-1998"
FULL_MAX=1200; THUMB_MAX=500
FULL_Q=80;     THUMB_Q=72

mkdir -p "$OUT" "$THUMBS"
shopt -s nullglob nocaseglob

gen () {  # gen <src> <dst> <max-edge> <quality>
  local src="$1" dst="$2" max="$3" q="$4" w h
  w=$(sips -g pixelWidth  "$src" | awk '/pixelWidth/{print $2}')
  h=$(sips -g pixelHeight "$src" | awk '/pixelHeight/{print $2}')
  local rz=()
  if [ "$w" -gt "$max" ] || [ "$h" -gt "$max" ]; then
    if [ "$w" -ge "$h" ]; then rz=(-resize "$max" 0); else rz=(-resize 0 "$max"); fi
  fi
  cwebp -quiet -q "$q" -metadata none "${rz[@]}" "$src" -o "$dst"
}

for f in "$SRC"/*.jpg "$SRC"/*.jpeg "$SRC"/*.png "$SRC"/*.tif "$SRC"/*.tiff; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"; name="${base%.*}"
  full="$OUT/$name.webp"; thumb="$THUMBS/$name.webp"
  if [ ! -e "$full" ] || [ "$f" -nt "$full" ]; then gen "$f" "$full" "$FULL_MAX" "$FULL_Q"; echo "full  $name"; fi
  if [ "$name" != "$HERO" ]; then
    if [ ! -e "$thumb" ] || [ "$f" -nt "$thumb" ]; then gen "$f" "$thumb" "$THUMB_MAX" "$THUMB_Q"; echo "thumb $name"; fi
  fi
done

HERO="$HERO" OUT="$OUT" python3 - <<'PY'
import json, os, subprocess
out = os.environ["OUT"]; hero = os.environ["HERO"]
manifest = "photos.json"
prev, order = {}, []
if os.path.exists(manifest):
    try:
        for e in json.load(open(manifest)).get("photos", []):
            prev[e["file"]] = e; order.append(e["file"])
    except Exception:
        pass
files = sorted(f for f in os.listdir(out) if f.endswith(".webp") and f[:-5] != hero)
def dims(p):
    o = subprocess.check_output(["sips", "-g", "pixelWidth", "-g", "pixelHeight", p]).decode()
    w = h = 0
    for ln in o.splitlines():
        if "pixelWidth"  in ln: w = int(ln.split()[-1])
        if "pixelHeight" in ln: h = int(ln.split()[-1])
    return w, h
ordered = [f for f in order if f in files] + [f for f in files if f not in order]
photos = []
for f in ordered:
    w, h = dims(os.path.join(out, f))
    p = prev.get(f, {})
    photos.append({"file": f, "w": w, "h": h,
                   "caption": p.get("caption", ""),
                   "alt": p.get("alt", p.get("caption", "") or "Photograph of Chuck Garrett")})
json.dump({"photos": photos}, open(manifest, "w"), indent=2, ensure_ascii=False)
open(manifest, "a").write("\n")
print("photos.json: %d entries" % len(photos))
PY

echo "Done. Review photos.json, then: git add -A && git commit && git push"
