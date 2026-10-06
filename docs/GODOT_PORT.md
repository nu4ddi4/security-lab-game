# Security Lab native companion

The native project lives in `godot/`, beside the unchanged web v0.7.0 runtime.
Baseline: upstream main `6e6580e`. Tested engine: **Godot 4.7.2 stable,
official ed1daf0bf**, standard GDScript edition. Windows x64 export templates
of the same version are required for building, but are not required to play.

## Run and export

Open `godot/project.godot` with Godot 4.7.2 and run the main scene. On the first
import Godot extracts the embedded model textures. Those image files are generated
and ignored by Git; their import settings are tracked. `godot/.godot` and builds
are also ignored. The model is a Git LFS asset.

From the repository root, with Godot, Python and Node available to the developer:

```powershell
git lfs pull --include="godot/assets/models/Interior_07_Godot.glb,assets/models/security_lab.glb" --exclude=""
./scripts/godot-build.ps1 -Godot "C:/path/to/Godot_v4.7.2-stable_win64_console.exe"
```

Output: `godot/builds/Windows/SecurityLab.exe`. The PCK is embedded. Playing
requires neither Godot nor Chrome, Python, a local server, or a separate PCK.
The normal release export is not code signed. Its size is about 247 MB, including
the engine and imported assets; the EXE is distributed through the separate
`SecurityLab-Native-Windows-x64` Actions artifact rather than committed to Git.
The existing web Windows artifact/release path is retained.
The build helper resolves Windows PATH symlinks to the installed engine and
uses its adjacent `*_console.exe` wrapper for captured output and exit status.
Both build checks and scene smoke use that same console entry point; the player
EXE remains a normal graphical application.
The setup action creates a hard-link GUI alias on Windows, so CI explicitly
selects `Godot_v4.7.2-stable_win64_console.exe` from its installation directory.
Hard-link aliases without a companion wrapper fail with a useful message instead
of silently starting the GUI binary.
The action's Windows cache omits the wrapper, so CI restores the pinned official
editor archive when that file is absent while retaining the export-template cache.

Forward+ is the default renderer. For machines that cannot initialize it, Godot's
Compatibility renderer can be selected with the fixed engine argument
`SecurityLab.exe --rendering-method gl_compatibility`. SSAO and the reflection
probe are disabled on that path. This is not a separate HTML/Chrome fallback.

## Scene and responsibilities

`scenes/main.tscn` assembles native Node components, with no autoload managers:

| Component | Responsibility |
| --- | --- |
| `game.gd` | Composition, input actions, import/save wiring and startup |
| `missions.gd` | Evidence, explanation, defense, checks, score and spatial gates |
| `resources/definitions.json` | Authored mission/device data, separated from runtime state |
| `world.gd` | Interior import, preserved bindings, manual colliders and lighting |
| `player.gd` | CharacterBody3D, capsule, gravity, crouch, jump, camera and RayCast3D |
| `door.gd` | Original hinge, leaf collider, interpolation and player sweep protection |
| `device.gd` | Shared interaction contract and field guidance |
| `equipment.gd` / `screen.gd` | Shared SubViewport textures and live surface/LED materials |
| `ui.gd` | Control HUD, observations, terminal, policies, files, comparison and notes |
| `save_manager.gd` | Validated JSON, temporary-file replacement, backup and migration |
| `settings.gd` / `audio.gd` | Display/input preferences and quiet generated ambient/cue audio |

Signals connect mission changes to UI, equipment and debounced saves. Equipment
displays are read-only projections and cannot award evidence or verification.
The terminal interprets a fixed allowlist of simulation commands. It never
executes an OS shell or sends player-supplied targets to a network service.

## Assets and protected interfaces

`Security_Lab_Interior_07.blend` remains the authoring master. The native GLB is
derived from the shipped v0.7.0 base geometry using offline lossless decompression:

```powershell
npm ci
node scripts/godot-assets.mjs
node scripts/godot-asset-test.mjs
```

The native source is **63,300,876 bytes**. It does not require a browser meshopt
decoder. Browser LOD selection, temporal resolve and batching are not run in
Godot; the importer generates native mesh LOD. Native texture import uses VRAM
compression and mipmaps. The existing 1K–2K assets, credits and Korean Noto font
license are bundled; audio is project-generated.

The source comparison checks all **101 functional interfaces** and **98 exact
indexed door/collider geometry hashes** against the shipped baseline. Runtime
binding finds 89 authored collider meshes, three doors and five device anchors.
Godot replaces periods with underscores in two entry-wall node names; their
original identities are retained in metadata and the registry. Blender names,
transforms and source data are not renamed to accommodate this.

Authored colliders provide movement bodies and opaque interaction blocking;
transparent upper partitions retain movement collision without acting as opaque
ray blockers. Native floor/ceiling support bodies are separate additions.
Door leaf bounds and pivots come from the original metadata. Player height is
1.8 m, radius 0.305 m, eye height 1.65 m; crouch height/eye are 1.1/0.95 m.
Interaction reach is 2.65 m.

## Gameplay and persistence

