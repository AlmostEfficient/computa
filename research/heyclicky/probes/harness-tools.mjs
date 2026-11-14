// Pure schema/name/classification functions; fake tool definitions, no tool calls.
import{readFileSync,writeFileSync}from'node:fs';import assert from'node:assert/strict';
const s=readFileSync(new URL('../evidence/harness-bundle.js',import.meta.url),'utf8');
const a=s.indexOf('var kI=new Set'),b=s.indexOf('function Bn(',a);
const {map,write}=new Function('hi',s.slice(a,b)+';return {map:ep,write:FI};')([]);
const mapped=map([{server:'a',tools:[{name:'get.item',inputSchema:{type:'object',properties:{date:{type:'string',format:'date-time'}},readOnly:true}},{name:'get/item'},{name:'constructor'},{name:'web_search'}]},{server:'b',tools:[{name:'get_item'}]}]);
assert.equal(mapped.defs.length,1);assert.equal(mapped.index.get_item.server,'a');assert.equal(mapped.defs[0].parameters.properties.date.format,undefined);assert.equal(mapped.defs[0].parameters.properties.date.description,'(format: date-time)');
const cases=[['device','device_read_file',{},false],['device','device_open',{},true],['x','browser',{operation:'snapshot'},false],['x','browser',{operation:'navigate'},true],['x','GET_AND_DELETE',{},true],['x','DOWNLOAD_FILE',{},false],['x','COMPOSIO_MULTI_EXECUTE_TOOL',{tools:[]},true]];
for(const [server,tool,args,expected]of cases)assert.equal(write(server,tool,args),expected);
const result={scope:'Pure exact-source name/schema mapping and read/write classification, synthetic definitions only',sourceCharacterRange:[a,b],mapped,classification:cases.map(([server,tool,args,expected])=>({server,tool,args,isWrite:expected})),assertionsPassed:11};
writeFileSync(new URL('../evidence/harness-tools-probe.json',import.meta.url),JSON.stringify(result,null,2));console.log(JSON.stringify({assertionsPassed:11,mappedNames:mapped.defs.map(x=>x.name)}));
