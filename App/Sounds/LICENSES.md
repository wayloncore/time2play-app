# Where the app's sounds come from

The sound effects are real recordings from Kenney's free packs (Kenney Vleugels, kenney.nl), all CC0 1.0 Universal
(public domain, https://creativecommons.org/publicdomain/zero/1.0/): free to use, no credit required. Kenney asks for
an optional "Kenney.nl" credit, given here. The music loop is still Time2Play's own, made in code. Nothing here is from
a TV show, and there's no theme music.

| File | What it is | Source file | Pack | License |
| --- | --- | --- | --- | --- |
| card-play.caf | A card landing on the pile | `Audio/card-place-1.ogg` | Casino Audio | CC0 1.0 |
| draw.caf | A card sliding off the deck | `Audio/card-slide-4.ogg` | Casino Audio | CC0 1.0 |
| dice-roll.caf | Dice shaken in the hand | `Audio/dice-shake-3.ogg` | Casino Audio | CC0 1.0 |
| dice-land.caf | Dice thrown onto the table | `Audio/dice-throw-3.ogg` | Casino Audio | CC0 1.0 |
| farkle.caf | A Farkle: a dull thud (a leather bag dropped, muffled) | `OGG/dropLeather.ogg` | RPG Audio | CC0 1.0 |
| bolt.caf | A Bolt (+2 or +4) aimed at you: a zap stepping down | `zapThreeToneDown.mp3` | Digital Audio | CC0 1.0 |
| your-turn.caf | Your turn: a short rising chime | `Audio/confirmation_001.ogg` | Interface Sounds | CC0 1.0 |
| win.caf | A win: a short rising steel-drum jingle | `OGG/jingles_STEEL/jingles_STEEL10.ogg` | Music Jingles | CC0 1.0 |
| thunder.caf | Thunder for a lightning strike (#717): a crack, then a rolling rumble; played from thunder.ahap | made by `scripts/thunder.py` | Time2Play's own | Time2Play's own |
| music.m4a | The background music: a quiet loop, off unless turned on in You | made by `scripts/sounds.py` | Time2Play's own | Time2Play's own |

The packs, as Kenney posted them on OpenGameArt (each page says License: CC0, Author: Kenney):

- Casino Audio: https://opengameart.org/content/54-casino-sound-effects-cards-dice-chips (also https://kenney.nl/assets/casino-audio)
- RPG Audio: https://opengameart.org/content/50-rpg-sound-effects (also https://kenney.nl/assets/rpg-audio)
- Digital Audio: https://opengameart.org/content/63-digital-sound-effects-lasers-phasers-space-etc (also https://kenney.nl/assets/digital-audio)
- Interface Sounds: https://opengameart.org/content/interface-sounds (also https://kenney.nl/assets/interface-sounds)
- Music Jingles: https://opengameart.org/node/22000 ("85 Short music jingles"; also https://kenney.nl/assets/music-jingles)

How they're made: `.github/workflows/sounds.yml` downloads the packs on a GitHub runner (kenney.nl refuses automated
downloads, so it uses Kenney's OpenGameArt posts), checks each page's license, and runs `scripts/recorded-sounds.py`:
it trims the silence, cuts each to length, fades the end, levels it, and saves it as a small mono .caf (IMA4, 44.1 kHz).
`scripts/sound-picks.json` names each file and its settings. Only the picked files are kept, never the packs.

The synthesized versions (`scripts/sounds.py`, sine tones, filtered noise and plucked strings) shipped in build 39. The
app plays an effect's `.caf` when there is one and its `.wav` otherwise, so to bring one back, run
`python3 scripts/sounds.py` and delete that effect's `.caf` (and keep only the `.wav` files you want).
