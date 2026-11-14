import assert from 'node:assert/strict';
const BATCH_STEPS=['open','click','fill','press','scroll','wait_for','back','upload'];
const LOOKS=new Set(['snapshot','extract','screenshot','wait_for','download']);
const message=e=>String(e?.message??e);
let now=0; const calls=[];
const subject={limits:{batch:30000,batchSteps:20,batchReserve:3000},now:()=>now,
queued:async(id,work)=>{now=28000;return work()},hold:async()=>{},runTab:async req=>{calls.push(req);return {ok:true}},
  async batch(request, budget = this.limits.batch) {
    const {task, steps} = request;
    const max = this.limits.batchSteps;
    if (!Array.isArray(steps) || steps.length === 0 || steps.length > max) throw new Error(`batch needs 1 to ${max} steps.`);
    steps.forEach((step, index) => {
      if (!step || typeof step !== 'object' || !BATCH_STEPS.includes(step.operation)) throw new Error(`Step ${index + 1}: a batch step can be ${BATCH_STEPS.join(', ')}. Nothing ran.`);
      if (step.tabId != null && step.tabId !== request.tabId) throw new Error(`Step ${index + 1}: steps run in the batch's tab; leave tabId off the steps. Nothing ran.`);
      if (step.operation === 'open' && index > 0 && request.tabId == null) throw new Error(`Step ${index + 1}: only the first step can open a new tab. Nothing ran.`);
    });
    const deadline = this.now() + budget;
    const results = [];
    let tabId = request.tabId, index = 0;
    if (tabId == null) {
      if (steps[0].operation !== 'open') throw new Error('batch needs a tabId, or an open step first.');
      const opened = await this.openNew(task, steps[0].url, Math.min(deadline, this.now() + this.limits.load));
      tabId = opened.tabId; results.push({operation:'open', ...opened}); index = 1;
    }
    if (!Number.isInteger(tabId) || tabId < 0) throw new Error('A tabId from tabs/open is required.');
    const looks = steps.slice(index).every(step => LOOKS.has(step.operation));
    return this.queued(tabId, async () => {
      let stop = null;
      if (index === 0) await this.hold(task, tabId, looks); // Nothing ran yet, so a refusal simply throws.
      for (; index < steps.length && !stop; index++) {
        const step = steps[index], label = `Step ${index + 1} (${step.operation})`;
        if (deadline - this.now() < this.limits.batchReserve) { stop = {index, text:`The batch ran out of time before step ${index + 1}.`}; break; }
        try {
          const result = await this.runTab({...step, task, tabId, inBatch:true, afterSteps:index > 0, deadline: deadline - this.limits.batchReserve});
          results.push({operation:step.operation, ...result});
          if (result.loading) stop = {index, text:`${label} ran, but the page was still loading afterwards.`};
          else if (result.dialog) stop = {index, text:`${label} ran and the page opened a dialog; answer it with operation dialog.`};
        } catch (error) {
          results.push({operation:step.operation, error:message(error)});
          stop = {index, text:`${label} failed: ${message(error)}`};
        }
      }
      const out = {steps:results};
      if (stop) {
        const first = stop.index + 2, last = steps.length;
        out.error = stop.text + (first > last ? '' : first === last ? ` Step ${last} did not run.` : ` Steps ${first}-${last} did not run.`);
      }
      // The closing look gets what is left of the budget, so the whole call stays inside the app's timeout.
      try { out.snapshot = await this.runTab({task, tabId, operation:'snapshot', deadline:Math.max(deadline, this.now() + 1500)}); }
      catch (error) { out.snapshotError = message(error); }
      return out;
    });
  }
};
const result=await subject.batch({task:'t',tabId:1,steps:[{operation:'click'},{operation:'fill'}]});
assert.equal(result.steps.length,0);
assert.equal(calls.length,1);assert.equal(calls[0].operation,'snapshot');
assert.equal(result.error,'The batch ran out of time before step 1. Step 2 did not run.');
console.log(JSON.stringify({scope:'original batch body with synthetic clock and stubbed browser methods',result,actualActions:0,snapshotDeadline:calls[0].deadline}));
