# BUILD_AND_DEPLOY — City of Shadows

## Requirements
- A GitHub account (build runs on GitHub Actions, `macos-14`, Xcode 15.x).
- iPhone with ESign (or GBox) and a signing certificate for installation.
- No local build is possible on the Linux dev VM (no Xcode) — by design.

## Steps
1. Push this folder to a GitHub repository (keep `.github/workflows/build.yml`).
2. Actions tab → **Build CityOfShadows IPA** → Run workflow.
3. The workflow generates the app icon (`tools/generate_icon.py`, Pillow),
   builds the unsigned app with `CODE_SIGNING_ALLOWED=NO`, and zips
   `Payload/CityOfShadows.app` into `CityOfShadows.ipa`.
4. Download artifact **CityOfShadows-IPA**.
5. Open the IPA in ESign on the iPhone, sign with your certificate, install.
6. Launch in landscape. New Game creates a save; progress autosaves to the
   device (UserDefaults) roughly every 6 seconds and on purchases/missions.

## Project facts
- Project: `CityOfShadows.xcodeproj`, scheme `CityOfShadows`, Swift 5, iOS 15.
- Bundle ID: `com.etoo.cityofshadows`. Signing style: Manual (unsigned CI build).
- Reference workflow copy at project root: `build.yml` (identical content).

## Troubleshooting
- Build fails at icon step → Pillow install uses `--break-system-packages`
  (already in the workflow).
- "App is damaged"/won't open → the IPA must be signed in ESign before install.
- Static pre-checks before pushing: `python3 tools/check.py`.
