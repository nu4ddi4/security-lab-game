# Native mission UX and Windows test artifact

This change targets `godot-port`, building on `0baca39`. The web v0.7.0
runtime remains the reference for mission rules and saved progress. No release
version, release workflow, or tag is changed.

## Player-facing changes

- First exploration shows a nonmodal nine-second movement/E/F cue and the current
  target. Inspection or a device tool dismisses it; returning from F does not
  repeat it.
- The HUD separates the mission, objective, next action, its purpose, and the
  target's existing zone/direction/straight-line distance.
- A compact contextual prompt names the device and specific E/F actions. Its
  dark background keeps text readable over light desks.
- Services explains that the server supplies evidence while the firewall edits
  access policy. Integrity explains trusted source versus current-file analysis.
  Login and Tutorial use the same inspect/interpret/tool/verify sequence.
- Field cards separate device, status, key findings, earned evidence count and
  next action. They stay visible while aiming at the inspected device and close
  on tool entry, another target, or state changes. Full hashes/command transcripts
  stay in detailed tools; missing evidence names are not revealed by the card.
- Wrong and unrelated inspections remain factual. Blocking HTTPS reports loss
  of normal document service; it does not prescribe the corrective setting.
- A policy change names the physical recheck destination in the HUD and detail
  banner. The device placard, prompt and card use the same neutral/pending/
  problem/normal meanings. F cannot fulfill E inspection or recheck gates.
- Detail tools show their originating device/zone and return to the same place.
- The first-entry review required correcting one spawn interpretation: the
  authored `SPAWN_Player` is a foot-level anchor, while the existing camera
  already supplies 1.65 m eye height. Player placement no longer subtracts that
  eye height from the anchor. The anchor, player physics and respawn are preserved.

## Implementation boundary

`missions.gd` supplies read-only action reasons, device purpose/tool labels,
device status and short findings derived from existing observations. It executes
the same allowlisted simulation commands. No new saved fields, mission states,
network requests, render passes or dependencies are added.

`ui.gd`, `device.gd` and the tool signal in `game.gd` display those projections.
`world.gd` changes only initial player placement interpretation. The Blender
master, GLB, functional transforms, door pivots and colliders are unchanged.

## Verification

- Native unit suite: **452 assertions**, including the existing 42 independent
  web-oracle checkpoints, legacy/native save compatibility and focused UX checks.
- Existing headless scene smoke: all 101 protected nodes, 89 colliders, 3 doors,
  screen/LED bindings, initial eye height, recheck banner/placard agreement,
  wrong-defense card and save roundtrip.
- Local exported EXE: `-- --qa-ux --qa-output=<directory>` checks all four missions
  using fixed review positions, real raycast/E/F and native UI answer/policy/
  restoration controls. It checks F without clues, unrelated E, incorrect
  defense, E rechecks, same-position tool return and saved completion. Each
  mission scores 100 after its full loop. Eleven rendered 1600×900 views are
  captured for inspection. This is not a manual map tour or long walking test.
- Required `npm run check`: 72 Node checks, 26 server checks (25 pass, one
  existing platform permission skip), 45 Chrome checks. Web files are unchanged.
- Protected asset verification checks native transforms and all 98 indexed
  door/collision surfaces against the authored baseline.

## Artifact, not release

The existing **Godot Native Windows** workflow imports, tests and exports once,
runs its existing short headless scene smoke, then uploads only the embedded-PCK
`SecurityLab.exe` as **SecurityLab-Native-Windows-x64**. The build now rejects a
missing/empty EXE explicitly; the Actions summary links the artifact and records
the EXE's byte size. Playing requires no Chrome, Python, Godot installation or
separate PCK.

The branch's scoped CI keeps development pushes on fast native checks. Windows
builds run for a non-draft PR/main, or the existing manual native workflow.
This task requests an artifact, so that native workflow is dispatched for the
same `godot-port` commit; the scoped selection policy and caches are preserved.

The local four-mission screenshot review is not added to CI. CI timings and the
downloaded artifact's exact EXE size belong to the final Actions run/report, not
estimated values here. Release creation: **NO**. Tag creation: **NO**.

New tutorial frameworks, asset/rendering changes, long walking E2E, additional
missions and a project-wide audit are outside this UX task.
