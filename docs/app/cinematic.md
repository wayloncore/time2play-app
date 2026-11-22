# Cinematic arenas: research (#708, Part 1)

Tyler, Nov 21: "make the lightning in Overdraft even more aggressive … cinematic … 10,000 and any arena game truly
cinematic." Nov 21, 8:02 PM: "I will only allow the cinematic if it's made high quality and not fast to get it done.
Consult resources." This file is the reading, written down, and what each source changes in the design. The options
(Parts 2 to 4) are built from it; nothing ships until Tyler picks.

Checked Nov 22, 2026. A source marked **(not read in full)** is cited from its abstract or catalog page only; its
claims here are flagged as the talk's known thesis, to confirm before an option leans on a specific number.

## Where we start (what's in the app now)

- Overdraft's 3D table (App/Table3D/Table3DWorld.swift): Bolt suit storm, a strike every 1.4 to 3.2 s (2 to 4 s on
  the oldest phones), branching bolts drawn by a Metal shader (t3d_bolt_*), sometimes a second, fainter bolt; a violet
  directional `flashLight`; at most two flashes a strike, the second 0.4 s or more after the first (#610).
- No HDR, bloom, motion blur or depth of field anywhere in the 3D scenes (the Close Enough board sets wantsHDR = false).
- Haptics: `Haptics.jolt()` plus the `.bolt` sound for a Bolt aimed at you (App/Feel.swift). Not one AHAP pattern.
- 10000's arena (App/Dice3D): the roll eases the camera in (#706 makes it land closer); no shake, no held beats.

## Sources and what each changes

### Game feel

1. **Steve Swink, *Game Feel* (Morgan Kaufmann, 2008).** Feel is real-time control, simulated space and polish
   working together; polish ("juice") only reads as feel when it answers something the player did.
   *Changes the design:* every cinematic beat is tied to a player-caused moment (your Bolt, your Overdraft, your roll),
   never ambient noise. A storm that flashes on its own timer is background; the strike that hits *you* is the event.
2. **Martin Jonasson and Petri Purho, "Juice it or lose it," GDC Europe 2012** (GDC Vault 1016487) **(not read in
   full).** The known demo: the same breakout game made to feel alive by layering tweening, squash, particles, sound,
   shake, one at a time. *Changes:* build the options as layers we can switch one by one in the still mode, so Tyler
   can compare "camera only", "world only", "both"; and judge each layer on its own merit.
3. **Jan Willem Nijman (Vlambeer), "The art of screenshake," 2013** **(not read in full).** The known list: a lot of
   small reactions (kick, shake, a pause on hit, permanence) make an action land. *Changes:* the "hit stop" (a
   50–120 ms freeze or slow-down on the strike frame) is cheaper and more readable than more brightness; add it to
   the director option.
4. **Squirrel Eiserloh, "Math for Game Programmers: Juicing Your Cameras With Math," GDC 2016** (GDC Vault 1023146;
   overview: framing, smoothed motion, camera shake, split screen) **(not read in full).** Its widely cited method:
   a *trauma* value 0–1 that events add to and that decays over time; shake = trauma² (or ³) × smooth noise (Perlin),
   applied mostly to rotation, not translation. *Changes:* shake is driven by one trauma number with a cap, so two
   strikes don't stack into chaos; noise, not random jitter, so it reads as weight, not glitch; mostly rotation so
   the cards stay in place and readable.

### Cinematography and animation

5. **Frank Thomas and Ollie Johnston, *The Illusion of Life* (1981): the 12 principles**, especially anticipation,
   staging, timing, slow in and slow out, and exaggeration. *Changes:* every big moment gets a wind-up (a held beat,
   the light dropping) before the payoff; the camera stages the one thing that matters (the hit card, the dice) and
   eases in and out, never cuts mid-motion on a phone.
6. **How real lightning lights a scene.** A cloud-to-ground flash is a dim stepped leader, then the very bright
   return stroke moving up the channel (NWS, "Lightning science: the return stroke"); the channel stays conductive
   for a moment, so later dart leaders and return strokes can follow the same path, which is why a flash flickers.
   Typical figures in the literature (several strokes in one flash, tens of milliseconds apart, the whole flash a
   fraction of a second) are from Britannica's "Cloud-to-ground lightning"; **confirm the exact numbers before
   tuning**. *Changes:* a strike is staged as darken → leader → one big return stroke → a long violet afterglow on the
   cards and table, with any restrike on the *same* path. That is what reads as real; more bolts in more places does
   not.

### Apple

7. **SceneKit `SCNCamera`:** `wantsHDR` (default false; lighting in a deeper range, tone-mapped by exposure settings),
   `bloomIntensity` (default 0; needs wantsHDR), `motionBlurIntensity` (default 0, about 1 max; not supported with
   wide-gamut rendering, which is on by default on supported devices, unless SCNDisableWideGamut is set),
   `wantsDepthOfField`. *Changes:* bloom on the bolt and the flash is the single biggest "cinematic" win and is
   built in, but it means turning HDR on for the table, which changes every color: the options must re-check card
   readability and the suit colors. Motion blur is likely out (it costs wide gamut on the whole scene); a short
   shader smear on the bolt itself gets the look without that trade. Depth of field only during a held beat, and
   never on the cards you need to read.
8. **Core Haptics, AHAP files:** a pattern can hold HapticTransient, HapticContinuous, AudioContinuous and AudioCustom
   events, so a thunder sound and its rumble play from one file, in sync. *Changes:* the strike's crack is a sharp
   transient at the return stroke; the thunder is a continuous rumble that rises and decays a beat later (sound is
   slower than light), from one AHAP, so it never drifts from the picture.
9. **Human Interface Guidelines, Motion, and Reduce Motion:** keep motion purposeful, let people turn it down, and
   don't make large moving or flashing effects required to follow play. *Changes:* with Reduce Motion on: no shake,
   no flash, no camera moves; the moment is told by a calm light change, a still frame and the haptic.

### Safety

10. **WCAG 2.2, 2.3.1 Three Flashes or Below Threshold:** no more than three general flashes and no more than three
    red flashes in any one second, unless the flashing area is small (the combined area within .006 steradians of any
    10° field, about a 341 × 256 px rectangle on a 1024 × 768 screen). A general flash is a pair of opposing changes
    of 10% or more of maximum relative luminance where the darker state is below 0.80. A red flash involves a
    saturated red (R/(R+G+B) ≥ 0.8). *Changes:* a full-screen flash is always "large", so the rule that matters is
    the count: a strike plus restrikes is at most **two** luminance flashes in any second (keeping a margin under
    three), strikes stay at least 1.4 s apart as now, and no red flashes at all (the Bolt suit is violet; keep it).
    Every option gets an automated check: render the strike frame by frame in the still mode, compute mean relative
    luminance per frame and count opposing 10% changes in every one-second window.

## Principles the options will follow

- Cinema answers the player: big moments only when something happened to someone.
- Anticipation, then one big payoff, then a long settle; not many small flashes.
- One trauma value drives shake; rotation more than position; capped; zero under Reduce Motion.
- Readability is a hard rule: during every effect, cards, dice and scores stay legible (checked in the stills).
- Photosensitivity: at most 2 flashes a second, no red flashes, checked by a script, not by eye.
- Frame rate: hold the table's current frame rate on an older iPhone; any layer that costs more is optional per device.

## The split (linked parts of #708)

1. Part 1: this research (done).
2. Part 2: option A, the director (camera: anticipation, push-in, hit stop, trauma shake), built in the app on a
   branch, Overdraft mid-strike and 10000 mid-roll, recordings and stills, frame rates on a recent and an older
   simulator.
3. Part 3: option B, the storm (world: HDR and bloom, staged leader → return stroke → afterglow, AHAP thunder), same
   deliverables.
4. Part 4: option C, big moments only (calm play, short directed sequences), same deliverables, then the flash-count
   checker on all three and the comparison for Tyler with the one question; #708 gets `needs-tyler`.

Sources (checked Nov 22, 2026):
- WCAG 2.2 Understanding 2.3.1: https://www.w3.org/WAI/WCAG22/Understanding/three-flashes-or-below-threshold.html
- NWS, the return stroke: https://www.weather.gov/safety/lightning-science-return-stroke
- Britannica, cloud-to-ground lightning: https://www.britannica.com/science/thunderstorm/Cloud-to-ground-lightning
- SCNCamera bloomIntensity: https://developer.apple.com/documentation/scenekit/scncamera/bloomintensity
- SCNCamera wantsHDR: https://developer.apple.com/documentation/scenekit/scncamera/wantshdr
- SCNCamera motionBlurIntensity: https://developer.apple.com/documentation/scenekit/scncamera/motionblurintensity
- SCNCamera wantsDepthOfField: https://developer.apple.com/documentation/scenekit/scncamera/wantsdepthoffield
- AHAP files: https://developer.apple.com/documentation/corehaptics/representing-haptic-patterns-in-ahap-files
- Eiserloh, GDC 2016: https://gdcvault.com/play/1023146/Math-for-Game-Programmers-Juicing
- Jonasson and Purho, GDC Europe 2012: https://gdcvault.com/play/1016487/

## Option A, the director (Part 2, #716): what was built

Only with the launch argument `-t2p-cinema director`; without it both arenas are exactly as they were. The logic is
in T2PCore (`Cinema.swift`, tested in `CinemaTests` on the Mac run), so the other two options can reuse its pieces.

- **One director, one trauma value.** `CameraDirector` runs on real time and gives each frame a shot: how far the
  push-in has gone, how far the light has dropped, the scene's time scale (0 during a hit stop) and the shake.
  `Trauma` follows Eiserloh: events add to it, it falls away at 1.35 a second, shake = trauma², capped at 1.
  The shake is smooth gradient noise (11 steps a second) on roll (up to 2.1°), yaw (1.3°) and pitch (0.9°) at full
  trauma, plus a slide of about a hundredth of the camera's distance; a full beat adds 0.8 trauma, so the most a
  single Bolt turns the picture is about 1.3°.
- **A beat:** a held beat of 0.34 s (anticipation) in which the table's light drops by up to a third and a slow
  push-in starts (to 70%); the payoff with a 100 ms hit stop (the scene holds on the strike frame) and the trauma;
  the push creeps on for 0.5 s, then eases out over 1.2 s; the light comes back over 0.22 s, never a snap.
- **What counts as the moment (Swink: cinema answers the player).** Overdraft: a Bolt (+2 or +4) that lands, on you
  at full strength and on someone else at 0.6. In the storm's scene the strike itself comes at the end of the held
  beat; elsewhere the camera tells it alone. The storm's own strikes get a quiet rumble (0.4: no held beat, no hit
  stop) and come less often (2.4 to 4.2 s). 10000: your roll, its held beat lasting until the first die hits the felt
  (the throw is worked out ahead, so the director knows when), then a 75 ms hit stop and the shake; your Farkle
  lands with a harder knock. Someone else's roll gets nothing.
