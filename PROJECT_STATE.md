# PROJECT_STATE — City of Shadows

## Overview
- Platform: iPhone (landscape), Swift 5, iOS 15+, SceneKit + SwiftUI.
- Bundle: `com.etoo.cityofshadows`, target `CityOfShadows`, manual signing.
- Build: GitHub Actions `macos-14`, unsigned IPA → user signs with ESign.
- This single delivery combines the playable foundation (Part 1) plus simplified,
  working versions of the systems described in Parts 2–5. It is NOT five
  sequential builds; see FINAL_QA_REPORT.md for honest scope.

## File map
| File | Responsibility |
|---|---|
| CityOfShadowsApp.swift | @main app, owns GameState |
| Config.swift | All tuning constants, vehicle catalog, tuning prices, paint/wheel/shirt colors, properties, quality/weather enums |
| RoadNetwork.swift | Road grid math: nearest road, intersections, lane offsets, next-target routing |
| GameState.swift | Codable save (UserDefaults JSON), InputState channel, HUD-published state, dialogue/panel models, all buy logic |
| StoryData.swift | Characters, 5 chapters, 10 missions with typed steps, dialogue trees with choices, races, delivery data |
| CityBuilder.swift | Procedural city: districts, roads, coast, landmarks, colliders, interactables, traffic lights, trees, lamps |
| Entities.swift | Primitive-built models: humanoid figure (walk animation, hair cap, shoes), player, detailed multi-part vehicles (PBR paint/glass/chrome, bumpers, grille, mirrors, exhaust, plate, spoked chrome wheels with brake discs, per-type extras), traffic car, police car (siren bar, push bumper, door panels), pedestrian, helicopter |
| PoliceAI.swift | WantedSystem state machine (patrol/observe/chase/search/return/arrest), PursuitCoordinator (unit counts, speed/aggression per star, pursuit & search targets) |
| GameViewController.swift | Engine: render loop, player & arcade car physics, collisions, traffic AI, pedestrian AI, police integration, helicopter, missions/races/deliveries, dynamic events, day/night + weather, camera, HUD sync, save sync |
| ContentView.swift | SwiftUI: HUD, touch controls, main menu, pause, dialogue UI, shop/dealership/garage/property/clothing/settings panels |
| HUDViews.swift | Minimap Canvas, wanted stars, hold/tap buttons, joystick, camera-drag surface, stat bar |

## Implemented systems (verified statically — see FINAL_QA_REPORT)
City exploration on foot (walk/run/jump), enter/exit cars, arcade driving with
drift, 6 purchasable cars (sedan, SUV, sports, **muscle, hatchback** — the
latter two added 2026-10-22 by the overnight improvement program) +
police interceptor, tuning with real stat effects, garage underglow neon
(6 colours, day/night logic), full interior cabin visible through glass,
traffic AI on the road network with traffic-light phases and obstacle braking,
pedestrians (wander/cross/wait/flee/knocked down), wanted 1–5 with search &
escape decay, arrest with fine, police roadblocks at 3+ stars (2 police cars
+ 3 concrete barriers, temporary colliders, auto-clear on arrest/session
reset), helicopter at 4+ stars, jump ramps (3) with airborne physics and
$120/s air-time bonus, day/night cycle, weather (clear/cloudy/rain/fog)
with wet roads & rain particles, 10 story missions with 8 step types,
dialogue choices persisted to decisions & relationships, 3 endings selected
by decisions, 4 races (northside sprint + outer ring rally added), deliveries,
dynamic events (breakdown, jam, **celebratory convoy** — 3 slow black cars,
45 s), shops/properties/clothing with validated purchases, achievements,
settings save, JSON save/load with defaults migration.

## Graphics-max pass (2026-10-22)
- IBL: `sky_env.jpg` (2048×1024 equirect gradient) feeds
  `scene.lightingEnvironment` (intensity 1.2) for real PBR reflections.
- PBR materials (`.physicallyBased`): car paint metalness 0.85 / roughness
  0.32, cabin glass 0.9 / 0.08, chrome & rims 1.0 / 0.15, facades roughness
  0.85, asphalt 0.9 dry → 0.25 in rain (wet reflective roads; the engine now
  changes roughness instead of overwriting the asphalt texture).
