import json,struct
from pathlib import Path
root=Path(__file__).resolve().parents[1]; layout=json.loads((root/'evidence/native-mach-o-layout.json').read_text()); b=Path('/tmp/codex-heyclicky/HeyClicky-arm64').read_bytes()
def offset(a):
 for s in layout['segments']:
  base=int(s['address'],16)
  if base<=a<base+s['file_size']:return s['file_offset']+a-base
 raise ValueError(hex(a))
def u32(a):return struct.unpack_from('<I',b,offset(a))[0]
def rel(a):
 n=struct.unpack_from('<i',b,offset(a))[0];return a+n if n else 0
def string(a):
 o=offset(a);end=b.index(0,o);return b[o:end].decode('utf8')
sec=next(s for s in layout['sections'] if s['name']=='__swift5_types'); rows=[];errors=[]
for i in range(sec['size']//4):
 a=int(sec['address'],16)+4*i
 try:
  desc=rel(a);kind=u32(desc)&31
  if kind not in [16,17,18]:raise ValueError('unexpected kind '+str(kind))
  name=string(rel(desc+8));fd=rel(desc+16);fields=[]
  if fd:
   k,rs,n=struct.unpack_from('<HHI',b,offset(fd)+8)
   if rs<12 or n>20000:raise ValueError('invalid field header')
   for j in range(n):
    rec=fd+16+j*rs;fields.append({'name':string(rel(rec+8)),'flags':u32(rec),'record':hex(rec),'type_reference':hex(rel(rec+4)) if rel(rec+4) else None})
  rows.append({'entry':hex(a),'descriptor':hex(desc),'kind':kind,'name':name,'field_descriptor':hex(fd) if fd else None,'fields':fields})
 except Exception as e:errors.append({'entry':hex(a),'error':str(e)})
(root/'evidence/swift-type-fields.json').write_text(json.dumps({'method':'relative type descriptors and field records; generic type references not resolved','types':rows,'errors':errors},indent=2)+'\n')
print('types',len(rows),'errors',len(errors))
for r in rows:
 if r['name'] in ['DictationGeminiTranscriber','ClickyDictationController','OneBrainGeminiTranscriber','ClickyJobStore']:print(r['name'],[x['name'] for x in r['fields']])
