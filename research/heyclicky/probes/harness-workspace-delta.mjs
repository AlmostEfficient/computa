// Extract only the snapshot comparison; provide synthetic maps, no filesystem/network.
import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const s=readFileSync(new URL('../evidence/harness-bundle.js',import.meta.url),'utf8');
const start=s.indexOf('function P2('),end=s.indexOf('async function x_(',start);
assert(start>=0&&end>start);
let snapshot=new Map();
const compare=new Function('xf','K2',s.slice(start,end)+';return P2;')(()=>snapshot,40);
const state={workspaceDir:'/synthetic',snapshot:new Map()};
snapshot=new Map(Array.from({length:45},(_,i)=>[`/synthetic/${i}`,{size:i,mtimeMs:1}]));
const first=compare(state);const second=compare(state);
assert.equal(first.length,40);assert.equal(second.length,0);assert.equal(state.snapshot.size,45);
snapshot=new Map(snapshot);snapshot.delete('/synthetic/0');const deleted=compare(state);assert.equal(deleted.length,0);
snapshot=new Map(snapshot);snapshot.set('/synthetic/1',{size:1,mtimeMs:1});const unchangedMetadata=compare(state);assert.equal(unchangedMetadata.length,0);
const result={scope:'Exact P2 function with mocked xf snapshots. No real files or target execution.',sourceCharacterRange:[start,end],firstReturned:first.length,secondReturned:second.length,baselineEntriesAfterFirst:45,deletionReturned:deleted.length,unchangedMetadataReturned:unchangedMetadata.length,assertionsPassed:5};
writeFileSync(new URL('../evidence/harness-workspace-delta-probe.json',import.meta.url),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
