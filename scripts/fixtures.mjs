// Makes the view fixtures the T2PCore tests decode, from the website's own room cores (the rooms' real views, not
// hand-written copies). Run from this repo with the website checked out beside it:
//   node scripts/fixtures.mjs ../tyleralocke
// Writes Core/Tests/T2PCoreTests/Fixtures/*.json. Run it again when a room's view grows a field the app reads.
import { createRequire } from 'node:module';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const site = resolve(process.argv[2] || '../tyleralocke');
const out = resolve('Core/Tests/T2PCoreTests/Fixtures');
const req = createRequire(import.meta.url);
const save = (name, obj) => writeFileSync(`${out}/${name}.json`, JSON.stringify({ t: 'you', ...obj }, null, 1) + '\n');
const t0 = 1_800_000_000_000;

// Overdraft: a hostless room, one person and two bots, dealt
{
	const C = req(`${site}/src/live/overdraft/room-core.cjs`);
	const R = C.createRoom({ code: 'K7QP', seed: 7, now: t0 });
	C.claim(R, t0, { hostless: true });
	const me = C.join(R, { name: 'Sam', face: 9 }, t0);
	C.addBot(R, R.hostToken, 'easy', t0); C.addBot(R, R.hostToken, 'normal', t0);
	save('overdraft-lobby', C.viewFor(R, me.id, me.token));
	C.deal(R, R.hostToken, t0);
	// play until it's my turn
	for (let i = 0; i < 50 && !C.viewFor(R, me.id, me.token).yourTurn; i++) C.tick(R, t0 + (i + 1) * 60_000);
	save('overdraft-table', C.viewFor(R, me.id, me.token));
}
// Hot Dice (Farkle Live), Roll Call, Close Enough: hostless, one person and a bot, started
for (const [name, file, bot, opts] of [['hotdice', 'farkle/room-core.js', 'steady'], ['rollcall', 'rollcall/room-core.js', 'medium'], ['closeenough', 'closeenough/room-core.js', 'medium']]) {
	const C = await import(pathToFileURL(`${site}/src/live/${file}`).href);
	const R = C.createRoom({ code: 'K7QP', seed: 7, now: t0 });
	C.claim(R, t0, { hostless: true });
	const me = C.join(R, { name: 'Sam', face: 9 }, t0);
	C.addBot(R, R.hostToken, bot, t0);
	C.settleOwner?.(R); // the room settles who owns it after every message (room-do.js)
	save(`${name}-lobby`, C.viewFor(R, me.id, me.token));
	C.deal(R, R.hostToken, t0);
	C.settleOwner?.(R);
	let v = C.viewFor(R, me.id, me.token);
	if (name === 'rollcall' && v.yourTurn) { C.act(R, me.id, me.token, { t: 'roll' }, t0 + 10); v = C.viewFor(R, me.id, me.token); }
	if (name === 'hotdice' && v.yourTurn) {
		C.act(R, me.id, me.token, { t: 'roll' }, t0 + 10);
		C.tick?.(R, t0 + 5000);
		v = C.viewFor(R, me.id, me.token);
	}
	save(`${name}-playing`, v);
}
console.log('fixtures written to', out);
