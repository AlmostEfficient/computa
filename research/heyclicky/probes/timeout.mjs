import assert from 'node:assert/strict';
const subject={
  async withinLimit(promise, limitMs) {
    let timer;
    const expired = new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('The page did not respond in time (it may be a sleeping background tab). Nothing was changed; try again, or open the page in a tab of your own.')), limitMs); });
    try { return await Promise.race([promise, expired]); } finally { clearTimeout(timer); }
  }
};
let finished=false;
const operation=new Promise(resolve=>setTimeout(()=>{finished=true;resolve()},30));
await assert.rejects(subject.withinLimit(operation,1),/Nothing was changed/);
await operation;
assert.equal(finished,true);
console.log(JSON.stringify({scope:'original withinLimit with synthetic delayed operation',timedOut:true,underlyingOperationFinished:true,conclusion:'timeout does not cancel the supplied promise'}));
