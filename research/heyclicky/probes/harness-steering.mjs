// Exact steering methods in a synthetic holder; no job files, blobs or requests.
import{readFileSync,writeFileSync}from'node:fs';import assert from'node:assert/strict';
const s=readFileSync(new URL('../evidence/harness-bundle.js',import.meta.url),'utf8');const a=s.indexOf('beginSteering(A){'),b=s.indexOf('putBlob(A,e){',a);
const Holder=new Function('return class {'+s.slice(a,b)+'}')();const job=new Holder();Object.assign(job,{keys:new Set(),notes:[],modelNotes:new Map(),done:false,interrupted:false,cutOffTurn:null,getBlob:()=>null});
assert.equal(job.beginSteering(1).ok,true);assert.equal(job.addNote('first',1,{tag:1}).ok,true);
assert.deepEqual(job.takeNotes('model 1'),['first']);job.addNote('second',1);assert.deepEqual(job.takeNotes('model 1'),['first']);assert.equal(job.notes.length,1);
assert.deepEqual(job.takeNotes('model 2'),['second']);
job.interrupted=true;assert.equal(job.addNote('current',1).ok,false);assert.equal(job.addNote('future',2).ok,true);
const result={scope:'Exact methods with synthetic in-memory state; no account/job data',sourceCharacterRange:[a,b],modelRetryReusesNotes:true,newNotesWaitForNextModel:true,currentTurnRejectedWhenInterrupted:true,futureTurnAcceptedWhenInterrupted:true,assertionsPassed:8};writeFileSync(new URL('../evidence/harness-steering-probe.json',import.meta.url),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
