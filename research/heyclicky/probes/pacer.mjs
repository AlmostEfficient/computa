import assert from 'node:assert/strict';
  function Pacer(o) {
    o = o || {};
    const wps = o.wps || 2.6, gap = o.gap != null ? o.gap : 0.25, est = o.speech !== 'external', lead = o.lead != null ? o.lead : 0.08, tail = o.tail != null ? o.tail : 0.12;
    // HeyClicky screen canvas: how much a line may speed its strokes up (FAST) or slow them down (SLOW) to fit it
    const FAST = o.minPace != null ? o.minPace : 0.35, SLOW = o.maxSlow != null ? o.maxSlow : 2;
    // HeyClicky screen canvas: how far a line too full for its time (or one starting late) may hurry its strokes,
    // so its marks still end with its words. Without it, a crowded line stays at FAST and runs over.
    const RUSH = o.rushPace != null ? Math.min(o.rushPace, FAST) : FAST;
    // HeyClicky screen canvas: how far gaps between strokes may stretch to fill a line. Capped, an object's
    // parts (a sticky's paper and words, a badge's ring and number) stay together and spare time is a rest
    // at the end of the line instead of pauses inside the drawing.
    const MAXSPREAD = o.maxSpread != null ? o.maxSpread : Infinity;
    const lines = [], items = [];
    let closed = -1, all = false, rel = 0, rush = false;
    const count = s => String(s).trim().split(/\s+/).filter(Boolean).length;
    function addLine(text, t) { const p = lines[lines.length - 1]; lines.push({ k: lines.length, text, words: count(text), arrive: t, start: null, end: null, cum: p ? p.cum + p.words : 0 }); return lines.length - 1; }
    function add(m, i, t, nat) { const it = { m, i, arrive: t, line: undefined, dur: nat.dur, adv: nat.adv, t: null, p: 1, rt: null }; items.push(it); return it; }
    function times(k, memo) {
      if (k in memo) return memo[k];
      const L = lines[k]; let r = null;
      if (L) {
        let s = L.start;
        if (s == null && est) { const pe = k ? times(k - 1, memo) : null; if (!k || pe) s = Math.max(L.arrive, pe ? pe[1] + gap : L.arrive); }
        if (s != null) { const e = L.end != null ? L.end : s + L.words / wps; r = [s, Math.max(e, s + 0.2)]; }
      }
      return (memo[k] = r);
    }
    function plan(now) {
      if (rush) { let t = now; for (let i = rel; i < items.length; i++) { const it = items[i]; it.t = t; it.p = 0.35; it.gap = it.adv * 0.12; t += it.gap; } return; }  // finishNow: everything, quickly, in order
      const memo = {}, last = rel ? items[rel - 1] : null;
      let cursor = last ? Math.max(now, last.rt + last.gap) : now, i = rel;
      while (i < items.length) {
        const k = items[i].line;
        if (k === undefined) break;                             // still waiting for its say(): hold it and everything after it
        let j = i; while (j < items.length && items[j].line === k) j++;
        const grp = items.slice(i, j);
        if (k < 0) { for (const it of grp) { it.t = cursor; it.p = 1; it.gap = it.adv; cursor += it.adv; } i = j; continue; }
        const T = times(k, memo); if (!T) break;
        const ws = Math.max(cursor, T[0] + lead), avail = T[1] - tail - ws, isClosed = all || k <= closed;
        const A = grp.reduce((a, it, q) => a + (q < grp.length - 1 ? it.adv : 0), 0), dl = grp[grp.length - 1].dur;
        // spread so the last stroke ends as the line ends: gaps grow by `spread`, strokes slow down by at most SLOW
        let f = avail <= 0.05 ? 0 : avail / (A + dl || 0.1);
        if (!isClosed) f = Math.min(f, 1.3);                  // an open line may still get more strokes
        let p, spread;
        if (f < FAST) {
          // Too much for its time, or the line before ran over: strokes and gaps shrink together (down to RUSH) so
          // this line's marks end with its words and never push the next line's marks back.
          p = spread = Math.max(RUSH, f);
        } else {
          p = Math.min(f, SLOW); spread = f;
          if (isClosed && f > SLOW && A > 0) spread = Math.max(SLOW, (avail - SLOW * dl) / A);
        }
        spread = Math.min(spread, MAXSPREAD);
        let t = ws; for (const it of grp) { it.t = t; it.p = p; it.gap = it.adv * spread; t += it.gap; }
        cursor = t; i = j;
      }
      for (; i < items.length; i++) items[i].t = null;
    }
    function due(now) {
      const out = [];
      for (;;) { plan(now); const it = items[rel]; if (!it || it.t == null || it.t > now + 0.004) break; it.rt = now; rel++; out.push(it); }
      return out;
    }
    return {
      lines, items, addLine, add,
      assign: (it, k) => { it.line = k; }, close: k => { closed = Math.max(closed, k); }, closeAll: () => { all = true; }, rush: () => { rush = true; }, get rushed() { return rush; },
      start: (k, t) => { if (lines[k] && lines[k].start == null) lines[k].start = t; },
      end: (k, t) => { if (lines[k]) { if (lines[k].start == null) lines[k].start = t; lines[k].end = t; } },
      due, nextAt: now => { plan(now); const it = items[rel]; return it && it.t != null ? it.t : null; },
      empty: () => rel >= items.length, times: k => times(k, {}),
      // HeyClicky (a new turn on the same card): items not released yet whose mark matches `gone(i)` are dropped;
      // reopen() takes more lines and strokes after the program was done
      drop: gone => { const out = []; for (let q = items.length - 1; q >= rel; q--) if (gone(items[q].i)) out.push(items.splice(q, 1)[0]); return out; },
      reopen: () => { all = false; rush = false; }
    };
  }


const p=Pacer({speech:'external'});p.addLine('one two',0);
const mark=p.add({},0,0,{dur:0.2,adv:0.2});p.assign(mark,0);p.closeAll();
assert.equal(p.nextAt(0),null);assert.deepEqual(p.due(0),[]);
p.start(0,1);p.end(0,2);assert.equal(p.nextAt(0),1.08);
assert.equal(p.due(1).length,0);assert.equal(p.due(1.08).length,1);assert.equal(p.empty(),true);
console.log(JSON.stringify({scope:'original Pacer in isolation, synthetic speech timestamps',heldBeforeSpeech:true,scheduledAt:1.08,releasedMarks:1}));
