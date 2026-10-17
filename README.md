# OCL Viyar Export

SketchUp extension that works next to [OpenCutList](https://github.com/lairdubois/lairdubois-opencutlist-sketchup-extension)
(tested against v7.1.0). It runs OpenCutList's cutlist generator, takes the sheet-good parts with their
edge banding, adds drillings modeled as nested components, and writes a ViyarPro project file (`*.project`).

Two output formats:
- **ViyarPro project** (default): the format the Bazis2Viyar script (Bazis-Mebelshchik → ViyarPro, v5.10)
  writes. Load it in ViyarPro's order constructor with **Load from file**. This format has native
  operations for grooves, rabbets, corner processing and cut-outs, so new features go here.
- **GibLab XML** (legacy): imported via viyar.pro → **Conversion → GibLab**. Drillings only.

OpenCutList itself is not modified, so it keeps updating normally from the Extension Warehouse.

## Usage

1. Select the furniture to export (or nothing, for the whole model). The selection rules are the same as in OpenCutList.
2. **Extensions → OCL Viyar Export → Export to ViyarPro...** (or **Export to Viyar (GibLab)...**)
3. The export writes:
   - `<name>.project`: the file to load in ViyarPro. A ViyarPro project holds one sheet material, so with
     several materials there is one file per material: `<name>_<material>_<thickness>.project`.
   - `<name>.xml` (ViyarPro format only): the unencrypted project, for checking
   - `<name>.json`: the intermediate data, for debugging
   - `<name>.report.txt`: a summary and warnings (unknown features, skipped parts, ...)

OpenCutList's cutlist options saved in the model (auto orient, flipped detection, ...) are used.

## Panels

- Each panel is a component with an OpenCutList **sheet good** material. Other material types are skipped (listed in the report).
- Panel length is along OpenCutList's length axis, which is also the grain direction and GibLab's `l`.
- Edge banding comes from OpenCutList's edge materials. Band thickness and width come from the edge material's settings.
- ViyarPro format: the Viyar article (code) is the first line of the OpenCutList material **description**
  (Materials → edit material → Description), e.g. `81234`. The same goes for edge-band materials. If the
  description is empty, the name is used like Bazis does: `<name> (Артикул <code>)`. Without either, the
  article is empty (reported) and ViyarPro asks for the material.
- GibLab format: the material name is exported as-is. ViyarPro doesn't map GibLab material names or codes, so pick the real material in Viyar after import.
- Grain: OpenCutList's *grained* material setting gives `grain="1"` (texture along the length) or `"0"`.

## Drillings (surface features)

A drilling is a **component nested directly inside the panel definition**:

- named `f_...` (definition name, or instance name if that one starts with `f_`)
- with the **Cuts opening** behaviour enabled (Component options → Glue to: Any, Cut opening). OpenCutList then doesn't list it as a separate part.
- placed with its **origin on the panel face or edge**, at the hole center. The face is detected from the origin's position. If the origin is ambiguous, the component's Z axis (outward face normal, as gluing sets it) decides.

OpenCutList counts the faces of Cuts-opening components and groups as panel geometry. The export
computes the panel size without `f_`/`g_` subtrees and reports a warning when that differs from
OpenCutList's size, which happens when feature or helper geometry sticks out of the panel.

### Groups of features (`g_`)

A component or group named `g_...` is a container used to place several features together (a hinge
pattern, a drawer-runner set, ...). The export goes into it, at any depth, and collects:
- every `f_...` inside it, exported as separate holes;
- nested `g_...` containers, searched the same way.

Everything else inside a `g_` (helper lines, guide geometry, unnamed components) is ignored.
Components inside a `g_` should also have Cuts opening. Otherwise OpenCutList lists them as parts,
and the report warns about it. Report messages show the path, e.g. `g_hinge / f_d35x12`.

### Names

```
f_<spec>[ <free comment>]
```

| Spec | Meaning | Examples |
|---|---|---|
| `d<D>x<depth>` | one hole, diameter × depth in mm (`.` or `,` as decimal) | `f_d5x11.5`, `f_d35x12`, `f_d8x33` |
| `d<D>xF` | through hole | `f_d7xF` |
| `d<D>x<depth>c`, `d<D>xFc` | confirmat hole with countersink (ViyarPro `subtype="48"`) | `f_d7xFc` |
| `<preset>` | named fitting from `presets.json` (can contain several holes) | `f_confirmat_face`, `f_minifix_edge` |

- Text after the first space is ignored (comment): `f_d5x11.5 shelf pin`.
- SketchUp's uniqueness suffixes are ignored: `f_d5x11.5#1`, `f_d5x11.5_1`.
- Face vs. edge is always taken from the geometry; `_face` / `_edge` in a preset name is only a label.
- A through hole on a face gets depth = thickness + 5 mm (ViyarPro format, like Bazis2Viyar) or + 2 mm (GibLab). A depth ≥ thickness also counts as through. Through holes on edges are not supported.
- ViyarPro format: a countersunk hole (`c` suffix, or `"countersink": true` in a preset hole) is exported as
  `subtype="48"`. A 7.1 mm hole is also exported as a 7 mm countersunk hole, the Bazis2Viyar convention.
  The GibLab export ignores countersinks.
- Edge holes keep their position across the thickness in the ViyarPro format. GibLab exports them centered; a warning is reported if the component is off-center.
- Mirrored (flipped) panel instances: holes move to the opposite face.

### Presets

`src/ocl_viyar/presets.json`, overridable per project by a `viyar_presets.json` next to the `.skp`:

```json
{
  "confirmat_face": [ { "d": 7, "depth": "F" } ],
  "hinge_cup":      [ { "d": 35, "depth": 12 },
                      { "d": 8, "depth": 11, "dx": -22.5, "dy": 9.5 },
                      { "d": 8, "depth": 11, "dx": 22.5,  "dy": 9.5 } ]
}
```

`dx` / `dy` are mm offsets in the feature component's local X/Y plane. `"countersink": true` marks a confirmat
hole with countersink.

## Grooves and rabbets (push/pull)

Grooves are modeled in the panel's own geometry with push/pull (ViyarPro format only; the GibLab
export reports them as not exported). Every rectangular recess has a **floor**: a flat face parallel
to a panel face or an edge, inside the panel. The floor gives the removed box, which is classified like
Bazis2Viyar does:

