import{readFileSync,writeFileSync}from'node:fs';import assert from'node:assert/strict';
const s=readFileSync(new URL('../evidence/harness-bundle.js',import.meta.url),'utf8');const a=s.indexOf('function df('),b=s.indexOf('function g2(',a);
const {timeout,normalize}=new Function(s.slice(a,b)+';return {timeout:h2,normalize:df};')();
const inputs=[0,1,9999,10000,300000,Infinity,-1];const outputs=inputs.map(x=>timeout(x,300));assert.deepEqual(outputs,[300,1,1200,10,300,300,300]);
const normalized=normalize({a:null,b:[null,{x:null,y:1}]});assert.deepEqual(normalized,{b:[null,{y:1}]});
const result={scope:'Exact pure timeout/argument functions; no shell or file tools executed',sourceCharacterRange:[a,b],inputs:inputs.map(String),outputs,normalized,assertionsPassed:2};writeFileSync(new URL('../evidence/harness-local-limits-probe.json',import.meta.url),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
