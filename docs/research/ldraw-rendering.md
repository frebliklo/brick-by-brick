# LDraw rendering investigation

Research date: 2026-11-16. Scope: investigate accurate pictures for the native SwiftUI brick board; no production renderer change is proposed as already completed.

## Recommendation

Start with a reproducible pipeline that renders verified LDraw part/color combinations to PNG. Keep ordinary cached images in the scrolling board. Explore interactive rotation separately, as a detail view for difficult parts. This separates the useful immediate improvement—consistent pictures derived from actual geometry—from an on-device CAD loader, geometry conversion, materials, and rendering lifecycle.

The hard correctness boundary is **catalog identity → verified geometry and material**, not whether a 3D renderer can draw a brick. Rendering a correctly loaded but incorrectly mapped model still gives a persuasive wrong answer.

## What the sources establish

### Catalog identity and mapping

Rebrickable's official v3 changelog documents `external_ids`, detailed part fields via `inc_part_details`, and `print_of`. Since July 2025, `print_of` is omitted from default part list/search results unless detailed fields are requested. Inventory image URLs already represent the inventory color. These make Rebrickable the appropriate source for inventory identity and the existing photo fallback. [Rebrickable v3 documentation](https://rebrickable.com/api/v3/docs/)

The intended mapping input is the exact Rebrickable part ID plus color ID, supplemented by its LDraw external IDs. **Live authenticated responses and the exact current mapping schema have not been verified in this investigation.** Direct documentation retrieval was blocked; the official documentation's indexed changelog was available. Before implementation, capture sanitized fixtures from the user's authorized catalog connection, including no mapping and multiple mappings. Do not choose the first candidate blindly.

