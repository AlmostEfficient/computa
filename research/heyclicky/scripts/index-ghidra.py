"""Index retained Ghidra text without claiming decompilation correctness/completeness."""
import argparse, hashlib, json, re
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('source');p.add_argument('output');p.add_argument('--partial',action='store_true');a=p.parse_args()
b=Path(a.source).read_bytes();marks=list(re.finditer(rb'^/\* ([^\n]+) @ ([0-9a-fA-F]+) \*/$',b,re.M));rows=[]
for i,m in enumerate(marks):
 end=marks[i+1].start() if i+1<len(marks) else len(b);chunk=b[m.start():end]
 rows.append({'name':m[1].decode(),'address':m[2].decode(),'byte_start':m.start(),'byte_end':end,'failure':'Decompilation failed:' in chunk.decode('utf8','replace'),'warnings':chunk.count(b'WARNING:'),'tail_may_be_incomplete':a.partial and i==len(marks)-1})
out={'source':a.source,'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b),'partial':a.partial,'scope':'Text export index, not function discovery coverage or semantic correctness','functions':rows,'counts':{'headers':len(rows),'failures':sum(r['failure']for r in rows),'warnings':sum(r['warnings']for r in rows)}}
Path(a.output).write_text(json.dumps(out,indent=2));print(json.dumps({k:v for k,v in out.items()if k!='functions'}))
