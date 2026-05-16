#!/usr/bin/env bash
set -euo pipefail

# Build a Miro-importable icon pack from cncf/artwork.
# Output: dist/cncf-icons-miro.zip (containing one optimized SVG per active CNCF project).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTWORK_DIR="$ROOT/artwork"
DIST_DIR="$ROOT/dist"
OUT_DIR="$DIST_DIR/cncf-icons"
ZIP_PATH="$DIST_DIR/cncf-icons-miro.zip"
MAX_BYTES=51200   # Miro custom-shape upload fails on files larger than ~50 KB
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
mkdir -p "$OUT_DIR"

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

  cp "$src" "$OUT_DIR/${project}.svg"
  picked=$((picked + 1))
done

echo ">> Picked $picked SVGs (skipped $skipped projects)"

echo ">> Optimizing with SVGO"
npx -y svgo@3 --multipass -q -f "$OUT_DIR"

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
' "$OUT_DIR"

echo ">> Shrinking oversized SVGs (Miro rejects > ~50 KB)"
filesize() { wc -c < "$1" | tr -d ' '; }

# First pass: aggressive SVGO (floatPrecision=1, no readable formatting) on
# anything still over the limit after the default pass.
aggressive_cfg="$(mktemp -t svgo-aggressive.XXXXXX).js"
cat > "$aggressive_cfg" <<'EOF'
module.exports = {
  multipass: true,
  floatPrecision: 1,
  plugins: [
    { name: 'preset-default',
      params: { overrides: {
        cleanupNumericValues: { floatPrecision: 1 },
        convertPathData:      { floatPrecision: 1, transformPrecision: 1 },
        convertTransform:     { floatPrecision: 1, transformPrecision: 1 },
      } } },
  ],
};
EOF
oversized=()
for f in "$OUT_DIR"/*.svg; do
  if [ "$(filesize "$f")" -gt "$MAX_BYTES" ]; then oversized+=("$f"); fi
done
if [ ${#oversized[@]} -gt 0 ]; then
  echo "   aggressive SVGO on ${#oversized[@]} file(s)"
  npx -y svgo@3 -q --config "$aggressive_cfg" "${oversized[@]}"
fi

# Second pass: anything still oversized (typically SVGs that embed a raster
# image or have impractically detailed path data) — rasterize at 256 px and
# wrap the PNG in a thin SVG. Lossy but guarantees the size budget.
still_oversized=()
for f in "$OUT_DIR"/*.svg; do
  if [ "$(filesize "$f")" -gt "$MAX_BYTES" ]; then still_oversized+=("$f"); fi
done
if [ ${#still_oversized[@]} -gt 0 ]; then
  echo "   rasterizing ${#still_oversized[@]} file(s) at 256 px"
  sharp_tmp="$(mktemp -d -t sharp.XXXXXX)"
  ( cd "$sharp_tmp" && npm install --silent --no-save --no-audit --no-fund sharp@0.33 )
  NODE_PATH="$sharp_tmp/node_modules" MAX_BYTES="$MAX_BYTES" node -e '
const sharp = require("sharp");
const fs = require("fs");
const max = parseInt(process.env.MAX_BYTES, 10);
const wrap = (w, h, b64) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}"><image href="data:image/png;base64,${b64}" width="${w}" height="${h}"/></svg>`;
(async () => {
  // Try size + palette/colour combinations in descending quality until one
  // fits under MAX_BYTES. Order matters — best quality first.
  const attempts = [
    { size: 256, palette: false },
    { size: 256, palette: true,  colours: 128 },
    { size: 256, palette: true,  colours: 64  },
    { size: 192, palette: true,  colours: 64  },
    { size: 160, palette: true,  colours: 64  },
    { size: 128, palette: true,  colours: 64  },
    { size: 128, palette: true,  colours: 32  },
  ];
  for (const f of process.argv.slice(1)) {
    const meta = await sharp(f).metadata();
    const aspect = (meta.width || 1) / (meta.height || 1);
    let pickedSvg = null, pickedW, pickedH, pickedAttempt;
    for (const a of attempts) {
      let w = a.size, h = a.size;
      if (aspect > 1) h = Math.max(1, Math.round(a.size / aspect));
      else if (aspect < 1) w = Math.max(1, Math.round(a.size * aspect));
      const pngOpts = { compressionLevel: 9 };
      if (a.palette) { pngOpts.palette = true; pngOpts.colours = a.colours; }
      const buf = await sharp(f).resize(w, h, { fit: "fill" }).png(pngOpts).toBuffer();
      const svg = wrap(w, h, buf.toString("base64"));
      if (svg.length <= max) {
        pickedSvg = svg; pickedW = w; pickedH = h; pickedAttempt = a;
        break;
      }
    }
    if (!pickedSvg) {
      // Worst case: keep the smallest attempt anyway so the icon ships, just
      // with a warning. Better a slightly oversized icon than no icon.
      const a = attempts[attempts.length - 1];
      let w = a.size, h = a.size;
      if (aspect > 1) h = Math.max(1, Math.round(a.size / aspect));
      else if (aspect < 1) w = Math.max(1, Math.round(a.size * aspect));
      const buf = await sharp(f).resize(w, h, { fit: "fill" }).png({ palette: true, colours: a.colours, compressionLevel: 9 }).toBuffer();
      pickedSvg = wrap(w, h, buf.toString("base64"));
      pickedW = w; pickedH = h; pickedAttempt = a;
    }
    fs.writeFileSync(f, pickedSvg);
    const tag = pickedAttempt.palette ? `palette-${pickedAttempt.colours}` : "rgba";
    console.log(`     ${f.split("/").pop()}: ${pickedW}x${pickedH} ${tag}, ${(pickedSvg.length / 1024).toFixed(1)} KB`);
  }
})();
' "${still_oversized[@]}"
  rm -rf "$sharp_tmp"
fi

# Final safety check
remaining=()
for f in "$OUT_DIR"/*.svg; do
  if [ "$(filesize "$f")" -gt "$MAX_BYTES" ]; then remaining+=("$f"); fi
done
if [ ${#remaining[@]} -gt 0 ]; then
  echo "   WARNING: ${#remaining[@]} file(s) still over 50 KB:"
  printf '     %s\n' "${remaining[@]}"
fi

echo ">> Checking for foreignObject (Miro rejects it)"
if grep -l '<foreignObject' "$OUT_DIR"/*.svg >/dev/null 2>&1; then
  echo "   WARNING: the following SVGs contain <foreignObject> and may not render in Miro:"
  grep -l '<foreignObject' "$OUT_DIR"/*.svg | sed 's/^/     /'
fi

cat > "$DIST_DIR/SOURCE.txt" <<EOF
Built from https://github.com/cncf/artwork @ $SOURCE_SHA
Build date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Icons included: $picked
EOF
cp "$DIST_DIR/SOURCE.txt" "$OUT_DIR/SOURCE.txt"

echo ">> Zipping"
rm -f "$ZIP_PATH"
( cd "$DIST_DIR" && zip -qr "$(basename "$ZIP_PATH")" cncf-icons/ )

size="$(du -h "$ZIP_PATH" | awk '{print $1}')"
echo ">> Done: $ZIP_PATH ($picked icons, $size)"
