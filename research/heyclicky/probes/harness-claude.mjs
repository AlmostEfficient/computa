// Pure input/output conversion from the bundle; no streaming/fetch code evaluated.
import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const s=readFileSync(new URL('../evidence/harness-bundle.js',import.meta.url),'utf8');
const a=s.indexOf('var lI='),b=s.indexOf('function mI(',a),c=s.indexOf('function gI('),d=s.indexOf('async function zf(',c);
const {input,output}=new Function(s.slice(a,b)+s.slice(c,d)+';return {input:Nf,output:gI};')();
const request={model:'claude-haiku-5-5',input:[{role:'system',content:'first'},{role:'developer',content:'second'},{role:'user',content:[{type:'input_image',image_url:'https://example.invalid/image.png'},{type:'input_image',image_url:'data:image/png;base64,AAAA'},{type:'input_text',text:'hello'}]}],tools:[{type:'web_search'}],max_output_tokens:100000};
const mapped=input(request,{dropThinking:false});
assert.equal(mapped.max_tokens,64000);assert.equal(mapped.system[0].text,'first');assert.equal(mapped.messages[0].role,'user');assert.equal(mapped.messages[0].content[0].text,'second');assert.equal(mapped.messages[0].content.filter(x=>x.type==='image').length,1);
const blocks=[{type:'thinking',thinking:'synthetic reasoning',signature:'synthetic'},{type:'text',text:'synthetic answer'},{type:'tool_use',id:'fake',name:'fake_tool',input:{a:1}}];
const normalized=output(blocks);
const roundtrip=input({model:'claude-haiku-5-5',input:normalized},{dropThinking:false});
assert.equal(roundtrip.messages[0].content.length,3);
const stripped=input({model:'claude-haiku-5-5',input:normalized},{dropThinking:true});assert.equal(stripped.messages[0].content.length,2);
const result={scope:'Exact pure conversion functions with synthetic data; no requests or real images',ranges:[[a,b],[c,d]],mapped,normalized,roundtripBlockCount:3,strippedBlockCount:2,assertionsPassed:7};
writeFileSync(new URL('../evidence/harness-claude-probe.json',import.meta.url),JSON.stringify(result,null,2));console.log(JSON.stringify({assertionsPassed:7,sourceRanges:result.ranges}));
