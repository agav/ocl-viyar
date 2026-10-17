# ViyarPro format: reverse engineering Bazis2Viyar

ViyarPro has no published format for its order constructor's `*.project` files. The format this
plugin writes (`ViyarWriter`) was taken from **Bazis2Viyar**, Viyar's own export script for
Bazis-Mebelshchik. This document records how it was taken apart, where each piece of our code
comes from, and what to do when a new Bazis2Viyar version comes out.

Analyzed version: **Bazis2Viyar 5.10** (script dated 2024-02-03, Bazis-Mebelshchik 8 – 2021).

## 1. Getting the installer

| Source | Status (Oct 2026) |
|---|---|
| viyar.pro docs, `http://vp.viyar.ua/service/doc/?cid=dsp&s=import-export` | links `https://viyar.ua/downloads/files/SetupBazisViyar5.3.exe` (older 5.3), which now returns an HTML page instead of the file |
| [dismebel.com article](https://dismebel.com/eksportirovat-detali-iz-bazis-mebelshhik-v-viyarpro.html) | Google Drive link `16BH7XUdGtRSfjKKTcEep4glnG34lvx0R`, a RAR with `SetupBazisViyar5.10.exe` |

```sh
curl -L -o b2v.rar "https://drive.usercontent.google.com/download?id=16BH7XUdGtRSfjKKTcEep4glnG34lvx0R&export=download&confirm=t"
```

Check `file` on what you download: viyar.ua serves an HTML page with status 200 for missing files.

SHA-256 of the analyzed files:

| File | SHA-256 |
|---|---|
| RAR from Google Drive | `c9825d1cffdc6d85263abf94ce78585f75ee8c55f0db31240a06b7cf599684cb` |
| `SetupBazisViyar5.10.exe` | `7b0e2cbcfd8bd1783b98eb605b08db6579fc0fbdaef25e633412ca444587d278` |
| `Экспорт проекта ViyarPro.js` (as installed, wrapped) | `c6c4633702e394b9d2e730db521fb76d756b8c15746bb3fee22b125463fc9655` |
| decoded source (`decode.py` output) | `6905ad752f5cf2a280753ad8e912dfe2bb673ddbe0b37b109ed0941177efc52a` |
| `ObjTree.js` | `565063990b05e3822c339d81cc9fac006010b7fd9d19436092fc400d4b405e11` |

## 2. Unpacking (without running the installer)

The installer is **Inno Setup 5.5.7 (unicode)**. 7-Zip opens the RAR but not the installer; use
[innoextract](https://github.com/dscharrer/innoextract) (1.9 has a static Linux build).

```sh
"/mnt/c/Program Files/7-Zip/7z.exe" x b2v.rar                  # -> SetupBazisViyar5.10.exe
innoextract -e -d out SetupBazisViyar5.10.exe
```

There is no program inside. The installer only copies, for every Bazis version from 8 to 2021
(normal, DEMO, Online), into `Documents\Bazis<ver>\Scripts\Импорт-экспорт\`:

- `Экспорт проекта ViyarPro.js`: the converter (≈260 KB)
- `ObjTree.js`: XML.ObjTree 2006, a JS object ↔ XML serializer (plain source)
- `app/Help/Руководство.pdf`: user manual

## 3. Decoding the script

The script looks encrypted but is only wrapped:

```js
"use strict";
if (system.secureExecBytes == null) { system.secureExec("AQAA/wF4nO..." + ...); }
else { system.secureExecBytes([1,0,0,255,1,120,156, ...]); }      // same payload as bytes
```

Payload: base64 → 5-byte header `01 00 00 ff 01` → **zlib** (`78 9c`) → a binary record whose last
field is the source as **UTF-16LE**, preceded by its length in characters (uint32 LE).

```sh
python3 -I tools/bazis2viyar/decode.py "out/userdocs/Bazis/Scripts/Импорт-экспорт/Экспорт проекта ViyarPro.js" decoded.js
```

It prints the line count and `SCRIPT_VERSION`. If it fails on the header, Bazis changed the wrapping;
dump the first bytes after base64 decoding and look for a zlib header again.

Keep the decoded source outside the repository: it is Viyar's code. Store it as
`bazis2viyar-<version>.js` somewhere local, so the next version can be diffed against it.

## 4. What the script does

Line numbers are for the decoded 5.10 source.

| Lines | Part | Notes |
|---|---|---|
| 2–50 | SJCL (Stanford JS Crypto Library), minified | used for the output encryption |
| 52–55 | version guard | `system.apiVersion >= 2274` (newer than Bazis 2021) refuses to run |
| 56–200 | constants | `SCRIPT_VERSION`, `PASSWORD`, `VIYAR_*` side/edge/operation codes, thresholds |
| 221 `Panel` | reads a Bazis panel | size from the ordered contour, edge bands per side, holes from all fasteners converted into panel coordinates, cuts |
| 621 `GlobalHole`, 634 `Hole` | holes | 7.1 mm → 7 mm confirmat with countersink |
| 957 `Butt`, 1018 `Material` | edge band, sheet material | name/article split, `сращ.(2)/(3)` laminated panels |
| 1172 `exportViyarPro` | main | validate → read model → `createDocNode` → ObjTree XML → `sjcl.encrypt(PASSWORD, xml)` → write `.project` + `.txt` report |
| 1294 `readModel` | collects fittings (`products`), holes, panels | identical panels merged into `amount` (also mirrored / rotated copies) |
| 1555 `splitNameCode` | article from `"<name> (Артикул <code>)"` or the 2nd line of the name | |
| 1869 `createDocNode` | **the output format**, see section 5 | |
| 2432, 2682 `standardize*Cont` | recognize contour shapes | corners (radius, chamfer, cutouts), arcs, "smiles", rectangle/circle cut-outs → `cornerOperation` / `shapeByPattern` |
| 4074 `ViyarClipping` | parts narrower than 70 mm | exported 70 mm larger with a `clipping` operation |
| 4108 `ViyarDrilling` | hole → `drilling` | side mapping, through depth = thickness + 5 |
| 4158 `ViyarCutToGroove` | Bazis path cut (Паз tool) → `grooving` / `rabbeting` / edge bevel `srez` | includes the `closed` rule (groove ends at the edge band) |
| 4597 `ViyarPlaneCutToGroove` | flat pocket → `grooving` / `rabbeting` | the rules our push/pull grooves follow |
| 5230 `validateProject` | refuses: contour elements < 1 mm, profiled edges (кант), band narrower than thickness + 3 mm | |
| 5867 `adjustOrientation` | rotates panels so the grain runs along x, flips by front face / drilling side | |

## 5. Output format

`sjcl.encrypt` with defaults: PBKDF2-HMAC-SHA256, 10000 iterations, random 8-byte salt → AES-128
key; AES-CCM, 16-byte random IV truncated to `15 - L` bytes (L = 2, 3 or 4 by data length), 8-byte
tag, no associated data. The file is SJCL's JSON:

```json
{"iv":"…","v":1,"iter":10000,"ks":128,"ts":64,"mode":"ccm","adata":"","cipher":"aes","salt":"…","ct":"…"}
```

The password is the `PASSWORD` constant (64 hex characters, used as a UTF-8 string). The plaintext
is the XML as UTF-8, although its declaration says `windows-1251` (that is what Bazis2Viyar does).
With `DEBUG = true` the script writes the XML unencrypted.

XML (ObjTree: keys starting with `-` are attributes, in insertion order):

```
project currency version=1 costOperation costMaterial cost date orderDate productFilter=false
└ viyar version=27
  ├ order delivery uuid
  ├ creator id=Bazis2Viyar version=<script> bazisVersion=<apiVersion>
  ├ constructor id=dsp site
  ├ materials
  │ ├ material id=1 type=sheet article name width=3000 height=3000 thickness
  │ └ material id=2.. type=band article name height=<band width> thickness   (sorted by thickness)
  ├ details
  │ └ detail id material=1 barcode amount widthFull heightFull multiplicity grain(1/0) [detKind] description marker=0 [decoratedSide]
  │   ├ edges: left / top / right / bottom  type(kromka|srez|srezkrom|"") param(band id | angle) [srez krstart] drop=0
  │   └ operations: operation id type …     (order: clipping, drilling, grooving/rabbeting, cornerOperation, shapeByPattern)
  └ products: product id article name amount   (fittings, optional)
```

One file holds **one sheet material** (`detail material="1"` is hard-coded).

Sides: 1 front, 2 left, 3 top, 4 right, 5 bottom, 6 back. Panel frame: x along `widthFull`, y along
`heightFull`, origin bottom-left seen from the front. Numbers: `rnd()` = fixed 1 decimal (`"12.0"`,
`0` for zero), `rnds()` = trailing zeros dropped.

| Operation | Attributes (in order) |
|---|---|
| `drilling` | `[subtype=48 countersink]` side x y xo yo xl=0 yl=0 d depth; edge holes: the coordinate across the thickness is measured from the front face |
| `grooving` (face) | side(1/6) subtype(0 along x, 1 along y) x y width length closed depth [radius] |
| `grooving` (edge) | side(2–5) subtype x y (across thickness from the front face) width length closed depth |
| `rabbeting` | side(1/6) subtype="" edge(2–5) shift width length closed depth [radius] |
| `cornerOperation` | corner subtype(1 radius, 2 chamfer, 3 cutout) xFull yFull [rFull] [ext] edgeMaterial edgeCovering |
| `shapeByPattern` | patternId uShaped / rectangular / circle / arc / smile + its size attributes |
| `clipping` | cutHSize cutHBase edgeMaterialH cutVSize cutVBase edgeMaterialV edgeLengthH edgeLengthV |

## 6. Where it lives in this plugin

| Bazis2Viyar | Plugin |
|---|---|
| `sjcl.encrypt` | `src/ocl_viyar/sjcl.rb` (CCM on AES-ECB/CBC, no dependency on OpenSSL's CCM) |
| `PASSWORD`, `SCRIPT_VERSION`, viyar `version` 27 | `ViyarWriter::PASSWORD`, `CREATOR_VERSION`, `VIYAR_VERSION` |
| `createDocNode` | `ViyarWriter#to_xml`, `#_detail` |
| `splitNameCode` | `ViyarWriter#split_name_code` (the OpenCutList description comes first) |
| `Hole` 7.1 → countersink, `ViyarDrilling` | `ViyarWriter#_drilling` (+ `c` suffix / `countersink` preset flag) |
| `ViyarPlaneCutToGroove` | `Grooves.find` (geometry) + `ViyarWriter#_groove_attrs` (classification) |
| not ported yet | clipping, corners, shape patterns, bevels, `products`, groove `closed`/`radius`, `multiplicity`, `detKind`, `decoratedSide` |

## 7. When a new Bazis2Viyar version comes out

1. Download and unpack it (sections 1–2). Save the installer's checksum.
2. Decode the script: `python3 -I tools/bazis2viyar/decode.py "<script>.js" bazis2viyar-<new>.js`.
3. Run the encryption check, which also compares the password:
   `node tools/bazis2viyar/sjcl_check.js bazis2viyar-<new>.js` (from the repository root).
   If the password changed, update `ViyarWriter::PASSWORD`. If SJCL output differs, the
   encryption parameters changed (look at `sjcl.json.defaults` and the `sjcl.encrypt` call).
4. Diff against the previous decoded version, ignoring the SJCL block:
   `diff <(sed 1,50d bazis2viyar-5.10.js) <(sed 1,50d bazis2viyar-<new>.js)`.
   Things to look for:
   - `createDocNode`: `viyar` `version`, attribute names and order, new elements or operations
   - `ViyarDrilling`, `ViyarCutToGroove`, `ViyarPlaneCutToGroove`: side/subtype codes and coordinates
   - new `VIYAR_*` constants (new operation types or subtypes)
   - the `apiVersion` guard (newer Bazis versions supported)
5. Port the changes into `ViyarWriter` and its tests, bump `CREATOR_VERSION`, and update sections 4–6 here.
6. Export a sample (`OCL_VIYAR_SAMPLE_OUT=… ruby test/test_viyar_writer.rb -n test_write_sample_project`)
   and load it in the ViyarPro order constructor.

A ViyarPro project saved from the constructor itself may use the same format and password. If so,
decrypting it (SJCL, `sjcl.decrypt(PASSWORD, json)`) is the quickest way to learn attributes that
Bazis2Viyar never writes (e.g. other drilling subtypes).