- Renderer: MSAA 4X, camera HDR + bloom (0.6 / 0.75 / 8), sun shadows
  `.forward`, 16 samples, shadow map 2048 (High) / 1024 (Medium) / 512 (Low),
  re-applied live when the quality setting changes.
- Key textures at 2048: asphalt + all four facades + sky_env (rest stay 1024).
- Cars are realistic-STYLED but original: detailed multi-part primitive
  models with PBR paint/glass/chrome and IBL reflections — not licensed
  real-brand cars and not studio-scanned meshes like CarX Street. All names
  (Vega Sedan, Bison SUV, Falco GT, Nyx Hyper, Interceptor) are invented.

## Known simplifications
- followCar mission step = drive to the convoy destination point (no separate
  convoy vehicle simulation).
- Traffic lights share global materials: all lights flip colour together with
  the phase; behaviour (who stops) is per-axis correct, visuals are not per-axis.
- Camera collision is "pull closer" only; cars/players use circle-vs-AABB.
- Audio is a synthesized pack (see Asset pack below); playback is AVAudioPlayer only (no AVAudioEngine).
- No keyboard/gamepad controls: touch-first build for iPhone.
- Building interiors are not enterable; shops are interaction points + panels.

## Decisions
- One engine view controller + data-driven content (StoryData) so future
  parts/missions extend data, not the engine.
- Save = single Codable struct, version field for migration.
- All buy actions validate in GameState (single source of truth for money).

## Asset pack (generated in CI, also present in this workspace)
Textures — `CityOfShadows/Textures/` (15 JPGs, 3,188,305 bytes total):
asphalt 603,666 (2048) · billboard 100,532 (added 2026-10-22, Phase 1 —
referenced by `CityBuilder.billboardMaterial`, bundled via the folder
reference in project.pbxproj) · facade_glass 408,814 (2048) ·
facade_high 392,171 (2048) · facade_mid 373,345 (2048) ·
facade_house 303,992 (2048) · sand 189,178 · grass 163,578 ·
concrete 146,724 · warehouse 130,496 · water 127,964 · brick 80,525 ·
shopfront 79,552 · sky_env 64,193 (2048×1024, IBL) · sky_gradient 23,575.
Note: `tools/check.py`'s expected-texture list covers the 14 pre-Phase-1
files (3,087,773 bytes); `billboard.jpg` was verified separately on disk
and by code/pbxproj reference.
Applied via `TextureLoader` (Config.swift) with flat-colour fallbacks; roads,
sidewalks, ground, sand and water tile with repeat wrapping; building boxes use
the five facade/brick/warehouse variants; the sky gradient is the scene
background (static — it does not change with the day/night cycle), while
sky_env drives image-based lighting reflections only.

Audio — `CityOfShadows/Audio/` (11 WAVs, 13,759,680 bytes total):
menu_music 10,584,044 (60 s pad, 44.1 kHz) · city_ambience 1,764,044 (20 s) ·
rain_loop 529,244 · engine_loop 352,844 · siren_loop 352,844 · success 70,604 ·
fail 44,144 · cash 35,324 · punch 13,272 · ui_click 7,100 · step 6,216.
Played by `SoundManager.swift` (AVAudioPlayer): menu music, city ambience,
engine loop with speed-driven playback rate, siren when police are near with
wanted > 0, rain loop in rain weather, and one-shots for UI clicks, purchases
(cash), mission success/fail, punches and footsteps. Volumes follow settings.

Total added asset size on disk: 16,947,985 bytes (~16.2 MiB).
Whole project on disk: 17,373,955 bytes (~16.6 MiB, `du` ≈ 17 MB).
Estimated IPA size: ~19–23 MB (app binary + asset pack; WAV/JPG compress
poorly, so the IPA stays close to the raw asset size).

## Final state (2026-10-22 06:00 — improvement program ended)
- Swift: 12 files, 7,169 lines (baseline 2026-10-22 02:14 was 6,073; +1,096
  across program Phases 1–3).
- Static checks: `python3 tools/check.py` → ALL CHECKS PASSED, **135/135**,
  run on this VM 2026-10-22 ~06:00 (includes Phase 2/3 section checks).
- Program outcome: Phases 1–3 completed; Phases 4–6 not done (see
  IMPROVEMENT_PROGRAM.md — honesty rule: do not mark them done).
- Xcode build / device runtime: **NOT TESTED** (no Xcode on this VM) —
  first real compile happens in GitHub Actions.
