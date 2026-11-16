// The parity check (#402): the same seeded game played step by step, in Node (scripts/rules-bundle.mjs writes the
// result as a fixture) and inside the app's JavaScriptCore (T2PCore's ParityTests). Every step's view is hashed; the
// two lists must be identical, move for move. The player's choices here are a fixed, simple policy, the same on both.

/** FNV-1a over the view's JSON text: the same number in any JavaScript engine. */
function hash(s) {
	let h = 0x811c9dc5;
	for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
	return h.toString(16).padStart(8, '0');
}

const BOT = { overdraft: ['easy', 'normal'], farkle: ['steady', 'bold'], rollcall: ['easy', 'hard'], closeenough: ['easy', 'hard'] };

/** One move for the player, from its own view, or null to wait for the room's clock. */
function choose(game, v) {
	if (game === 'overdraft') {
		if (!v.yourTurn) return null;
		if (v.legal && v.legal.length) {
			const c = v.hand.find((x) => x.id === (v.drawn && v.legal.includes(v.drawn) ? v.drawn : v.legal[0]));
			return { t: 'play', card: c.id, suit: c.suit || 'wave' };
		}
		return v.drawn ? { t: 'hold' } : { t: 'draw' };
	}
	if (game === 'farkle') {
		const t = v.turn;
		if (!v.yourTurn || !t) return null;
		if (t.state === 'start' || t.state === 'hot') return t.pts >= (t.need || 0) && t.state === 'hot' ? { t: 'bank' } : { t: 'roll' };
		if (t.state !== 'choose') return null;
		if (!t.sel.length) { const d = t.live.find((x) => true); return d == null ? null : { t: 'tap', die: d }; }
		if (t.selPts > 0) return t.pts + t.selPts >= Math.max(300, t.need || 0) ? { t: 'bank' } : { t: 'roll' };
		return { t: 'tap', die: t.live.find((x) => !t.sel.includes(x)) ?? t.sel[0] };
	}
	if (game === 'rollcall') {
		if (!v.yourTurn || !v.turn) return null;
		if (v.turn.rolls === 0) return { t: 'roll' };
		const o = v.options;
		if (!o) return null;
		const best = o.allowed.slice().sort((a, b) => o.scores[b] - o.scores[a])[0];
		return { t: 'score', key: best };
	}
	if (game === 'closeenough') {
		const q = v.question;
		if (!q || q.stage !== 'ask' || v.answer) return null;
		const mid = q.floor + (q.ceiling - q.floor) / 2;
		return { t: 'range', lo: q.floor + (mid - q.floor) / 2, hi: mid + (q.ceiling - mid) / 2 };
	}
	return null;
}

/** Plays one seeded game to its end (or 2,000 steps) and returns every step's hash. */
export function parityRun(game, seed, OfflineRoom) {
	let now = 1_800_000_000_000;
	const room = new OfflineRoom(game, seed, now);
	const steps = [];
	const note = (label, msgs) => { for (const m of msgs) steps.push(label + ':' + hash(JSON.stringify(m))); };
	note('join', room.handle({ t: 'join', name: 'Sim', face: 9 }, now));
	for (const b of BOT[game]) note('bot', room.handle({ t: 'addbot', level: b }, now));
	note('deal', room.handle({ t: 'deal' }, now));
	let v = room.views()[0];
	for (let i = 0; i < 2000 && v && v.phase !== 'done'; i++) {
		const m = choose(game, v);
		if (m) { now += 500; note(m.t, room.handle(m, now)); }
		else {
			const due = room.next();
			now = due == null ? now + 1000 : Math.max(now + 1, due);
			room.tick(now);
			note('tick', room.views());
		}
		v = room.views()[0];
	}
	return { game, seed, steps: steps.length, phase: v ? v.phase : null, hashes: steps };
}
