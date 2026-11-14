// Pure scheduling validation and in-memory projection; no schedule creation.
import{readFileSync,writeFileSync}from'node:fs';import assert from'node:assert/strict';
const s=readFileSync(new URL('../evidence/harness-bundle.js',import.meta.url),'utf8');const a=s.indexOf('var UI='),b=s.indexOf('var HI=',a);
const {validate,project}=new Function(s.slice(a,b)+';return {validate:ip,project:op};')();
const created=validate({action:'create',title:'One',task:'synthetic',every_minutes:2880,time_of_day:'09:00'},[],'UTC');assert.equal(created.ok,true);assert.equal(created.block.time_of_day,undefined);
const existing=[{title:'One',taskPrompt:'synthetic',everyMinutes:1440,timeOfDay:'09:00',timezone:'UTC'}];
const timezoneOnly=validate({action:'update',title:'One',timezone:'Europe/London'},existing,'UTC');assert(timezoneOnly.error);
const update=validate({action:'update',title:'One',every_minutes:60},existing,'UTC');assert.equal(update.ok,true);const projected=project(existing,update.routine);assert.equal(projected[0].timeOfDay,'09:00');
const duplicateRename=validate({action:'update',title:'One',new_title:'Two'},[...existing,{title:'Two'}],'UTC');assert.equal(duplicateRename.ok,true);
const result={scope:'Exact validator and local projection with synthetic routine list; no schedules changed',sourceCharacterRange:[a,b],created,timezoneOnly,update,projected,duplicateRename,assertionsPassed:6};writeFileSync(new URL('../evidence/harness-routines-probe.json',import.meta.url),JSON.stringify(result,null,2));console.log(JSON.stringify({assertionsPassed:6}));