| Recess | ViyarPro operation |
|---|---|
| open to the front/back face, not reaching the edge it runs along | `grooving` (паз), `side` 1/6 |
| open to the front/back face and reaching that edge | `rabbeting` (четверть), `edge` 2–5 |
| open to an edge face only (slot in the edge) | `grooving` in the edge, `side` 2–5 |

- A recess runs along y if it is longer in y, otherwise along x. A through groove simply spans the panel.
- A floor split by drawn lines is joined back into one recess.
- Not exported (reported): non-rectangular floors (L-shapes, crossing grooves, curved ends), recesses
  through the whole thickness, edge slots reaching two edges.
- Groups and Cuts-opening components inside the panel count as panel geometry; `f_`/`g_` subtrees don't.

## Panel coordinate frame

Seen from the **front** face:
- x = along length, from the left edge
- y = along width, from the bottom edge
- origin = bottom-left corner

The front face is the one whose normal is `length × width` (right-handed). Holes on the back face go to a
separate GibLab operation (`side="false"`) and use the same x/y.

## ViyarPro project format (from Bazis2Viyar 5.10, not yet verified with this plugin's output)

The file is SJCL JSON (`sjcl.encrypt` defaults: PBKDF2-SHA256 10000 iterations, AES-128-CCM, 64-bit tag)
with Bazis2Viyar's fixed password. Decrypted, it is XML:

