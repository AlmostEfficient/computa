import assert from 'node:assert/strict';
const VIEW_SKIP = new Set(['role', 'name', 'ref']);
export function snapshotLines(snapshot) {
  return (snapshot?.nodes ?? []).map(node => {
    let line = node.role === 'StaticText' ? 'text' : node.role;
    const name = String(node.name ?? '').replace(/\s+/g, ' ').trim();
    if (name) line += `: ${name}`;
    for (const [key, value] of Object.entries(node)) if (!VIEW_SKIP.has(key)) line += value === true || value === 'true' ? ` (${key})` : ` (${key}=${value})`;
    if (node.ref) line += ` [${node.ref}]`;
    return line;
  });
}
export class ModelView {
  constructor() { this.seen = new Map(); }
  /// tabId → the lines the model last saw for that page.
  render(snapshot, tabId, fromAction, partial = false) {
    const lines = snapshotLines(snapshot);
    const {nodes, ...rest} = snapshot;
    if (partial) return {...rest, elements: lines.join('\n')}; // A query's subset is not the page.
    const key = String(tabId);
    const previous = this.seen.get(key);
    this.seen.set(key, {url: snapshot.url, lines});
    if (fromAction && previous && previous.url === snapshot.url && lines.length) {
      const before = new Set(previous.lines), after = new Set(lines);
      const added = lines.filter(line => !before.has(line)), removed = previous.lines.filter(line => !after.has(line));
      const kept = lines.length - added.length;
      if (kept >= lines.length * 0.5 && added.length + removed.length <= Math.max(40, lines.length * 0.3)) {
        const {note: _note, ...meta} = rest;
        if (!added.length && !removed.length) return {...meta, unchanged: true, note: 'Nothing on the page changed; your last snapshot still applies.'};
        return {...meta, added, removed, note: `Only what changed since your last look at this page (${kept} other elements as before, refs unchanged).`};
      }
    }
    return {...rest, elements: lines.join('\n')};
  }
  forModel(result, request = {}) {
    if (!result || typeof result !== 'object') return result;
    const tabId = request.tabId ?? result.tabId;
    // A query's or an interactive snapshot's subset is not the whole page: never the base for an action's changes.
    if (Array.isArray(result.nodes)) return this.render(result, tabId, false, Boolean(request.query) || request.interactive === true);
    const out = {...result};
    if (out.snapshot && Array.isArray(out.snapshot.nodes)) out.snapshot = this.render(out.snapshot, out.tabId ?? tabId, true);
    if (Array.isArray(out.steps)) out.steps = out.steps.map(step => step?.snapshot?.nodes ? {...step, snapshot: this.render(step.snapshot, step.tabId ?? tabId, true)} : step);
    return out;
  }
  forget(tabId) { this.seen.delete(String(tabId)); }
}


const v=new ModelView();
const a={role:'button',name:'A',ref:'e1'},b={role:'button',name:'B',ref:'e2'};
const snapshot=nodes=>({url:'https://example.invalid/',nodes});
v.render(snapshot([a,b]),1,false);
assert.equal(v.render(snapshot([b,a]),1,true).unchanged,true);
v.render(snapshot([a]),1,false,true);
assert.equal(v.render(snapshot([a,b]),1,true).unchanged,true);
const changed=v.render({...snapshot([a,b]),url:'https://example.invalid/next'},1,true);
assert.equal(typeof changed.elements,'string');
console.log(JSON.stringify({passed:3,scope:'original snapshotLines and ModelView on synthetic data only',findings:['reordering alone reported unchanged','partial snapshot preserves full baseline','URL change emits full elements']}));
