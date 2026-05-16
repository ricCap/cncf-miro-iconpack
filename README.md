# cncf-miro-iconpack

Pipeline that builds a [Miro Custom Shape pack](https://help.miro.com/hc/en-us/articles/20352896814866-Custom-Shapes-for-Diagramming) from [cncf/artwork](https://github.com/cncf/artwork) on demand. The output is a zip of one optimized SVG per active CNCF project, ready to upload to a Miro board for diagramming.

The zip itself is never committed — it's published as a GitHub Release asset.

## Release a new pack

1. Go to the **Actions** tab → **Release pack** → **Run workflow**.
2. Wait ~2 minutes for the job to finish.
3. Find the zip on the newly created Release under the **Releases** page (`cncf-icons-miro.zip`).

The release tag is `pack-<UTC date>-<HHMM>`. The release body lists the upstream `cncf/artwork` commit the pack was built from.

## Use the pack in Miro

Requires a Miro **Education / Business / Enterprise** plan (Custom Shapes is gated).

1. Download `cncf-icons-miro.zip` from the Release and unzip it. You'll get a `svg/` folder with ~200 SVGs.
2. Open a Miro board → **Shapes** panel → **Custom Shapes** → **Browse and upload shapes**.
3. Multi-select every SVG in `svg/` (Cmd/Ctrl+A in the file picker) and upload.

The shape label in Miro's picker is the filename — so `kubernetes.svg` shows up as "kubernetes".

## Local development

The workflow just calls `scripts/build-pack.sh`. You can run the same script locally to debug:

```sh
bash scripts/build-pack.sh
```

Requirements: `git`, `node` (for `npx svgo`), `zip`. Output lands in `dist/` (gitignored).

## Trademark

CNCF project logos are trademarks governed by the [Linux Foundation Trademark Usage policy](https://www.linuxfoundation.org/trademark-usage). This pack is intended for diagramming, not for branding or marketing materials.