- **Readability.** Your hand, the scores and every word are drawn over the 3D scene, so they never move. The push is
  7% of the camera's distance on the table (12% on the dice), and the dice's tap spots follow the push but not the
  shake, so a tap during a shake still lands on the die it meant.
- **Photosensitivity.** Under the director a strike is one flash (no restrike), at least 1.4 s after the last: a Bolt
  that comes just after the storm's own strike holds its beat up to 0.8 s longer to get there, and any closer the
  camera tells it alone. `scripts/flashcheck.py` counts flashes in every second of each recording (whole screen and
  each quarter); the bar is at most 2 general flashes in any second and no red flashes.
- **Reduce Motion:** no push, no shake, no hit stop, no drop in the light, and (as before) no strikes.

The Mac run (`.github/workflows/cinema.yml`, a pushed commit with `[cinema director]`) puts the stills, recordings,
frame rates and flash counts in `docs/app/cinematic/director/`.

### Option A's first Mac run (run 44985878236, Nov 22): what it showed

Files: `docs/app/cinematic/director/` (stills as JPEGs, 19 s recordings as MP4s, `report.txt`). Recent simulator:
iPhone 17 Pro (iOS 26.2), tier high. Older: iPhone SE (3rd generation) (iOS 18.5), drawn at the oldest phones' tier.
"today" files are the same moments without the director, to compare.

