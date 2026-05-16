#!/usr/bin/env bash
set -euo pipefail

# Build a Miro-importable icon pack from cncf/artwork.
# Output: dist/cncf-icons-miro.zip (containing one optimized SVG per active CNCF project).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTWORK_DIR="$ROOT/artwork"
DIST_DIR="$ROOT/dist"
SVG_DIR="$DIST_DIR/svg"
ZIP_PATH="$DIST_DIR/cncf-icons-miro.zip"
UPSTREAM="https://github.com/cncf/artwork.git"

echo ">> Syncing $UPSTREAM"
if [ -d "$ARTWORK_DIR/.git" ]; then
  git -C "$ARTWORK_DIR" fetch --depth=1 origin main
  git -C "$ARTWORK_DIR" reset --hard origin/main
else
  rm -rf "$ARTWORK_DIR"
  git clone --depth=1 "$UPSTREAM" "$ARTWORK_DIR"
fi
SOURCE_SHA="$(git -C "$ARTWORK_DIR" rev-parse HEAD)"

rm -rf "$DIST_DIR"
mkdir -p "$SVG_DIR"

# Filenames matching these patterns are skipped as non-default color variants
# (e.g. -reversed.svg, -light.svg, colordark.svg). Boundary-anchored so "hyperlight"
# is not accidentally caught by "light".
EXCLUDE_RE='(color)?(-|_)?(reversed|light|dark|black|white)\.svg$'

picked=0
skipped=0
for proj_dir in "$ARTWORK_DIR"/projects/*/; do
  project="$(basename "$proj_dir")"
  color_dir="${proj_dir}icon/color"
  if [ ! -d "$color_dir" ]; then
    echo "   skip: $project (no icon/color/ folder)"
    skipped=$((skipped + 1))
    continue
  fi

  # Preferred: a *-icon-color*.svg without an excluded suffix.
  src=""
  while IFS= read -r f; do
    base="$(basename "$f")"
    if [[ "$base" == *icon*color*.svg ]] && ! [[ "$base" =~ $EXCLUDE_RE ]]; then
      src="$f"
      break
    fi
  done < <(find "$color_dir" -maxdepth 1 -type f -name '*.svg' | sort)

  # Fallback: first .svg in the folder without an excluded suffix.
  if [ -z "$src" ]; then
    while IFS= read -r f; do
      base="$(basename "$f")"
      if ! [[ "$base" =~ $EXCLUDE_RE ]]; then
        src="$f"
        break
      fi
    done < <(find "$color_dir" -maxdepth 1 -type f -name '*.svg' | sort)
  fi

  if [ -z "$src" ]; then
    echo "   skip: $project (no usable SVG in icon/color/)"
    skipped=$((skipped + 1))
    continue
  fi

  cp "$src" "$SVG_DIR/${project}.svg"
  picked=$((picked + 1))
done

echo ">> Picked $picked SVGs (skipped $skipped projects)"

echo ">> Optimizing with SVGO"
npx -y svgo@3 --multipass -q -f "$SVG_DIR"

echo ">> Backfilling viewBox where missing"
node -e '
const fs = require("fs"), path = require("path");
const dir = process.argv[1];
let fixed = 0;
for (const f of fs.readdirSync(dir).filter(x => x.endsWith(".svg"))) {
  const p = path.join(dir, f);
  let s = fs.readFileSync(p, "utf8");
  if (/<svg[^>]*\sviewBox=/.test(s)) continue;
  const w = s.match(/<svg[^>]*\swidth="([\d.]+)"/);
  const h = s.match(/<svg[^>]*\sheight="([\d.]+)"/);
  if (!w || !h) continue;
  s = s.replace(/<svg/, `<svg viewBox="0 0 ${w[1]} ${h[1]}"`);
  fs.writeFileSync(p, s);
  fixed++;
}
console.log(`   backfilled ${fixed} files`);
' "$SVG_DIR"

echo ">> Checking for foreignObject (Miro rejects it)"
if grep -l '<foreignObject' "$SVG_DIR"/*.svg >/dev/null 2>&1; then
  echo "   WARNING: the following SVGs contain <foreignObject> and may not render in Miro:"
  grep -l '<foreignObject' "$SVG_DIR"/*.svg | sed 's/^/     /'
fi

cat > "$DIST_DIR/SOURCE.txt" <<EOF
Built from https://github.com/cncf/artwork @ $SOURCE_SHA
Build date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Icons included: $picked
EOF
cp "$DIST_DIR/SOURCE.txt" "$SVG_DIR/SOURCE.txt"

echo ">> Zipping"
rm -f "$ZIP_PATH"
( cd "$DIST_DIR" && zip -qr "$(basename "$ZIP_PATH")" svg/ )

size="$(du -h "$ZIP_PATH" | awk '{print $1}')"
echo ">> Done: $ZIP_PATH ($picked icons, $size)"
