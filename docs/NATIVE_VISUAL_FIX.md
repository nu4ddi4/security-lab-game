# Native city and workstation corrections

Requested comparison: `godot-port...main`. Main `41d44b0` (including `55fe04a`)
was merged into `godot-port` as `aa6ae20`. The native workflow's EXE checks and
artifact summary were retained when resolving its add/add conflict.

## Exterior

The native port previously used one facade shader on randomly spread plain boxes.
It omitted the web city's roof silhouettes, facade families, balconies, fins,
urban ground and riverbank layers. Its hard window masks also produced aliasing.

`exterior.gd` now uses the same deterministic 130-building layout as `city3d.js`,
with six material families, varied occupancy, sunset-facing shading, distance haze
and derivative-based window filtering. Native MultiMeshes share roof copings,
plant, antennae, balcony parapets, office fins, bridges and road lamps. Ground
blocks, river highlights and the office's exterior sill/slab envelope restore
the missing depth. There are no new textures, per-window lights or render passes.

## Furniture

The decorative source is regenerated from the existing packed web GLB. Functional
nodes and indexed door/collision geometry remain exact. Corrected decoration is
baked into the native GLB so ordinary Godot imports keep their shared geometry,
materials and generated LODs.

- **26 keyboards:** long spacebars now face the chair. Shared position/normal
  accessors are changed once despite station-specific AO UVs. The asset test
  identifies the actual long key face to verify orientation for every station.
- **98 loose prop nodes:** support height is measured from each wood tabletop;
  footprints stay at least 25 mm inside its edge. Pens, paper, bottles, trays,
  notebooks, phones and sticky notes retain curated placement.
- Mug/headset pieces in combined meshes move to the rear/right, away from laptop
  bases. Laptop/phone/hub parts and their screens are brought down to the table.
  A phone that shared a laptop footprint moves to the left rear. Sticky notes
  and pen trays use clear front-side slots.
  Actual component bounds account for narrower desks. Selection bounds include
  5 mm of bevel/quantization tolerance, and indexed triangles are checked to
  prevent partial moves. Source positions and shared edits are tracked separately.
- Floating nameplates attach to the table's front face. Duplicate legacy training
  lettering is suppressed while its nonfunctional node name is preserved.
- **26 chairs:** the front of each rendered bounding box is 90 mm from its desk
  edge, rather than approximately 0.28–0.70 m. The native physics child shifts
  by the same world delta; original COLLIDER names, transforms and indexed mesh
  data remain untouched. Doors and INTERACT/SPAWN anchors remain unchanged.

`native-layout.json` records the derived support bounds and chair collision
offsets. It is authoring data, not saved mission state. Existing missions, input,
door pivots, player dimensions and save compatibility are preserved.

## Validation and distribution

Native unit checks retain 452 assertions. The asset check retains all 101
functional interfaces and 98 geometry hashes and validates all 26 long spacebars.
The existing scene smoke adds a direct rendered-chair/physics alignment check.

The exported EXE is reviewed at fixed window and workstation positions using
`-- --qa-layout`. It renders ten views and uncapped CPU/GPU/frame samples.
`-- --qa-ux` exercises all four missions, wrong defense, E/F, policy changes,
recheck, return position and save/reload. This is scoped automated input and
camera review, not a claim of a manual whole-map tour. Neither local visual
review is added to normal CI; its existing short scene smoke remains.

Exact screenshot measurements, final EXE size and Actions duration are recorded
in the output report after the corresponding run, without estimating them.
The Windows executable is delivered through the existing native Actions artifact.
No release, version bump or tag is needed for these branch corrections.