- **It reads as intended.** The Bolt strike (recent-overdraft.mp4 at about 14.5 s): the table dims and the camera
  pushes in, the bolt lands, the frame holds, the picture turns about a degree and settles. The still
  (recent-overdraft-strike.jpg) against today's shows the push and the tilt. The dice (recent-dice.mp4): push-in
  through the throw, the knock on landing, a harder one on each Farkle; the loop's six rolls all played.
- **Readability:** your hand, the scores, the turn line and the Draw button never move (they're over the scene);
  the pile's 7 and the seat names stay sharp at full shake in every still.
- **Photosensitivity:** every recording passes, both phones: 0 general flashes in any second, 0 red flashes (whole
  screen and each quarter). The strikes are small changes in screen luminance (0.02 to 0.04), well under the 10%
  that makes a WCAG flash; a bigger, brighter flash is option B's job, and its check will matter more.
- **Frame rate:** the simulator draws the table at 22 to 35 fps whatever the option (today's 32, the director's 24,
  the calm version's 22: the calm one does the least, so the spread is the simulator's noise, not the effect). The
  dice hold 60. The director adds no draw calls, nodes, lights or passes: a few sums a frame on the camera and the
  three lights. Battery: nothing it adds runs on the GPU, so no cost beyond today's scene; only a phone (Instruments)
  can measure it, and only Tyler's phone can run that.
- **Gaps, to close in the comparison (#718):** "dice-mid-roll" stops 0.42 s after the pour, when the dice have
  already landed (today's still does the same); the workflow now stops at 0.18 s, so the next run shows them in the
  air. The 19 s Overdraft recording caught one directed strike on the recent simulator (the storm's own strikes
  are rarer under the director, and a slow simulator stretches the beat); the older one caught six.

## Option B, the storm (Part 3, #717): what was built

Only with `-t2p-cinema storm`. The camera never moves; the world does the work.

- **HDR and bloom.** The table's and the dice's cameras turn on `wantsHDR` (no exposure adaptation, so the picture
  never pumps) with a bloom threshold just over white (1.05): only what's brighter than white blooms, the bolt and
  the flash on the glass's rim, never the cards or the words. The bolt's core goes to 2.4 at the return stroke.
- **A strike, staged** (`StormStrike` in T2PCore, tested): the scene's light drops for 0.1 s; a dim stepped leader
  works down the channel in five steps (0.1 to 0.27 s, drawn from the cloud down by the bolt shader); then one return
  stroke (the whole channel at full brightness, the flash at its height); then a long violet afterglow on the cards
  and the table (a third bright half a second on, gone by 1.9 s). About two strikes in five get a restrike down the
  same channel 0.18 to 0.3 s after the stroke.
- **Thunder from one AHAP** (`App/Sounds/thunder.ahap`, `App/Cinema/Thunder.swift`): a sharp transient at the return
  stroke and a rumble 0.3 s later, with its sound (`thunder.caf`, Time2Play's own, `scripts/thunder.py`) in the same
  pattern, so they never drift apart. A Bolt aimed at you is felt and heard; the storm's own strikes are only heard,
  quietly. Haptics and Sound effects in You mute their halves. Without Core Haptics (an iPad), the sound alone.
- **What counts.** A Bolt aimed at you brings a strike of its own, as soon as the last one is 1.9 s behind (up to
  0.8 s later; any later and it gets none). The storm's own strikes come every 2.4 to 4.4 s.
  10000: your dice hitting the felt bring one warm swell of the light (a third brighter, settling in half a second)
  that makes their highlights bloom.
- **Photosensitivity.** A strike is the return stroke's flash and at most a restrike's: two. Strikes start at least
  1.9 s apart. The unit test models the worst case (the flash driving the whole screen black to white, every strike a
  restrike, strikes as close as allowed) and counts at most two flashes in any second. The recordings are counted too.
- **Reduce Motion:** as today, no strikes and no flashes (the clouds' slow flicker only), and no swell on the dice.

## Option C, big moments only (Part 4, #718): what was built

Only with `-t2p-cinema moments`. Play is calm; a short directed sequence, in slow motion, tells the moments that are
yours, and nothing else. It borrows the director's camera and the storm's staged strike, but only for those seconds.

- **What counts (Swink: cinema answers the player).** Overdraft: your Overdraft, a +2 or +4 that lands on you or a
  train you take; a suit change, read as a Change Suit or +4 played by anyone (a card matched by number changes the
  weather too, but that's every other turn, so it stays as it is today). 10000: your hot dice (every die you threw can
  score) and your Farkle. Someone else's Bolt or roll gets nothing. Both are small calls, noted for Tyler.
- **One sequence** (`MomentDirector` in T2PCore, tested in `BigMomentsTests`): a wind-up (about 0.3 s: the scene
  slows, the light drops, the camera starts to push in, the grade comes in), the payoff (the return stroke, the dice
  reaching the felt), a slow-motion hold (0.3× for an Overdraft, hot dice and a Farkle, 0.5× for a suit change), then
  the speed comes back over 0.45 s and the push and grade ease out half a second after. Cue to full speed is 1 to 2 s.
  One at a time, with a 1.2 s cool-down, so it stays rare enough to mean something.
- **The grade** is what makes it read as a cut to a different shot without a cut: the scene loses 40% of its color
  and the edges darken (SCNCamera saturation and vignetting), and the bloom rises (HDR as in option B, threshold over
  white, so only the bolt and highlights bloom). The hand, the scores and every word are drawn over the scene, so the
  grade never reaches them.
- **Overdraft.** In the storm, your Overdraft brings a full staged strike (option B's darkening, stepped leader and
  return stroke, no restrike) whose leader is the wind-up and whose stroke is the payoff, with thunder felt and heard;
  a small shake (trauma 0.6, at most about half a degree) on the stroke. In other weather the camera tells it alone.
  Calm play: the storm's own strikes come every 3.5 to 6.5 s, a third as bright, a fainter bolt, thunder heard quietly.
  A Change Suit to the storm sweeps in at half speed and arrives with a full strike once it's in.
- **10000.** The sequence starts a quarter second (scene time) before your dice reach the felt, so the last of the
  throw is in the air in slow motion; the hold plays the bounce; then, as the dice rest, a Farkle lands with a low
  knock and hot dice with a warm swell of the light. The push follows the dice's tap spots, as the director's does.
- **Photosensitivity.** One return stroke a strike, strikes at least 1.9 s of scene time apart (longer in real time
  under slow motion, which only stretches a flash). No red. The recordings are counted by `scripts/flashcheck.py`.
- **Reduce Motion:** no slow motion, push, shake, grade or strikes; your Overdraft is a gentle dip of the light and back
  over a second (and the haptic it already has). The dice play as today.
