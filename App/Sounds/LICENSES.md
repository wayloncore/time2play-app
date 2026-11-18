# Where the app's sounds come from

All of these are original, made in code for Time2Play by `scripts/sounds.py` (sine tones, filtered noise and plucked
strings, synthesized from scratch). Nothing is sampled, recorded from anywhere else, or taken from a TV show.

| File | What it is |
| --- | --- |
| card-play.wav | A card landing on the pile |
| draw.wav | A card sliding off the deck |
| your-turn.wav | Your turn: two notes going up |
| dice-roll.wav | Dice shaken and thrown |
| dice-land.wav | Dice coming to rest |
| farkle.wav | A Farkle: two muted notes stepping down |
| win.wav | A win: a rising arpeggio |
| bolt.wav | A Bolt (+2 or +4) aimed at you |
| music.m4a | The background music: a quiet loop, off unless turned on in You |

Run `python3 scripts/sounds.py` to make them again (needs numpy and ffmpeg).

Recorded CC0 sounds (Kenney's "Casino Audio", https://kenney.nl/assets/casino-audio, CC0) were the first choice on
Nov 17, but kenney.nl turned away the download from GitHub's runner, so the synthesized set shipped. If recorded
sounds replace any of these later, list the pack, its license and its link here.
