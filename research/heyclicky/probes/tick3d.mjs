import assert from 'node:assert/strict';
const global={}, logs=[], HOST={log:x=>logs.push(x)},slowTicks={};
let clock=0; const Date={now:()=>clock};
const live={ticks:{tick:()=>{clock+=9}},anim:{sp1:{pos:[1,2,3],color:'#ff8000',show:false}}};
const session={live3d:()=>live};const subject={
    tick3d({ stage, ticks, dt }) {
      const live = session && session.live3d ? session.live3d() : null;
      if (!live || !live.ticks) return null;
      for (const entry of ticks || []) {
        const id = entry[0], fn = live.ticks[id];
        if (typeof fn !== 'function') continue;
        const started = Date.now();
        // Pose writes inside a tick set this frame's pose (outside one they become timed moves: the engine's handle).
        global.__clickyInTick3d = true;
        try { fn(+entry[1] || 0, +dt || 1 / 60); }
        catch (e) { delete live.ticks[id]; HOST.log(`tick ${id} stopped: ${e && e.message}`); continue; }
        finally { global.__clickyInTick3d = false; }
        if (Date.now() - started > 8) {
          slowTicks[id] = (slowTicks[id] || 0) + 1;
          if (slowTicks[id] > 5) { delete live.ticks[id]; HOST.log(`tick ${id} stopped: too slow`); }
        }
      }
      const prefix = stage + 'p', out = [];
      for (const id in live.anim) {
        if (!id.startsWith(prefix)) continue;
        const n = +id.slice(prefix.length), a = live.anim[id];
        if (!(n > 0) || !a) continue;
        let mask = 0;
        const p = a.pos || [0, 0, 0], r = a.rot || [0, 0, 0];
        if (a.pos) mask |= 1; if (a.rot) mask |= 2; if (a.scale != null) mask |= 4; if (a.show != null) mask |= 8; if (a.glow != null) mask |= 16;
        let rgb = [0, 0, 0];
        const hex = typeof a.color === 'string' ? /^#?([0-9a-f]{6})$/i.exec(a.color.trim()) : null;
        if (hex) { const v = parseInt(hex[1], 16); rgb = [(v >> 16 & 255) / 255, (v >> 8 & 255) / 255, (v & 255) / 255]; mask |= 32; }
        out.push(n, mask, p[0], p[1], p[2], r[0], r[1], r[2], a.scale != null ? a.scale : 1, a.show === false ? 0 : 1, a.glow || 0, rgb[0], rgb[1], rgb[2]);
      }
      return new Float32Array(out);
    },

};
for(let i=0;i<5;i++)subject.tick3d({stage:'s',ticks:[['tick',0]],dt:0});
assert.equal(typeof live.ticks.tick,'function');
const out=subject.tick3d({stage:'s',ticks:[['tick',0]],dt:0});
assert.equal(live.ticks.tick,undefined);assert.equal(out.length,14);assert.equal(out[1],41);assert.equal(out[9],0);assert.equal(out[11],1);
assert.equal(global.__clickyInTick3d,false);
console.log(JSON.stringify({scope:'original tick3d method with synthetic clock/host/session',slowTickRemovedAfter:6,record:Array.from(out),logs}));
