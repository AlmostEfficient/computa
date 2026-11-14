// Isolated shipped staging method; filename helper stubbed, no browser APIs.
import assert from 'node:assert/strict';
const MAX_STAGED_CHARS = 140 * 1024 * 1024;
const fileName = value => String(value);
const subject = {stages:new Map(),
  stageFile(task, {stageId, fileIndex, name, mimeType, size, lastModified, index, total, data}) {
    if (typeof stageId !== 'string' || !stageId || !Number.isInteger(fileIndex) || fileIndex < 0 || fileIndex >= 10 || !Number.isInteger(index) || !Number.isInteger(total) || total < 1 || typeof data !== 'string') throw new Error('Bad file chunk.');
    let stage = this.stages.get(stageId);
    if (stage && stage.task !== task) throw new Error('Bad file chunk.');
    if (!stage) { stage = {task, files:[], chars:0}; this.stages.set(stageId, stage); }
    const file = stage.files[fileIndex] ??= {name:fileName(name), mimeType:typeof mimeType === 'string' ? mimeType : '', size:Number(size) || 0, lastModified:Number(lastModified) || Date.now(), total, chunks:[]};
    stage.chars += data.length;
    if (index !== file.chunks.length || total !== file.total || stage.chars > MAX_STAGED_CHARS) { this.stages.delete(stageId); throw new Error('This upload is too large or arrived out of order.'); }
    file.chunks.push(data);
    return {stored:index + 1};
  }
};
const chunk = {stageId:'s',fileIndex:0,name:'sample.txt',size:1,index:0,total:1,data:'YQ=='};
assert.deepEqual(subject.stageFile('task',chunk),{stored:1});
assert.throws(()=>subject.stageFile('other',{...chunk,index:1}),/Bad file chunk/);
assert.equal(subject.stages.has('s'),true);
// Declared total is only checked later by the upload consumer.
assert.deepEqual(subject.stageFile('task',{...chunk,index:1}),{stored:2});
assert.equal(subject.stages.get('s').files[0].chunks.length,2);
assert.throws(()=>subject.stageFile('task',{...chunk,index:3}),/out of order/);
assert.equal(subject.stages.has('s'),false);
assert.throws(()=>subject.stageFile('task',{...chunk,fileIndex:10}),/Bad file chunk/);
console.log(JSON.stringify({passed:5,scope:'isolated original stageFile body; filename helper stubbed',findings:['cross-task rejection preserves stage','chunk count can exceed declared total at staging','out-of-order input deletes entire stage','file index 10 rejected','ordinary chunk accepted']}));
