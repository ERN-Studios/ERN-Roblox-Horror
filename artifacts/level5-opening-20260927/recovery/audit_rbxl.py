"""Read-only subset RBXL binary parser for source/hash and hierarchy audit.
Format: https://dom.rojo.space/binary.html (rbx-dom project's binary-format documentation).
Bounds-checks every chunk, known parsed fields, referent uniqueness and complete PRNT mapping.
No place writes, execution, or modifications. Other PROP payloads remain opaque.
"""
from pathlib import Path
import struct,hashlib,json,collections,sys
import lz4.block,zstandard
import numpy as np
ROOT=Path(__file__).resolve().parent
FILE=ROOT/'Studio-AutoRecovery-20260927-121430.rbxl'
BASE=ROOT.parent/'baseline/source-index.json'
binary=FILE.read_bytes();digest=hashlib.sha256(binary).hexdigest()
assert binary[:14]==b'<roblox!\x89\xff\r\n\x1a\n'
version,classesExpected,instancesExpected=struct.unpack_from('<HII',binary,14)
assert version==0 and binary[24:32]==b'\0'*8
class Reader:
 def __init__(self,data):self.data=data;self.pos=0
 def take(self,n):
  assert n>=0 and self.pos+n<=len(self.data),(self.pos,n,len(self.data))
  v=self.data[self.pos:self.pos+n];self.pos+=n;return v
 def u8(self):return self.take(1)[0]
 def u32(self):return struct.unpack('<I',self.take(4))[0]
 def string(self):return self.take(self.u32())
 def done(self):assert self.pos==len(self.data),(self.pos,len(self.data))
def words(r,n):
 a=np.frombuffer(r.take(4*n),dtype=np.uint8).reshape(4,n).astype(np.uint32)
 return (a[0]<<24)|(a[1]<<16)|(a[2]<<8)|a[3]
def refs(r,n):
 w=words(r,n).astype(np.int64)
 return np.cumsum((w>>1)^-(w&1)).tolist()
classes={};objects={};shared=[];chunks=[];pendingProps=[];parents=None;metadata={}
pos=32
while pos<len(binary):
 assert pos+16<=len(binary)
 name,compressed,uncompressed,reserved=struct.unpack_from('<4sIII',binary,pos);pos+=16
 size=compressed or uncompressed;assert pos+size<=len(binary)
 raw=binary[pos:pos+size];pos+=size
 if compressed:
  if raw.startswith(b'\x28\xb5\x2f\xfd'): data=zstandard.ZstdDecompressor().decompress(raw,max_output_size=uncompressed);codec='zstd'
  else:data=lz4.block.decompress(raw,uncompressed_size=uncompressed);codec='lz4'
 else:data=raw;codec='none'
 assert len(data)==uncompressed
 kind=name.rstrip(b'\0').decode('ascii');r=Reader(data)
 chunks.append({'name':kind,'compressedBytes':compressed,'decodedBytes':uncompressed,'codec':codec})
 if kind=='META':
  for _ in range(r.u32()):
   key=r.string().decode();value=r.string().decode();metadata[key]=value
  r.done()
 elif kind=='SSTR':
  assert r.u32()==0
  for _ in range(r.u32()):r.take(16);shared.append(r.string())
  r.done()
 elif kind=='INST':
  cid=r.u32();cname=r.string().decode();fmt=r.u8();n=r.u32();ids=refs(r,n)
  assert cid not in classes and len(set(ids))==n
  classes[cid]={'name':cname,'ids':ids}
  for iid in ids:
   assert iid not in objects
   objects[iid]={'class':cname,'name':cname}
  if fmt==1:r.take(n)
  else:assert fmt==0
  r.done()
 elif kind=='PROP':
  cid=r.u32();pname=r.string().decode();dtype=r.u8()
  if pname in {'Name','Source'}:
   pendingProps.append((cid,pname,dtype,r.take(len(data)-r.pos)))
 elif kind=='PRNT':
  assert parents is None and r.u8()==0
  n=r.u32();children=refs(r,n);pids=refs(r,n);r.done()
  assert n==instancesExpected and len(set(children))==n
  parents=dict(zip(children,pids))
 elif kind=='END':
  assert compressed==0 and data==b'</roblox>'
  assert pos==len(binary)
  break
