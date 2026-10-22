# RELEASE_NOTES — City of Shadows v1.0 (first playable)

## What this is
First playable build of CITY OF SHADOWS: an original open-world action/driving
game for iPhone, set in the coastal city of Meridian Bay. One build containing
the playable foundation plus simplified, working versions of the systems from
all five design parts.

## Working features
- Procedural texture pack (asphalt, concrete, 5 facade variants, brick,
  warehouse metal, shopfront, sand, grass, water, sky) and synthesized audio
  pack (11 WAVs) — app is intentionally heavier (~17–21 MB IPA).
- Full city: downtown, residential, commercial, industrial, coast & promenade,
  landmarks (dealership, garage, clothing, fuel mart, police station).
- On-foot movement (walk/run/jump/punch), third-person orbit camera.
- Arcade driving with drift; enter/exit any car; 4 ownable cars + tuning.
- Traffic AI with lights & obstacles; pedestrians with reactions.
- Wanted 1–5: patrol, pursuit, search, escape, arrest + fines; helicopter ≥4★.
- Story: 5 chapters, 10 missions, dialogue choices, relationships, 3 endings.
- Economy: missions/races/deliveries income; shops, properties, clothing.
- Day/night cycle, weather (clear/cloudy/rain/fog), wet roads, rain particles.
- Achievements, settings (quality/sensitivity/weather/time), JSON save.

## Known issues
- No device test yet — first verification is the GitHub Actions compile, then
  on-phone testing by the owner.
- Audio: full synthesized pack (menu music, ambience, engine/siren/rain loops, effects). Models are procedural primitives with a procedural texture pack — no external assets.
- Traffic light colours flip globally with the phase (behaviour is per-axis).

## Distribution
Unsigned IPA via GitHub Actions artifact `CityOfShadows-IPA`; sign with ESign.
