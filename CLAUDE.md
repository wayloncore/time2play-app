# time2play-app

The Time2Play iPhone app (native SwiftUI). The plan and its rules live in the website repo:
wayloncore/tyleralocke, `docs/app/plan.md` and issue #385. How to work with Tyler is in that repo's `CLAUDE.md`;
it applies here too.

## What's here
- `Core/`: the `T2PCore` Swift package, with no UI (room codes, join links, the protocol messages). It builds and
  tests on Linux, so a cloud session tests app logic for free.
- `App/`: the SwiftUI app. `UITests/`: UI tests that run in the iPhone simulator.
- `project.yml`: the XcodeGen spec. The Mac workflow makes `Time2Play.xcodeproj` from it; the project file isn't kept.
- `.github/workflows/mac.yml`: the batched Mac run (package tests, build, UI tests, screenshots printed into the log).
- `.github/workflows/testflight.yml`: the signed build, uploaded to TestFlight (#406). Start it with the REST dispatch
  or `[testflight]` in a pushed commit's message on main. Its build number is the run number. `scripts/asc.py` talks
  to App Store Connect with the API key in secrets (ASC_ISSUER_ID, ASC_KEY_ID, ASC_KEY_P8): the distribution
  certificate, the App Store profile, waiting for processing, and the internal testing group.
- `App/Assets.xcassets/AppIcon.appiconset`: the app icon (one 1024 × 1024 PNG, no transparency):
  the website's Time2Play mark (the gold 2 in its ring).

## Testing
- **In a cloud session:** `bash scripts/install-swift.sh` (Swift from swift.org, signature checked), then
  `export PATH=/opt/swift/usr/bin:$PATH && cd Core && swift test`. Run it for every change to `Core/`.
- **On a Mac (GitHub runner):** one run per finished piece, never per change. Start it with the REST dispatch
  (`gh api -X POST repos/wayloncore/time2play-app/actions/workflows/mac.yml/dispatches -f ref=main`) or `[mac]` in a
  pushed commit's message. Screenshots come back as base64 between `BEGIN-SHOT name` and `END-SHOT` in the job log.
  Report the Mac minutes each run used (they count 10x on a private repo).

## Kept in step with the website (never written twice by hand)
- `Core/Sources/T2PCore/Resources/rules.js`: the website's room cores (rules and bots) for offline games, bundled by
  `node scripts/rules-bundle.mjs ../tyleralocke` (with the website checked out beside this repo). It also writes the
  parity fixture the Mac checks in JavaScriptCore. Re-run it when a game's rules change on the website;
  `--check` says whether the bundle is out of date.
- `Core/Tests/T2PCoreTests/Fixtures/*.json`: real views from the website's room cores (`node scripts/fixtures.mjs
  ../tyleralocke`). Re-run when a view grows a field the app reads.

## UI tests and the live site
- The UI tests play real rooms on tyleralocke.com (staging is behind the studio's sign-in, which a GitHub Mac can't
  pass). Each run opens a few rooms there. Offline tests (`OfflineUITests`, the tour) need no network.
- `REVIEW_SIGNIN_KEY` (a repository secret, Tyler's) lets the account tests sign in as App Review; they skip without it.
- The workflow's `ipad` input runs `TourUITests` again on an iPad simulator.

## Rules (from #385)
- Visibility is Tyler's: don't change this repo's (private) or anything else's.
- Nothing goes live without its switch and Tyler's Approve. App Store releases only after he taps Approve.
- Saved data stays readable by the previous version: add fields, never rename or remove them in the same release.
- The server only adds to the protocol; an old app must survive a newer server (`ServerMessage.unknown`).
- Hosted rooms started from the website's game page must work exactly as they do now.
- Keys (App Store Connect, push, Sign in with Apple) live only in GitHub secrets: never in the repo, an issue or a log.
- Apple: Team ID `6WK983RXJT`, bundle id `live.time2play.app`, App Store name "Time2Play Live" (the home screen says
  "Time2Play"). None of these is secret.