| Mission | Native spatial loop |
| --- | --- |
| Tutorial | Admin PC E → F notes → authorized scope → verify |
| Services | Server E → network F/policy → server E → verify |
| Login | SOC E → F policy → E recheck → verify |
| Integrity | Cabinet E/baseline → analysis PC E/hash → F recovery → E/hash → verify |

Wrong defense still fails. Correct defense must preserve normal service/login,
and a terminal command cannot substitute for a required physical recheck.
Integrity computes the actual SHA-256 of the built-in UTF-8 strings. Recovery
clears the displayed hash result until another calculation, rather than displaying
an unmeasured success. SOC/network screens and server LEDs reflect the simulation
immediately; field records still require E.

WASD/mouse, Shift, Ctrl/C, Space, E, F and Esc retain their roles. F uses native
Control tool panels, not a webview. Notes expose evidence and explanation;
Comparison preserves before/after observations.

Normal progress lives at `user://progress.json`, with a validated previous save
at `progress.backup.json`. Invalid primary files are copied to timestamped corrupt
files before recovery. Saves contain mission IDs, clues, policies, observations
and inspected/rechecked flags, not Node references or instance IDs. Position and
open-door state are intentionally not persisted; loading returns to the safe spawn.

The file picker accepts exported web progress, v1/v2 game JSON and the v2 web
save envelope. Input is limited to 128 KiB, validated into a temporary candidate,
and completed missions are checked again. Invalid imports preserve current state.
The native game never reads browser localStorage. Preferences are separate in
`user://settings.json`: resolution, fullscreen, VSync, four quality presets,
Master/SFX volume, sensitivity and FOV.

## Graphics and validation

Forward+ uses restrained zone fills, directional shadows, SSAO and one bounded
reflection probe. The shadow/reflection atlas sizes are bounded. SSR and GI are
not enabled. Medium uses native resolution and 2× MSAA; Low reduces 3D resolution
and disables AO/reflection, while High/Ultra increase MSAA. Monitor/LED emission
is subdued and the monitor texture multiplies emission instead of adding a white
wash. Repeated office profiles share SubViewport textures.

Validation commands:

```powershell
node scripts/godot-asset-test.mjs
godot --headless --path godot --script res://tests/unit.gd
godot --headless --path godot -- --qa
# Local Windows input/Control regression, not the short CI smoke:
godot --path godot -- --qa-physical
# Or run the exported EXE with the same --qa-physical user argument.
```

`godot-parity.mjs` produces 42 independent v0.7.0 oracle checkpoints, including
wrong defense and recheck cases. The native suite passed **436 assertions**,
including web/legacy imports and malformed-import preservation. The vertical
slice passed before Login/Integrity were added. The exported Windows EXE then
completed all four missions at 100 points each through CharacterBody movement,
E/F input events, native Control button signals, all three doors and save/reload.
That full run uses no player teleport. Static camera review uses fixed poses.
OS-level UI review confirmed launch and the exploration button; the remainder
of that review was stopped by the user's Esc input, so it is not described as a
complete manual playthrough.

The native workflow builds/tests a separate Windows artifact. Existing fast
Windows Chrome CI is unchanged. Local `npm run check` covers the preserved web
version; run it against this checkout's server, not an older already-running EXE.
The final local web run passed 44 of 45 Chrome tests; the walking smoke lost
pointer lock while the interactive desktop was in use. It has not been marked
as passed. Native unit, protected-asset and scene smoke checks passed. Remote
CI results are recorded separately after push.

## Measured performance and remaining limits

Local editor review: RTX 5060 Ti, Vulkan Forward+, 1600×900, Medium, warmed caches,
VSync off, no FPS cap, 240 samples per view. These are static-camera measurements,
not a general minimum-hardware guarantee or a like-for-like browser comparison.

| View | Mean frame ms | P95 ms | Render CPU ms | Render GPU ms | Total draw calls | Rendered primitives |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Main Office | 1.737 | 1.796 | 0.810 | 1.479 | 2214 | 1845800 |
| SOC | 1.883 | 1.948 | 1.067 | 1.625 | 3243 | 2514960 |
| Network | 1.651 | 1.841 | 0.998 | 1.386 | 3323 | 2572662 |
| Server Room | 1.351 | 1.421 | 0.242 | 1.106 | 476 | 915472 |
| Window | 1.171 | 1.227 | 0.212 | 0.929 | 297 | 450590 |

Draw/primitives totals include renderer passes and are not unique asset triangle
counts. Engine-reported managed render video memory was about 421 MB and static
memory about 129 MB; these are not total process RAM or total driver VRAM.
Scene initialization was 519 ms in that editor run and 588 ms in the exported
EXE play test. Cold launch-to-first-frame, total process RAM, broad hardware
coverage and native CI duration have not been measured yet.

Remaining limitations: some printed boards/rack LCDs retain static source
graphics; city geometry is a native reconstruction rather than an exact shader
port; no GI/SSR or automatic renderer/settings recovery UI. Forward+ shutdown
logs reported seven texture RIDs, and the headless scene smoke reported six
ObjectDB instances at exit. Those cleanup warnings have not been resolved or
proven to indicate an in-session memory increase. Broader Windows hardware and
full independent manual playtesting remain appropriate before replacing the
stable web distribution.
