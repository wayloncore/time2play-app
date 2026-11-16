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

## Testing
- **In a cloud session:** `bash scripts/install-swift.sh` (Swift from swift.org, signature checked), then
  `export PATH=/opt/swift/usr/bin:$PATH && cd Core && swift test`. Run it for every change to `Core/`.
- **On a Mac (GitHub runner):** one run per finished piece, never per change. Start it with the REST dispatch
  (`gh api -X POST repos/wayloncore/time2play-app/actions/workflows/mac.yml/dispatches -f ref=main`) or `[mac]` in a
  pushed commit's message. Screenshots come back as base64 between `BEGIN-SHOT name` and `END-SHOT` in the job log.
  Report the Mac minutes each run used (they count 10x on a private repo).

## Rules (from #385)
- Visibility is Tyler's: don't change this repo's (private) or anything else's.
- Nothing goes live without its switch and Tyler's Approve. App Store releases only after he taps Approve.
- Saved data stays readable by the previous version: add fields, never rename or remove them in the same release.
- The server only adds to the protocol; an old app must survive a newer server (`ServerMessage.unknown`).
- Hosted rooms started from the website's game page must work exactly as they do now.
- Keys (App Store Connect, push, Sign in with Apple) live only in GitHub secrets: never in the repo, an issue or a log.
- The bundle id `live.time2play.app` isn't registered with Apple yet; it's fixed once the App Store record exists.
