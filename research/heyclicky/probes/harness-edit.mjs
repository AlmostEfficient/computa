// Exact pure edit algorithm. Synthetic strings only, no files changed.
import{readFileSync,writeFileSync}from'node:fs';import assert from'node:assert/strict';
const s=readFileSync(new URL('../evidence/harness-bundle.js',import.meta.url),'utf8');const a=s.indexOf('function go('),b=s.indexOf('function V0(',a);const edit=new Function(s.slice(a,b)+';return Ld;')();
const original='Keep “this”  \nChange “that” — elsewhere  \nUntouched — here  \n';
const changed=edit(original,[{oldText:'"that"',newText:'"new"'}],'synthetic');
assert.equal(changed.newContent,'Keep “this”  \nChange "new" - elsewhere\nUntouched — here  \n');
assert.throws(()=>edit('x “a”\nx "a"\n',[{oldText:'"a"',newText:'b'}],'synthetic'),/occurrences/);
assert.throws(()=>edit('abcd',[{oldText:'abc',newText:'X'},{oldText:'bc',newText:'Y'}],'synthetic'),/overlap/);
assert.throws(()=>edit('one',[{oldText:'one',newText:'two'},{oldText:'two',newText:'three'}],'synthetic'),/find/);
const result={scope:'Exact Ld and helpers with synthetic strings only',sourceCharacterRange:[a,b],original,result:changed.newContent,normalizedAmbiguityRejected:true,overlapRejected:true,incrementalMatchRejected:true,assertionsPassed:4};writeFileSync(new URL('../evidence/harness-edit-probe.json',import.meta.url),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
