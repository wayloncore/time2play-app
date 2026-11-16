// The app's offline rooms (#402): the website's own room cores (rules and bots), run inside the app with no server.
// This file is plumbing only, a small stand-in for src/live/overdraft/room-do.js: it passes a phone's messages to the
// game's core and hands back the same views the server would send. No rule of any game is written here.
// scripts/rules-bundle.mjs bundles it with the cores into Core/Sources/T2PCore/Resources/rules.js.
import Overdraft from '@site/src/live/overdraft/room-core.cjs';
import * as Farkle from '@site/src/live/farkle/room-core.js';
import * as RollCall from '@site/src/live/rollcall/room-core.js';
import * as CloseEnough from '@site/src/live/closeenough/room-core.js';
import { scoringOptions } from '@site/src/games/farkle/scoring.js';
import { parityRun } from './parity.js';

export const CORES = { overdraft: Overdraft, farkle: Farkle, rollcall: RollCall, closeenough: CloseEnough };

/** One offline room: you and the bots. */
export class OfflineRoom {
	constructor(game, seed, now) {
		this.game = game;
		this.core = CORES[game];
		this.R = this.core.createRoom({ code: 'SOLO', seed, now, tournament: false });
		this.core.claim(this.R, now, { hostless: true });
		this.me = null;
	}
	/** What the room says back to one message: the same messages room-do.js would send this phone. */
	handle(msg, now) {
		const C = this.core, R = this.R, out = [], key = R.hostToken;
		let res = { ok: true };
		switch (msg.t) {
			case 'hello': return [{ t: 'hello', v: 1, min: 1, game: this.game, update: false, account: null }];
			case 'ping': return [{ t: 'pong' }];
			case 'join':
				if (this.me) { out.push({ t: 'joined', ...this.me }); break; }
				res = C.join(R, { name: msg.name, face: msg.face }, now);
				if (res.ok) { this.me = { id: res.id, token: res.token, name: res.name }; out.push({ t: 'joined', ...this.me }); }
				break;
			case 'resume': res = this.me && msg.id === this.me.id ? C.resume(R, msg.id, msg.token, now) : { ok: false, error: 'No such player.', code: 'gone' }; if (res.ok) out.push({ t: 'resumed', id: msg.id }); break;
			case 'react': return this.me ? [{ t: 'react', id: this.me.id, r: msg.r }] : [];
			case 'addbot': res = C.addBot(R, key, msg.level, now); break;
			case 'remove': res = C.remove(R, key, msg.target, now); break;
			case 'deal': res = C.deal(R, key, now); break;
			case 'again': res = C.again(R, key, now); break;
			case 'options': res = C.setOptions(R, key, this.game === 'farkle' ? { ones: msg.ones, target: msg.target, board: msg.board, three: msg.three } : this.game === 'rollcall' ? { quick: msg.quick } : this.game === 'closeenough' ? { set: msg.set, count: msg.count, timer: msg.timer } : { stacking: msg.stacking, jumpIn: msg.jumpIn }); break;
			case 'close': case 'leave': return [{ t: 'ended' }];
			default: res = this.me ? C.act(R, this.me.id, this.me.token, msg, now) : { ok: false, error: 'Join first.' };
		}
		if (!res.ok) out.push(res.code ? { t: 'error', error: res.error, code: res.code } : { t: 'error', error: res.error });
		C.settleOwner?.(R);
		this.tick(now);
		return out.concat(this.views());
	}
	/** The room's clock (bots' turns, reveals, timeouts), run up to now. */
	tick(now) {
		const due = this.core.nextDeadline(this.R);
		if (due == null || due > now) return false;
		const t = this.core.tick(this.R, now);
		this.core.settleOwner?.(this.R);
		return !!(t && (t.changed || (t.gone && t.gone.length) || (t.held && t.held.length)));
	}
	next() { return this.core.nextDeadline(this.R); }
	views() {
		if (!this.me) return [];
		const v = this.core.viewFor(this.R, this.me.id, this.me.token);
		return [v.ok ? { t: 'you', ...v } : { t: 'error', error: v.error }];
	}
}

const rooms = new Map();
let nextRoom = 1;
/** What Swift calls (JavaScriptCore): JSON text in and out, so nothing but strings crosses. */
globalThis.T2POffline = {
	open(game, seed, now) { const id = nextRoom++; rooms.set(id, new OfflineRoom(game, seed >>> 0, now)); return id; },
	send(id, text, now) { const r = rooms.get(id); return JSON.stringify(r ? r.handle(JSON.parse(text), now) : [{ t: 'ended' }]); },
	tick(id, now) { const r = rooms.get(id); return JSON.stringify(r && r.tick(now) ? r.views() : []); },
	next(id) { const r = rooms.get(id); const n = r ? r.next() : null; return n == null ? -1 : n; },
	close(id) { rooms.delete(id); },
	parity(game, seed) { return JSON.stringify(parityRun(game, seed, OfflineRoom)); },
	/** Hot Dice (#488): which faces in a roll can score, by the website's own scoringOptions (its phone marks the rest
	    "dead" the same way). values: the live dice's faces as JSON; ones: what three 1s score. Returns the faces as JSON. */
	scoring(values, ones) {
		const faces = new Set();
		for (const o of scoringOptions(JSON.parse(values).map((value, id) => ({ id, value })), ones || 1000)) for (const k of o.key) faces.add(Number(k));
		return JSON.stringify([...faces].sort());
	}
};
