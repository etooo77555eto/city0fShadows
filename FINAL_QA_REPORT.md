# FINAL_QA_REPORT — City of Shadows (combined Parts 1–5 build)

## Environment note
This Linux VM has **no Swift compiler / Xcode**. All tests below are static
(`tools/check.py`) plus code review. The first real compile happens in GitHub
Actions (macos-14). Nothing in this report claims a runtime pass that was not
executed.

## Static tests (tools/check.py)
- Brace/paren/bracket balance for every .swift file (strings/comments stripped).
- Every .swift file referenced exactly once in project.pbxproj; objectVersion 56;
  bundle id `com.etoo.cityofshadows`; manual signing; GENERATE_INFOPLIST_FILE=NO.
- Scheme/project/app names consistent; scheme target id exists in pbxproj.
- No TODO / fatalError placeholders.
- Info.plist parses; display name "City of Shadows"; landscape-only.
- Both build.yml copies: macos-14 + correct project/IPA/artifact names.
- All docs present. Icon generator runs → 1024×1024 PNG.
- Phase 2 checks (purchasable muscle/hatchback, neon system, cabin, garage UI).
- Phase 3 checks (ramp defs/physics, roadblock deploy/clear/wiring, convoy).
Result: run 2026-10-22 ~06:00 on this VM by the closing worker — **ALL CHECKS
PASSED, 135/135** (baseline before the overnight program was 106/106).

## Manual scenario checklist (to run after the first device install)
| # | Scenario | Status |
|---|---|---|
| 1 | Launch → main menu → New Game starts world | NOT TESTED (needs device build) |
| 2 | City, player, camera visible; walk/run/jump; building collision | NOT TESTED |
| 3 | Enter car, drive, brake, reverse, drift, exit | NOT TESTED |
| 4 | Traffic follows roads, stops at red lights & obstacles | NOT TESTED |
| 5 | HUD updates (speed, money, health, stars, minimap, objective) | NOT TESTED |
| 6 | Weather picker + time skip change scene | NOT TESTED |
| 7 | Wanted rises (collision/speeding/theft), search, escape decay | NOT TESTED |
| 8 | Arrest: fine, release at MBPD | NOT TESTED |
| 9 | Mission 1 completes end-to-end; reward once | NOT TESTED |
| 10 | Buy car / tuning / property / clothing; insufficient-funds refusal | NOT TESTED |
| 11 | Save persists across relaunch; Continue works | NOT TESTED |
| 12 | Restart session without duplicated entities | NOT TESTED |

## Graphics-max pass (2026-10-22, static verification only)
Implemented and covered by new `tools/check.py` section-11 checks (all PASS):
IBL via `sky_env.jpg` → `scene.lightingEnvironment` (intensity 1.2); PBR
materials in Entities/CityBuilder/TextureLoader (paint 0.85/0.32, glass
0.9/0.08, chrome & rims 1.0/0.15, facades ~0.85, asphalt 0.9 dry → 0.25 wet);
MSAA 4X; camera HDR + bloom (0.6/0.75/8); sun shadow map 2048/1024/512 by
quality with 16 samples, forward mode, re-applied on quality change; asphalt
and facade textures regenerated at 2048; detailed multi-part cars (bumpers,
grille + chrome strip, side skirts, mirrors, exhausts, plate, full-width
taillight strip, lensed headlights, brake discs + 5-spoke chrome rims inside
the spin nodes, SUV roof rails and bigger wheels, sports/supercar hood panel
and painted wider spoilers, police push bumper + door panels); humanoid hair
cap and shoes.
Honest scope: the cars are realistic-styled ORIGINAL designs — detailed
multi-part primitive models with PBR paint/glass/chrome and IBL reflections —
not licensed real-brand cars and not studio-scanned meshes like CarX Street.
Runtime look/performance of the PBR + HDR + bloom stack is NOT TESTED (no
Xcode on this VM); it is verified statically only, like everything else here.

## Known limitations (honest)
- Prototype presentation: primitive-built models (no external meshes), now with a procedural texture pack and a synthesized audio pack (below).
- Traffic-light visuals flip globally (shared materials); stopping behaviour
  is per-axis. followCar step is simplified to reaching the convoy destination.
- AI uses distance-based vision (no occlusion raycasts).
- Performance on device is unmeasured; quality presets cap traffic/pedestrian
  counts and culling distance.

## Asset pack verification (run locally on this VM, 2026-10-22)
- `tools/generate_textures.py` ran clean: 15 JPGs in
  `CityOfShadows/Textures/`, total 3,188,305 bytes on disk — including
  `billboard.jpg` 100,532 (added 2026-10-22 Phase 1, 3 billboards in the
  commercial district; referenced by `CityBuilder.billboardMaterial` and
  bundled through the pbxproj folder reference). `tools/check.py`'s
  expected-texture list still names the 14 pre-Phase-1 files (3,087,773
  bytes); `billboard.jpg` was verified separately by disk + code + pbxproj
  reference, not by the checker.
- `tools/generate_audio.py` ran clean (stdlib only): 11 WAVs in
  `CityOfShadows/Audio/`, total 13,759,680 bytes (menu_music.wav 10,584,044).
- Textures/Audio folders are registered in project.pbxproj as folder
  references with Resources build files; SoundManager.swift is in Sources.
- tools/check.py re-runs both generators and asserts every expected file
  exists with a sane size; final run 06:00 — ALL CHECKS PASSED 135/135.
- Whole project on disk: 17,373,955 bytes (~16.6 MiB). Swift: 12 files,
  7,169 lines. Estimated final IPA: ~19–23 MB.
- **Xcode build and device runtime: NOT TESTED** (no Xcode on this VM).
  First real compile happens in GitHub Actions (macos-14); nothing here
  claims a runtime pass that was not executed.