LDraw explicitly uses its own numbering scheme for printed patterns. Its numbering specification also distinguishes mould variants, assemblies, stickers, and flexible configurations. Consequently, replacing a Rebrickable suffix, dropping it, or assuming `partNum + ".dat"` always works is unsafe. [LDraw part numbering](https://www.ldraw.org/part-number-spec.html)

For the initial fixture, manually verify each mapping against the part title and reference view. For production, record mapping provenance, candidate IDs, chosen filename, and review status. Treat `print_of` as a relationship, not permission to substitute an undecorated part.

### Shape and dependencies

LDraw files encode geometry and transformed subfile references. A top-level file often requires subparts and primitives; downloading just that file is insufficient. The coordinate system uses negative Y as up. A standard brick height is 24 LDU and a plate height is 8 LDU; stud spacing is 20 LDU. These provide useful dimensional checks. [LDraw format specification](https://www.ldraw.org/article/218.html)

The actual official `3001.dat` identifies a 2 × 4 brick and references `s/3001s01.dat`; it is an immediately inspectable example of this dependency structure. [Official 3001 source](https://library.ldraw.org/library/official/parts/3001.dat)

Resolve a complete dependency closure from one pinned library snapshot. Record checksums. Normalize LDraw filename separators, handle filename case consistently, and prevent path traversal outside the library. Reject missing dependencies, cycles, and unsupported required constructs rather than accepting an incomplete-looking success.

### Color and finish

`LDConfig.ldr` supplies the official material definitions. LDraw material descriptions include RGB, contrasting edges, alpha, luminance, and finishes such as rubber, chrome, pearl, and glitter. RGB alone cannot distinguish opaque and transparent versions. Standard transparent definitions normally specify alpha 128. [Color reference](https://ldraw.org/article/547.html), [color extension](https://ldraw.org/article/299.html)

Use an explicit Rebrickable-color-to-LDraw-material mapping, validated separately from part mapping. The practice inventory's friendly names and custom RGB values are demonstration values, not evidence of a catalog material match. Preserve fixed colors in printed or composite models; replace only inherited main color and its associated edges. LDraw uses 16 for inherited face color and 24 for inherited edge color. [Three.js material handling](https://threejs.org/docs/pages/LDrawLoader.html)

Lighting, tone mapping, background, and the display still affect perceived color. The renderer needs stable settings and visual comparison of nearby colors. Avoid claiming colorimetric matching from an RGB value.

## Rendering choices

| Approach | Suitability for this app | Remaining work |
| --- | --- | --- |
| Pre-render PNGs from LDraw | Recommended first: compatible with the current image-based board, deterministic appearance, cacheable offline | Build a verified manifest, rendering job, persistent image cache, and fallback policy |
| Three.js viewer in a separate experiment or embedded web view | Fast route to exploring rotation and alternate views | Validate browser/device performance, package dependencies, and account for unsupported features |
| Converted meshes in native RealityKit | Candidate for a later native rotating detail view | Convert to supported assets, preserve materials and hierarchy, verify deployment-target APIs and iPad behavior |

Three.js has an official `LDrawLoader`, a configurable library path, material preloading, conditional-edge support, and tooling advice for packing dependencies to reduce requests. It is a useful experiment foundation. Pin a release instead of loading an unversioned development build. [Loader documentation](https://threejs.org/docs/pages/LDrawLoader.html)

There are feature gaps: the inspected development source explicitly says glitter/speckle `MATERIAL` tags are not implemented, and no `TEXMAP` parser was found. Treat texture-mapped decoration as unsupported until the pinned renderer is tested. The loader can also warn and substitute a missing-color material; warnings must be promoted to failures for approved asset generation. [Three.js loader source, inspected 2026-11-16](https://raw.githubusercontent.com/mrdoob/three.js/dev/examples/jsm/loaders/LDrawLoader.js)

Apple recommends RealityKit for new long-term 3D work and describes SceneKit as soft-deprecated. RealityKit's documented file loading supports USD-family and Reality assets, so LDraw would require conversion or custom mesh construction. The app currently targets iOS 17; choosing a newer SwiftUI 3D container requires separate availability checking. [Apple migration guidance](https://developer.apple.com/documentation/RealityKit/bringing-your-scenekit-projects-to-realitykit), [supported asset formats](https://developer.apple.com/documentation/realitykit/entity/load(contentsof:withname:))

## Approval criteria for a rendered asset

These are proposed engineering checks, not completed verification:

1. Exact part and color mapping has an explicit provenance record. Printed and mould variants retain their identity.
2. Every model, primitive, texture, and material dependency resolves from the pinned snapshot; unsupported required features reject the render.
3. Geometry has finite bounds and nonzero visible content. Known simple parts pass dimension and stud-layout checks.
4. A standard three-quarter view shows the distinguishing feature; selected underside/side views expose grooves, tubes, holes, or clip orientation. Keep per-part camera overrides where necessary.
5. The render is reviewed beside a trusted catalog image or physical part, including at the actual board display size. A successful load alone does not prove correctness.
6. A failed or unreviewed render uses the exact catalog photo; if that is unavailable, show the existing explicit unavailable-picture state.

Start with the five practice shapes, then add difficult cases: grooved versus smooth tiles, two similar slopes, Technic pin/axle holes, opposing clips, an asymmetric part, a geometry-based print, a texture-mapped print, transparent parts, white/black, and a special finish. Include intentionally missing mappings and dependencies. This is a coverage sample, not a percentage claim about the full library.

Cache by exact catalog part/color plus mapping revision, top-level filename, dependency-content hash, `LDConfig` hash, renderer version, camera/lighting recipe, image dimensions, and output color space. An asset manifest should retain original source URLs, licenses, and validation outcome. Generate only required combinations; avoid shipping the entire parts library to each iPad by default.

## Licensing and attribution

The current contributor agreement permits CC BY 4.0 or CC0. Individual file headers carry license information: the inspected `3001.dat` says CC BY 4.0. Preserve headers and relevant license files for any distributed source or converted geometry. [Contributor agreement](https://library.ldraw.org/documentation/licenses-and-legal/ldraworg-contributor-agreement), [3001 header](https://library.ldraw.org/library/official/parts/3001.dat)

LDraw's published policy distinguishes 2D rendered images from converted geometry: it says rendered images are not treated as derivative works of the part library, while converted geometry is. That policy page includes historical CC BY 2.0 wording, so it should not replace checking the actual snapshot's licenses. Include “Geometry from the LDraw Parts Library” credit and a link in either approach. [LDraw legal information](https://www.ldraw.org/docs-main/licenses/legal-info.html)

## Experiment results — completed 2026-11-16

The isolated [reproducible experiment](../experiments/ldraw/README.md) uses **Three.js 0.181.0**, Playwright 1.56.1, and headless Chrome 157.0.8103.52 with SwiftShader. [View the comparison sheet](../experiments/ldraw/renders/comparison.png). No native app code was changed.

Eight part/color examples were rendered from **40 complete official geometry files** (59,113 bytes of source geometry, plus 67,579 bytes of `LDConfig.ldr`): yellow 3001, white 3003, green 3020, red 3039, blue 3069b, red Technic 3700, yellow printed 3001p08, and trans-clear 3001. Each has a three-quarter and underside PNG at 800 × 600. Front PNGs are **22–80 kB**; all 16 individual PNGs total **675,595 bytes**. The comparison sheet is additional. Inputs and material definitions are SHA-256 recorded in [manifest.json](../experiments/ldraw/manifest.json). This is a checksum-pinned subset fetched from the live library, not an atomic library release snapshot.

Checks passed for nonempty finite geometry; expected brick/plate/tile dimensions; preserved fixed print and parent colors; preserved transparent material; identical topology for two colors of 3001; and absence of missing geometry/material warnings. The actual picker, underside button, and drag rotation were also exercised. [results.json](../experiments/ldraw/results.json) contains the measurements. Recorded load/setup times mix warm and cold model cache states, and export times include GPU readback and PNG encoding; these are diagnostic observations, **not an iPad performance benchmark**.

Visual inspection confirms recognizable studs, underside tubes, tile groove, Technic hole, slope, and fixed printed decoration. White remains legible. Transparent geometry is present, but simple alpha rendering is too faint for confident child-facing matching; background/material treatment needs refinement. The red slope also shows a strong pale highlight. A production lighting recipe needs comparison against trusted reference images. Auto-fit framing means parts are not displayed at a common physical scale.

The printed source itself declares `Rebrickable 3001pr0009` in its keywords although the LDraw file is `3001p08.dat`. This establishes a concrete cross-catalog ID difference and provides a candidate mapping from LDraw metadata; no live Rebrickable response has verified it. [Printed part source](https://library.ldraw.org/library/official/parts/3001p08.dat)

One observed failure is particularly relevant: the loader warned about a missing packed subpart and still returned an empty scene. The experiment now rejects that result and supplies an explicit file map to avoid `s/` path rewriting. Full dependency checks are necessary even when rendering callbacks complete successfully.

**Next recommended experiment:** run one real set inventory through explicit Rebrickable part/color external-ID mappings, record every resolved, ambiguous, unsupported, and unmapped entry, and review renders against the inventory photos at board size. Only approved renders should replace the current photos. Texture-mapped prints, special finishes, broader mapping coverage, reference-image fidelity, and native iPad runtime behavior remain unverified.
