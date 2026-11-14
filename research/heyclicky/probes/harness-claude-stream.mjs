// Exact adapter code, fetch replaced by synthetic SSE transport. No network.
import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const s=readFileSync(new URL('../evidence/harness-bundle.js',import.meta.url),'utf8');
const a=s.indexOf('var lI='),b=s.indexOf('function Dc(',a);
const fakeGlobal={H1_ANTHROPIC_URL:'https://synthetic.invalid/messages'};
function fixture(stop,text){return [{type:'message_start',message:{usage:{input_tokens:2,cache_read_input_tokens:3,cache_creation_input_tokens:4}}},{type:'content_block_start',index:0,content_block:{type:'text',text:''}},{type:'content_block_delta',index:0,delta:{type:'text_delta',text}},{type:'content_block_stop',index:0},{type:'message_delta',delta:{stop_reason:stop},usage:{output_tokens:5}}].map(x=>'data: '+JSON.stringify(x)+'\n\n').join('');}
let requests=[];
const fakeFetch=async(url,opts)=>{requests.push(JSON.parse(opts.body));return new Response(fixture('pause_turn','part'+requests.length),{status:200,headers:{'content-type':'text/event-stream'}})};
class Fe extends Error{}
const run=new Function('fetch','globalThis','Fe',s.slice(a,b)+';return Hf;')(fakeFetch,fakeGlobal,Fe);
const result=await run('synthetic-token',{model:'claude-haiku-5-5',input:[{role:'user',content:'synthetic'}]});
assert.equal(requests.length,4);assert.equal(result.response.status,'completed');
const assistantBlocks=requests.map(r=>r.messages.filter(m=>m.role==='assistant').map(m=>m.content.length));
assert.deepEqual(assistantBlocks,[[],[1],[1,2],[1,2,3]]);
assert.equal(result.response.usage.input_tokens,36);assert.equal(result.response.usage.output_tokens,20);
let calls=0;const retryRequests=[];
const retryFetch=async(url,opts)=>{retryRequests.push(JSON.parse(opts.body));calls++;return calls===1?new Response('thinking bound to a different conversation',{status:400}):new Response(fixture('end_turn','done'),{status:200})};
const retry=new Function('fetch','globalThis','Fe',s.slice(a,b)+';return Hf;')(retryFetch,fakeGlobal,Fe);
await retry('synthetic-token',{model:'claude-haiku-5-5',prompt_cache_key:'test',input:[{type:'claude_turn',content:[{type:'thinking',thinking:'synthetic',signature:'synthetic'},{type:'text',text:'before'}]},{role:'user',content:'next'}]});
assert.equal(calls,2);assert.equal(retryRequests[0].messages[0].content[0].type,'thinking');assert.equal(retryRequests[1].messages[0].content[0].type,'text');
const evidence={scope:'Exact Claude adapter with injected fake fetch; synthetic SSE only. No network.',sourceCharacterRange:[a,b],pauseRequests:requests.length,assistantBlocks,exhaustedPauseStatus:result.response.status,normalizedUsage:result.response.usage,thinkingRetryCalls:calls,thinkingRemoved:true,assertionsPassed:8};
writeFileSync(new URL('../evidence/harness-claude-stream-probe.json',import.meta.url),JSON.stringify(evidence,null,2));console.log(JSON.stringify(evidence));
