// Exact pure dimension/budget functions, synthetic strings only; no image processing.
import{readFileSync,writeFileSync}from'node:fs';import assert from'node:assert/strict';
const s=readFileSync(new URL('../evidence/harness-bundle.js',import.meta.url),'utf8');
const a=s.indexOf('function Qo('),b=s.indexOf('function b$(',a),c=s.indexOf('var q$='),d=s.indexOf('var ce=',c);
const {size,budget}=new Function('bi','Rp','h$',s.slice(a,b)+s.slice(c,d)+';return {size:B$,budget:Pp};')(32,16000,16000000);
const dims=size(10000,10000);assert(Math.ceil(dims.width/32)*Math.ceil(dims.height/32)<=16000);assert.equal(size(100,100),null);
const mk=n=>({type:'message',role:'user',content:[{type:'input_image',image_url:'data:'+ 'x'.repeat(n-5)}]});
const cases=[[120],[60,60],[30,30,30,30],[10,120]];
const rows=cases.map(lengths=>{const output=budget(lengths.map(mk),100);return{lengths,kept:output.flatMap(x=>x.content).filter(x=>x.type==='input_image').map(x=>x.image_url.length)}});
assert.deepEqual(rows[0].kept,[120]);assert.deepEqual(rows[1].kept,[60,60]);assert.deepEqual(rows[2].kept,[30,30,30]);assert.deepEqual(rows[3].kept,[120]);
const result={scope:'Exact pure dimension and request-budget functions, scaled synthetic budget 100 characters, no real images or requests',sourceRanges:[[a,b],[c,d]],resizedDimensions:dims,cases:rows,assertionsPassed:6};
writeFileSync(new URL('../evidence/harness-image-budget-probe.json',import.meta.url),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