```xml
<project currency="" version="1" ...>
<viyar version="27">
  <creator id="Bazis2Viyar" version="5.10" .../> <constructor id="dsp" site=""/>
  <materials>
    <material id="1" type="sheet" article="81234" name="..." width="3000" height="3000" thickness="18"/>
    <material id="2" type="band" article="..." name="..." height="22" thickness="1"/>
  </materials>
  <details>
    <detail id="1" material="1" amount="2" widthFull="600.0" heightFull="400.0" multiplicity="1" grain="1" description="A.side" ...>
      <edges><left type="kromka" param="2" drop="0"/> <top .../> <right type="" param="" .../> <bottom .../></edges>
      <operations>
        <operation id="1" type="drilling" side="1" x="120.0" y="130.0" xo="120.0" yo="130.0" xl="0" yl="0" d="5" depth="5.0"/>
      </operations>
    </detail>
  </details>
</viyar>
</project>
```

| Hole on | `side` | `x` | `y` |
|---|---|---|---|
| front face | 1 | x | y |
| left edge (x = 0) | 2 | distance from front face | y |
| top edge (y = width) | 3 | x | distance from front face |
| right edge (x = length) | 4 | distance from front face | y |
| bottom edge (y = 0) | 5 | x | distance from front face |
| back face | 6 | x | y (front view, like Bazis) |

Other operation types Bazis2Viyar writes, for future features: `grooving`, `rabbeting`, `cornerOperation`
(radius / chamfer / cutout corners), `shapeByPattern` (U-shape, rectangle, circle, arc, smile cut-outs),
`clipping` (parts under 70 mm), and edge types `srez` / `srezkrom` (edge bevels).

## GibLab XML mapping (verified on ViyarPro import, Oct 2026)

| Panel side | Edge band attribute | Edge-hole tag | Hole coordinate |
|---|---|---|---|
| bottom (y = 0) | `elb` | `bt` | `x` |
| top (y = width) | `elt` | `bb` (assumed) | `x` |
| left (x = 0) | `ell` | `bl` | `y` |
| right (x = length) | `elr` | `br` | `y` |
| front face | – | `bf`, XNC `side="true"` | `x`, `y` |
| back face | – | `bf`, XNC `side="false"` | `x`, `y` (orientation to verify) |

- All XNC operations: `mirVert="true"` (bottom-left origin), `bySizeDetail="true"` (finished-size coordinates).
- Part sizes: `dl`/`dw` = finished, `l`/`w`/`cl`/`cw`/`jl`/`jw` = finished minus band thicknesses.
- Coordinates are written as plain numbers. ViyarPro treats a GibLab expression like `dy-32` as "32 from the top".
- Material codes (`$NNNNN`, a `code` attribute, ...) are not recognized by ViyarPro's GibLab import.

## Development

- The ViyarPro format comes from reverse engineering Viyar's Bazis2Viyar script; see
  [docs/bazis2viyar.md](docs/bazis2viyar.md) for how, and for the steps when a new version appears.

- Dev install: copy `tools/dev_loader.rb` into SketchUp's `Plugins` folder, restart SketchUp, then use
  **Reload extension (dev)** after edits.
- Build the installable package: `python3 tools/build_rbz.py` → `dist/ocl_viyar_<version>.rbz`.
- `features.rb`, `grooves.rb`, `sjcl.rb`, `viyar_writer.rb` and `giblab_writer.rb` are plain Ruby (no SketchUp API). Run their tests with
  `for t in test/test_*.rb; do ruby -w "$t"; done`.
- Write a sample `.project` for a manual ViyarPro import check:
  `OCL_VIYAR_SAMPLE_OUT=/mnt/c/prj/ocl_viyar_test.project ruby test/test_viyar_writer.rb -n test_write_sample_project`
  (GibLab: `ruby test/test_giblab_writer.rb -n test_write_sample_file`)

## Not yet supported

Corner processing, cut-outs, clipping of parts under 70 mm, edge bevels, fittings (`products`), groove
`closed` flag and rounded groove corners (`radius`).