assert chunks[-1]['name']=='END' and len(classes)==classesExpected and len(objects)==instancesExpected
assert parents is not None and set(parents)==set(objects)
for cid,pname,dtype,payload in pendingProps:
 ids=classes[cid]['ids'];r=Reader(payload)
 if dtype==1:values=[r.string() for _ in ids]
 elif dtype==0x1c:values=[shared[i] for i in words(r,len(ids)).tolist()]
 else:raise ValueError(f'Unsupported needed property type {classes[cid]["name"]}.{pname}: {dtype}')
 r.done()
 for iid,value in zip(ids,values):objects[iid][pname.lower()]=value.decode('utf-8') if pname=='Name' else value
children=collections.defaultdict(list)
for iid,parent in parents.items():
 assert parent==-1 or parent in objects
 assert iid!=parent
 children[parent].append(iid)
counts={};visiting=set()
def count(iid):
 if iid in counts:return counts[iid]
 assert iid not in visiting,'Hierarchy cycle';visiting.add(iid)
 value=sum(1+count(child) for child in children[iid]);counts[iid]=value;visiting.remove(iid);return value
assert sum(1+count(i) for i in children[-1])==instancesExpected
paths={}
def path(iid):
 if iid in paths:return paths[iid]
 parent=parents[iid];p=(() if parent==-1 else path(parent))+(objects[iid]['name'],);paths[iid]=p;return p
scriptclasses={'Script','LocalScript','ModuleScript'}
scripts=[]
for iid,o in objects.items():
 if o['class'] in scriptclasses:
  assert 'source' in o,('Missing Source',path(iid))
  scripts.append({'names':list(path(iid)),'path':'.'.join(path(iid)),'class':o['class'],'sourceBytes':len(o['source']),'sha256':hashlib.sha256(o['source']).hexdigest()})
base=json.loads(BASE.read_text());byPath={tuple(s['names']):s for s in scripts};assert len(byPath)==len(scripts),'Duplicate script name path'
comp=[]
for expected in base:
 actual=byPath.get(tuple(expected['names']))
 comp.append({'path':expected['path'],'present':actual is not None,'classMatch':actual is not None and actual['class']==expected['class'],'sourceHashMatch':actual is not None and actual['sha256']==expected['sha256'],'expectedSha256':expected['sha256'],'actualSha256':None if actual is None else actual['sha256']})
extra=[s for s in scripts if tuple(s['names']) not in {tuple(b['names']) for b in base}]
roots=[{'name':objects[i]['name'],'class':objects[i]['class'],'descendants':count(i)} for i in children[-1]]
world=next((i for i in children[-1] if objects[i]['class']=='Workspace'),None)
workspaceRoots=[] if world is None else [{'name':objects[i]['name'],'class':objects[i]['class'],'descendants':count(i)} for i in children[world]]
focus=[{'path':'.'.join(path(i)),'class':o['class'],'descendants':count(i)} for i,o in objects.items() if o['name']=='ServerLobby' or 'level6' in o['name'].lower().replace(' ','') and len(path(i))<=3]
report={'file':str(FILE),'bytes':len(binary),'sha256':digest,'fileHeaderVersion':version,'formatReference':'https://dom.rojo.space/binary.html','headerClassCount':classesExpected,'decodedClassCount':len(classes),'headerInstanceCount':instancesExpected,'decodedInstanceCount':len(objects),'allChunksDecompressedAndBoundsChecked':True,'completeHierarchyValidated':True,'endMarkerAndNoTrailingBytes':True,'metadata':metadata,'chunkSummary':dict(collections.Counter(c['name'] for c in chunks)),'compressionSummary':dict(collections.Counter(c['codec'] for c in chunks)),'scriptCount':len(scripts),'expectedScriptCount':len(base),'allExpectedSourceHashesMatch':all(r['sourceHashMatch'] and r['classMatch'] for r in comp),'extraScripts':extra,'scriptComparison':comp,'rootServices':roots,'workspaceChildren':workspaceRoots,'focusRoots':focus,'limitations':['Checks source text, hierarchy integrity and object counts. Does not compare every non-script property against live Studio.','Roblox PlaceVersion is not established by this parser; matching known v2150 sources and expected landmarks corroborates the checkpoint.','No Studio load or scripts executed; no Studio or repository mutations.']}
(ROOT/'offline-rbxl-audit.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in {'scriptComparison','rootServices','workspaceChildren'}},indent=2))
print('MISMATCHES',json.dumps([r for r in comp if not r['sourceHashMatch'] or not r['classMatch']]))
print('WORKSPACE_ROOTS',json.dumps(workspaceRoots))
