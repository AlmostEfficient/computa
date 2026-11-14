// Execute only extracted jp with fake tools and accelerated watchdog ticks.
import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('../evidence/harness-bundle.js',import.meta.url),'utf8');
const start=source.indexOf('async function jp('),end=source.indexOf('var zI=',start);
const ap=x=>typeof x==='string'?x:JSON.stringify(x,null,1);
const make=(interval=setInterval,clear=clearInterval)=>new Function('HI','ap','setInterval','clearInterval',source.slice(start,end)+';return jp;')(new Set(['mac_step']),ap,interval,clear);
const jp=make();
const visibility=await jp('return [typeof process,typeof require,typeof Bun,typeof globalThis,typeof fetch,typeof setTimeout]',{hasTool:()=>false,callTool:()=>{throw Error('unexpected')}});
assert.equal(visibility.ok,true);assert.deepEqual(JSON.parse(visibility.output),['undefined','undefined','undefined','undefined','function','function']);
const store=await jp('store("x",{a:1});const v=load("x");v.a=2;return load("x")',{hasTool:()=>false});
assert.equal(JSON.parse(store.output).a,1);
let release,completed=false;
const accelerated=make(cb=>setTimeout(()=>{for(let i=0;i<180;i++)cb()},0),clearTimeout);
const timed=await accelerated('await tools.fake();text("after")',{hasTool:()=>true,callTool:()=>new Promise(resolve=>{release=()=>{completed=true;resolve({ok:true,text:'{}'})}})});
assert.equal(timed.ok,false);assert.equal(completed,false);
release();await new Promise(resolve=>setTimeout(resolve,0));assert.equal(completed,true);
const result={scope:'Exact jp with fake tool and accelerated interval (180 ticks); no network, app startup, files accessed by target, or real tool actions',sourceCharacterRange:[start,end],visibility:JSON.parse(visibility.output),loadIsCopy:true,timeoutResult:timed.output,fakeToolCompletedAfterTimeout:completed,assertionsPassed:6};
writeFileSync(new URL('../evidence/harness-script-probe.json',import.meta.url),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
