#!/usr/bin/env python3
"""Static test suite for the CityOfShadows Xcode project.

No Swift compiler exists on this Linux VM, so these checks are the first
line of defence before the GitHub Actions macOS build:
  1. Every .swift file has balanced braces / parens / brackets
     (strings and comments stripped before counting).
  2. Every .swift file is referenced exactly once in project.pbxproj,
     and the pbxproj references no missing file.
  3. Scheme name, project name, bundle id and build names are consistent.
  4. No TODO / fatalError placeholders anywhere in the Swift sources.
  5. Info.plist parses as a valid plist and has the right display name
     and landscape orientations.
  6. build.yml (both copies) use macos-14 and the CityOfShadows names.
  7. Required docs exist.
  8. Icon generator runs and produces a 1024x1024 PNG.
Prints PASS/FAIL per check; exits non-zero on any failure.
"""
import os
import plistlib
import re
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
ROOT = os.path.abspath(ROOT)
APP_DIR = os.path.join(ROOT, "CityOfShadows")

failures = []


def check(name, ok, detail=""):
    print(("PASS" if ok else "FAIL") + "  " + name + ((" — " + detail) if detail else ""))
    if not ok:
        failures.append(name)


def strip_swift(text):
    """Remove // comments, /* */ comments and string literals (incl. \\" escapes)."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
        elif c == '"':
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == '"':
                    i += 1
                    break
                i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


swift_files = sorted(f for f in os.listdir(APP_DIR) if f.endswith(".swift"))
swift_paths = [os.path.join(APP_DIR, f) for f in swift_files]

# 1. Balance
for path in swift_paths:
    text = open(path).read()
    body = strip_swift(text)
    pairs = [("{", "}"), ("(", ")"), ("[", "]")]
    bad = [a + b for a, b in pairs if body.count(a) != body.count(b)]
    check("balance " + os.path.basename(path), not bad,
          "unbalanced: " + ",".join(bad) if bad else "")

# 2. pbxproj references
pbx_path = os.path.join(ROOT, "CityOfShadows.xcodeproj", "project.pbxproj")
pbx = open(pbx_path).read()
for name in swift_files:
    count = pbx.count("path = " + name + ";")
    check("pbxproj references " + name + " exactly once", count == 1,
          "count=" + str(count))
for extra in ["Info.plist", "Assets.xcassets", "CityOfShadows.app"]:
    check("pbxproj mentions " + extra, extra in pbx)
check("pbxproj objectVersion 56", "objectVersion = 56;" in pbx)
check("pbxproj bundle id", "com.etoo.cityofshadows" in pbx)
check("pbxproj GENERATE_INFOPLIST_FILE=NO", "GENERATE_INFOPLIST_FILE = NO;" in pbx)
check("pbxproj manual signing", "CODE_SIGN_STYLE = Manual;" in pbx)
check("pbxproj object ids share B22CE prefix",
      all(line.strip().split(" ")[0].startswith("B22CE") or not re.match(r"^\s*[0-9A-F]{24}\s", line)
          for line in pbx.splitlines() if re.match(r"^\s*[0-9A-F]{24}\s", line)))

# 3. Scheme
scheme_path = os.path.join(ROOT, "CityOfShadows.xcodeproj", "xcshareddata",
                           "xcschemes", "CityOfShadows.xcscheme")
scheme = open(scheme_path).read()
check("scheme BlueprintName CityOfShadows", 'BlueprintName = "CityOfShadows"' in scheme)
check("scheme BuildableName CityOfShadows.app", 'BuildableName = "CityOfShadows.app"' in scheme)
check("scheme container", "container:CityOfShadows.xcodeproj" in scheme)
target_ids = re.findall(r"BlueprintIdentifier = \"([0-9A-F]+)\"", scheme)
check("scheme target id exists in pbxproj",
      len(target_ids) > 0 and all(t in pbx for t in target_ids))

# 4. No placeholders
bad_tokens = ["TODO", "fatalError", "XXX:", "Lorem ipsum"]
for path in swift_paths:
    text = open(path).read()
    hits = [t for t in bad_tokens if t in text]
    check("no placeholders in " + os.path.basename(path), not hits,
          ",".join(hits))

# 5. Info.plist
plist_path = os.path.join(APP_DIR, "Info.plist")
try:
    with open(plist_path, "rb") as fh:
        pl = plistlib.load(fh)
    check("Info.plist parses", True)
    check("Info.plist display name", pl.get("CFBundleDisplayName") == "City of Shadows")
    orientations = pl.get("UISupportedInterfaceOrientations", [])
    check("Info.plist landscape only",
          "UIInterfaceOrientationLandscapeLeft" in orientations and
          "UIInterfaceOrientationPortrait" not in orientations)
except Exception as exc:  # noqa: BLE001
    check("Info.plist parses", False, str(exc))

# 6. build.yml copies
for rel in ["build.yml", os.path.join(".github", "workflows", "build.yml")]:
    yml = open(os.path.join(ROOT, rel)).read()
    ok = ("macos-14" in yml and "CityOfShadows.xcodeproj" in yml and
          "CityOfShadows.ipa" in yml and "CityOfShadows-IPA" in yml and
          "pillow" in yml and "--break-system-packages" in yml)
    check("workflow names in " + rel, ok)

# 7. Docs
docs = ["README.md", "PROJECT_STATE.md", "STORY_BIBLE.md", "MISSION_CATALOG.md",
        "ECONOMY_AND_ITEMS.md", "VEHICLE_SYSTEM.md", "FINAL_QA_REPORT.md",
        "RELEASE_NOTES.md", "BUILD_AND_DEPLOY.md"]
for doc in docs:
    p = os.path.join(ROOT, doc)
    check("doc exists: " + doc, os.path.isfile(p) and os.path.getsize(p) > 200)

# 8. Icon generator
try:
    proc = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "generate_icon.py")],
                          capture_output=True, text=True, timeout=120)
    icon_path = os.path.join(APP_DIR, "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")
    ok = proc.returncode == 0 and os.path.isfile(icon_path)
    detail = proc.stdout.strip() if ok else (proc.stdout + proc.stderr).strip()[:300]
    check("icon generator runs", ok, detail)
    if ok:
        from PIL import Image
        im = Image.open(icon_path)
        check("icon is 1024x1024", im.size == (1024, 1024), str(im.size))
except Exception as exc:  # noqa: BLE001
    check("icon generator runs", False, str(exc))

# 9. Enrichment: Textures / Audio folder references + SoundManager
check("pbxproj references Textures folder", "path = Textures;" in pbx and "folder" in pbx)
check("pbxproj references Audio folder", "path = Audio;" in pbx)
check("pbxproj has Textures build file", "Textures in Resources" in pbx)
check("pbxproj has Audio build file", "Audio in Resources" in pbx)
check("SoundManager.swift exists", os.path.isfile(os.path.join(APP_DIR, "SoundManager.swift")))
check("generate_textures.py exists",
      os.path.isfile(os.path.join(ROOT, "tools", "generate_textures.py")))
check("generate_audio.py exists",
      os.path.isfile(os.path.join(ROOT, "tools", "generate_audio.py")))
yml_gh = open(os.path.join(ROOT, ".github", "workflows", "build.yml")).read()
check("workflow generates textures+audio",
      "generate_textures.py" in yml_gh and "generate_audio.py" in yml_gh)

# 10. Run the asset generators and verify real output files.
for script, label in [("generate_textures.py", "textures"), ("generate_audio.py", "audio")]:
    try:
        proc = subprocess.run([sys.executable, os.path.join(ROOT, "tools", script)],
                              capture_output=True, text=True, timeout=300)
        check(label + " generator runs", proc.returncode == 0,
              (proc.stdout + proc.stderr).strip()[-200:] if proc.returncode != 0 else "")
    except Exception as exc:  # noqa: BLE001
        check(label + " generator runs", False, str(exc))

expected_textures = ["asphalt.jpg", "concrete.jpg", "facade_high.jpg", "facade_mid.jpg",
                     "facade_house.jpg", "facade_glass.jpg", "brick.jpg", "warehouse.jpg",
                     "shopfront.jpg", "sand.jpg", "grass.jpg", "water.jpg", "sky_gradient.jpg",
                     "sky_env.jpg"]
tex_total = 0
for name in expected_textures:
    p = os.path.join(APP_DIR, "Textures", name)
    ok = os.path.isfile(p) and os.path.getsize(p) > 5000
    if ok:
        tex_total += os.path.getsize(p)
    check("texture exists: " + name, ok)
expected_audio = ["menu_music.wav", "engine_loop.wav", "siren_loop.wav", "rain_loop.wav",
                  "city_ambience.wav", "ui_click.wav", "cash.wav", "success.wav",
                  "fail.wav", "punch.wav", "step.wav"]
aud_total = 0
for name in expected_audio:
    p = os.path.join(APP_DIR, "Audio", name)
    ok = os.path.isfile(p) and os.path.getsize(p) > 1000
    if ok:
        aud_total += os.path.getsize(p)
    check("audio exists: " + name, ok)
print("asset bytes: textures=" + str(tex_total) + " audio=" + str(aud_total))

# 11. Graphics-max pass: IBL, PBR materials, detailed cars.
gen_tex = open(os.path.join(ROOT, "tools", "generate_textures.py")).read()
check("sky_env generation present in generate_textures.py",
      "sky_env" in gen_tex and "sky_env.jpg" in gen_tex)
gvc_text = open(os.path.join(APP_DIR, "GameViewController.swift")).read()
check("lightingEnvironment referenced in GameViewController.swift",
      "lightingEnvironment" in gvc_text)
check("HDR + bloom configured in GameViewController.swift",
      "wantsHDR" in gvc_text and "bloomIntensity" in gvc_text)
ent_text = open(os.path.join(APP_DIR, "Entities.swift")).read()
check("physicallyBased referenced in Entities.swift", "physicallyBased" in ent_text)
check("spoiler construction present for sports in Entities.swift",
      "spoiler" in ent_text.lower())
cb_text = open(os.path.join(APP_DIR, "CityBuilder.swift")).read()
check("physicallyBased referenced in CityBuilder.swift", "physicallyBased" in cb_text)

# Phase 2 (vehicles+): two new cars, neon tuning mod, cabin interior.
cfg_text = open(os.path.join(APP_DIR, "Config.swift")).read()
check("Phase2: purchasable contains muscle", '"muscle"' in cfg_text)
check("Phase2: purchasable contains hatchback", '"hatchback"' in cfg_text)
check("Phase2: NeonColors enum in Config.swift", "enum NeonColors" in cfg_text)
check("Phase2: neonPrice in TuningPrices", "neonPrice" in cfg_text)
gs_text = open(os.path.join(APP_DIR, "GameState.swift")).read()
check("Phase2: buyNeon in GameState.swift", "func buyNeon" in gs_text)
check("Phase2: neonIndex in CarTuning", "neonIndex" in gs_text)
check("Phase2: setNeon in Entities.swift", "func setNeon" in ent_text)
check("Phase2: setUnderglowNight in Entities.swift", "setUnderglowNight" in ent_text)
check("Phase2: neonIndexValue in Entities.swift", "neonIndexValue" in ent_text)
check("Phase2: interior cabin in Entities.swift", "steerWheel" in ent_text)
check("Phase2: underglow wired in GameViewController.swift",
      "setUnderglowNight" in gvc_text)
check("Phase2: neon section in GaragePanel",
      "NEON UNDERGLOW" in open(os.path.join(APP_DIR, "ContentView.swift")).read())

# Phase 3 (gameplay+): police roadblocks, jump ramps, two new races, convoy.
sd_text = open(os.path.join(APP_DIR, "StoryData.swift")).read()
check("Phase3: RampDef in StoryData.swift", "struct RampDef" in sd_text)
check("Phase3: 3 jumpRamps in StoryData.swift", sd_text.count("RampDef(id:") == 3)
check("Phase3: race_northside in StoryData.swift", '"race_northside"' in sd_text)
check("Phase3: race_ring in StoryData.swift", '"race_ring"' in sd_text)
check("Phase3: airborne fields in Entities.swift", "var airborne" in ent_text and
      "var verticalSpeed" in ent_text and "var airTime" in ent_text)
check("Phase3: tryRampLaunch in GameViewController.swift", "func tryRampLaunch" in gvc_text)
check("Phase3: landFromJump in GameViewController.swift", "func landFromJump" in gvc_text)
check("Phase3: roadblock GameConfig constants used",
      "roadblockMinLevel" in gvc_text and "roadblockAheadDistance" in gvc_text and
      "roadblockMinDeployDistance" in gvc_text and "roadblockRedeploySeconds" in gvc_text)
check("Phase3: ramp GameConfig constants used",
      "rampTriggerSpeed" in gvc_text and "rampLaunchFactor" in gvc_text and
      "rampRewardPerAirSecond" in gvc_text and "rampMinAirTime" in gvc_text)
check("Phase3: deployRoadblock/clearRoadblock present",
      "func deployRoadblock" in gvc_text and "func clearRoadblock" in gvc_text)
check("Phase3: roadblock wired in update loop", "updateRoadblock(dt: dt)" in gvc_text)
check("Phase3: roadblock cleared on arrest/session reset",
      gvc_text.count("clearRoadblock()") >= 3)
check("Phase3: convoy GameConfig constants used",
      "convoyCarCount" in gvc_text and "convoySpeed" in gvc_text and
      "convoyDuration" in gvc_text)
check("Phase3: spawnConvoy/updateConvoy present",
      "func spawnConvoy" in gvc_text and "func updateConvoy" in gvc_text)
check("Phase3: convoy wired in update loop", "updateConvoy(dt: dt)" in gvc_text)
check("Phase3: convoy is third option in triggerDynamicEvent",
      "spawnConvoy()" in gvc_text and "roll < 0.34" in gvc_text)
check("Phase3: buildJumpRamps in CityBuilder.swift", "buildJumpRamps" in cb_text)
check("Phase3: ramp physics integrated in updateDrivenCar",
      "tryRampLaunch(car: car)" in gvc_text and "landFromJump(car: car" in gvc_text)

print()

print()
if failures:
    print("FAILED:", len(failures), "check(s)")
    sys.exit(1)
print("ALL CHECKS PASSED")
