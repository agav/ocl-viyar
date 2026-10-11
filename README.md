# OCL Viyar Export

SketchUp extension that works next to [OpenCutList](https://github.com/lairdubois/lairdubois-opencutlist-sketchup-extension)
(tested against v7.1.0). It runs OpenCutList's cutlist generator, takes the sheet-good parts with their
edge banding, adds drillings modeled as nested components, and writes a GibLab XML file (`*.project`)
that ViyarPro imports via **Conversion → GibLab**.

OpenCutList itself is not modified, so it keeps updating normally from the Extension Warehouse.

## Usage

1. Select the furniture to export (or nothing, for the whole model). The selection rules are the same as in OpenCutList.
2. **Extensions → OCL Viyar Export → Export to Viyar (GibLab)...**
3. The export writes three files:
   - `<name>.project`: upload this to viyar.pro → Conversion
   - `<name>.json`: the intermediate data, for debugging
   - `<name>.report.txt`: a summary and warnings (unknown features, skipped parts, ...)

OpenCutList's cutlist options saved in the model (auto orient, flipped detection, ...) are used.

## Panels

- Each panel is a component with an OpenCutList **sheet good** material. Other material types are skipped (listed in the report).
- Panel length is along OpenCutList's length axis, which is also the grain direction and GibLab's `l`.
- Edge banding comes from OpenCutList's edge materials. Band thickness and width come from the edge material's settings.
- The material name is exported as-is. ViyarPro doesn't map GibLab material names or codes, so pick the real material in Viyar after import.

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
| `<preset>` | named fitting from `presets.json` (can contain several holes) | `f_confirmat_face`, `f_minifix_edge` |

- Text after the first space is ignored (comment): `f_d5x11.5 shelf pin`.
- SketchUp's uniqueness suffixes are ignored: `f_d5x11.5#1`, `f_d5x11.5_1`.
- Face vs. edge is always taken from the geometry; `_face` / `_edge` in a preset name is only a label.
- A through hole on a face gets depth = thickness + 2 mm. A depth ≥ thickness also counts as through. Through holes on edges are not supported.
- Edge holes are exported centered in the thickness. A warning is reported if the component is off-center.
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

`dx` / `dy` are mm offsets in the feature component's local X/Y plane.

## Panel coordinate frame

Seen from the **front** face:
- x = along length, from the left edge
- y = along width, from the bottom edge
- origin = bottom-left corner

The front face is the one whose normal is `length × width` (right-handed). Holes on the back face go to a
separate GibLab operation (`side="false"`) and use the same x/y.

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

- Dev install: copy `tools/dev_loader.rb` into SketchUp's `Plugins` folder, restart SketchUp, then use
  **Reload extension (dev)** after edits.
- Build the installable package: `python3 tools/build_rbz.py` → `dist/ocl_viyar_<version>.rbz`.
- `features.rb` and `giblab_writer.rb` are plain Ruby (no SketchUp API). Run their tests with
  `for t in test/test_*.rb; do ruby -w "$t"; done`.
- Write a sample `.project` for a manual ViyarPro import check:
  `OCL_VIYAR_SAMPLE_OUT=/mnt/c/prj/ocl_viyar_writer_test.project ruby test/test_giblab_writer.rb -n test_write_sample_file`

## Not yet supported

Grooves (GibLab `GR` operation), Viyar fitting codes, curved cut-outs, mapping band names to ViyarPro's "customer edges".
