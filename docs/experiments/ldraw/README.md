# LDraw rendering experiment

Isolated research prototype, 2026-11-16. No native app code or inventory data is changed.

## Inspect the result

- [Rendered comparison](renders/comparison.png): eight models, each shown from above and underneath.
- [Research conclusions](../../research/ldraw-rendering.md).
- `results.json`: measured dimensions, triangle counts, material properties, image sizes, timings, and checks.
- `manifest.json`: official source URLs, source headers/authors/licenses, dependency closure, and SHA-256 hashes.

For the rotatable viewer, run from this directory:

```sh
npm ci --ignore-scripts --no-audit --no-fund
npm run preview
```

Open `http://127.0.0.1:8765`. Choose a part, drag to rotate, or switch to the underside. The gallery works from the same local server. Opening `index.html` directly as a file will not work because the viewer loads local models and modules.

## Reproduce

The downloaded geometry and packed models are included, so rendering does not require catalog credentials or network access after dependency installation:

```sh
npm run render
```

This uses a fresh headless Chrome profile and a temporary loopback-only server; it never opens a personal browser profile. It defaults to the macOS Chrome executable. Set `BROWSER_EXECUTABLE` to another installed Chromium executable if necessary. The browser is restricted to local requests. The experiment intentionally uses SwiftShader software rendering; timings are not native iPad performance measurements.

To assemble models from the official library (existing source files are reused):

```sh
python3 fetch_parts.py
```

The downloader follows only bounded, normalized references within the official library, records source hashes, resolves dependencies, and respects rate limits. It rejects missing dependencies, cycles, and texture-mapped parts. The included files form a content-hashed subset downloaded on 2026-11-16, **not an atomic official release snapshot**. A production asset build should pin an entire known release first. Deleting or replacing cached source files changes the experiment's inputs; retain the manifest with any published result.

## What was verified

- All eight specimens load from 40 local geometry files, with no missing geometry or material warnings.
- Brick 2 × 4 bounds: 80 × 28 × 40 LDU, including studs.
- Plate 2 × 4 bounds: 80 × 12 × 40 LDU, including studs.
- Tile 1 × 2 bounds: 40 × 8 × 20 LDU; its groove and underside are present.
- The printed brick retains fixed black and inherited yellow materials.
- Trans-clear retains alpha 128/255; changing color does not change triangle count.
- The actual part picker, underside button, and drag rotation change the model/view successfully.
- Both views of every part are saved at 800 × 600 with transparent backgrounds. The front images are 22,308–79,959 bytes in the recorded run; all 16 individual images total 675,595 bytes. The comparison screenshot is additional.

## Limits and findings

These are manually chosen LDraw specimens. No authenticated Rebrickable API mapping, full-set inventory, or full-library coverage test was performed. The printed model's source header contains `Rebrickable 3001pr0009` although its LDraw filename is `3001p08.dat`; this is direct evidence that names cannot simply be copied between catalogs. That header is a useful mapping lead, not verification of a current API response.

The model geometry is real, but this is not a photorealistic or color-calibrated renderer. Transparent plastic uses simple alpha and needs better contrast/material treatment for the board. Strong highlights on the red slope also need lighting refinement. Camera angle is shared, but framing auto-fits each part: images do not represent a common physical scale. Surface detail such as embossed LEGO logos is not added beyond the supplied models.

Geometry-based prints work in this sample. Texture-mapped prints, glitter/speckle finishes, flexible parts, complex assemblies, and ambiguous catalog mappings are not approved by this experiment. The pinned loader does not implement all of those features. Missing source files must be a failure: an earlier experiment demonstrated that the loader can warn and still return an empty/incomplete scene. The current checks reject that outcome.

Three.js normalizes some subpart paths (`s/` to `parts/s/`). Explicit file-map entries preserve the packed model's virtual filenames and prevent network fallbacks. Keep the source closure validation even when a renderer reports success.

## Sources and attribution

Geometry and material definitions from the [LDraw Parts Library](https://www.ldraw.org/), by the authors recorded in [CREDITS.md](CREDITS.md) and each original file header. All 40 geometry files in this subset state [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The original files are retained without geometry edits; generated MPDs wrap them in a parent color/model declaration. Source URLs and hashes are in `manifest.json`. LDraw is a community library and is not an official LEGO service.

Rendering uses Three.js 0.181.0 ([MIT license](https://github.com/mrdoob/three.js/blob/r181/LICENSE)); automation uses Playwright 1.56.1 ([Apache 2.0](https://github.com/microsoft/playwright/blob/v1.56.1/LICENSE)). Those packages and their licenses are installed through the committed lockfile. See the research note for primary-source links and the distinction between rendered images and redistributed geometry.
