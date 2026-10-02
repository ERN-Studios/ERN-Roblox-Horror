"""Synthetic local export-guard fixtures; no Studio, network or Git/index operations."""
from pathlib import Path
import hashlib,json,subprocess,sys,tempfile
repo=Path(__file__).resolve().parents[4];tool=Path(__file__).resolve().with_name('finish_export.py');compile(tool.read_bytes(),str(tool),'exec')
root=Path(tempfile.mkdtemp(prefix='lobby-polish-concurrent-export-fixtures-20261002-',dir='/private/tmp'));before=root/'before';after=root/'after';before.mkdir(exist_ok=True);after.mkdir(exist_ok=True)
sha=lambda b:hashlib.sha256(b).hexdigest();canon=lambda x:json.dumps(x,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def put(path,x):path.write_bytes(json.dumps(x).encode())
def row(path,source,cls='ModuleScript'):
 b=source.encode();return {'path':path,'class':cls,'source':source,'sourceBytes':len(b),'sourceSha256':sha(b),'editorSourceSha256':sha(b),'editorMatch':True}
expected={'ServerScriptService.LobbyReimaginedPreview.Builder':'ModuleScript','ServerScriptService.LobbyReimaginedPreview.EndBlockades':'ModuleScript','ServerScriptService.LobbyReimaginedPreview.MaterialPolish':'ModuleScript','ServerScriptService.LobbyReimaginedPreview.LobbyPolishBays':'ModuleScript','ServerScriptService.LobbyReimaginedPreview.LobbyPolishScene':'ModuleScript','StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController':'LocalScript'}
own=[];pins=[]
for n,(path,cls) in enumerate(expected.items()):
 r=row(path,f'return {n}\n',cls);file=root/f'candidate-{n}.luau';file.write_bytes(r['source'].encode());own.append(r);pins.append({'path':path,'className':cls,'file':str(file),'sha256':r['sourceSha256'],'new':path.endswith(('MaterialPolish','LobbyPolishBays','LobbyPolishScene'))})
oldforeign=row('ServerScriptService.OtherDeveloper','return "old"\n','Script');newforeign=row(oldforeign['path'],'return "new"\n','Script');qa=row('ServerScriptService.OtherDeveloperQA','return "Studio only QA"\n','Script')
oldrows=own+[oldforeign];newrows=own+[newforeign,qa];put(before/'scripts.json',oldrows);put(after/'scripts.json',newrows)
oldnative=b'fixture before native';native=b'fixture after native';(before/'all-service-children.rbxm').write_bytes(oldnative);(after/'all-service-children.rbxm').write_bytes(native)
base={'placeId':131311258779917,'universeId':10559217407,'groupId':1039373905,'editorConflicts':[],'skipped':[],'rootCount':2,'placeVersion':2495,'capturedAt':'synthetic fixture'}
oldmeta=dict(base,captureId='before-fixture',scriptCount=len(oldrows),nativeSHA256=sha(oldnative));meta=dict(base,captureId='after-fixture',scriptCount=len(newrows),nativeSHA256=sha(native),nativeBytes=len(native),sourceTransfer={'sha256':sha((after/'scripts.json').read_bytes()),'bytes':(after/'scripts.json').stat().st_size});put(before/'metadata.json',oldmeta);put(after/'metadata.json',meta)
for filename in ['metadata.received.json','backup-metadata-summary.json','backup-file-hashes.json','source-manifest.json','checkpoint-reuse-proof.json','native-recovery-reopen-verification.json']:put(after/filename,{'fixture':True})
put(after/'checkpoint-install-gate.json',{'verified':True,'captureId':meta['captureId'],'nativeSHA256':sha(native),'files':[{'file':'all-service-children.rbxm','bytes':len(native),'sha256':sha(native)}]})
pinfile=root/'pins.json';put(pinfile,pins)
source_deltas=[{'path':oldforeign['path'],'class':'Script','kind':'changed','beforeSHA256':oldforeign['sourceSha256'],'afterSHA256':newforeign['sourceSha256'],'beforeBytes':oldforeign['sourceBytes'],'afterBytes':newforeign['sourceBytes']},{'path':qa['path'],'class':'Script','kind':'added','beforeSHA256':None,'afterSHA256':qa['sourceSha256'],'beforeBytes':None,'afterBytes':qa['sourceBytes']}]
native_deltas=[{'path':'ServerScriptService.OtherDeveloper','kind':'savedRootFingerprintChanged','beforeCanonicalSHA256':'1'*64,'afterTaskNormalizedCanonicalSHA256':'2'*64}]
report={'verified':False,'taskScopeVerified':True,'wholeForestPreservedBeyondTaskScope':False,'serverLobby':{'unchangedBeyondTaskScope':True},'beforeCaptureId':oldmeta['captureId'],'afterCaptureId':meta['captureId'],'beforeNativeSHA256':sha(oldnative),'afterNativeSHA256':sha(native),'beforeSourceCount':len(oldrows),'afterSourceCount':len(newrows),'afterRootCount':2,'frozenSourcesSHA256':sha(pinfile.read_bytes()),'unclassifiedConcurrentSourceDeltas':source_deltas,'unclassifiedConcurrentNativeDeltas':native_deltas,'errors':{}}
reportfile=root/'report.json';put(reportfile,report)
review={'schema':'lobby-polish-reviewed-concurrent-export-v1','approvedForTaskSourceExportOnly':True,'reviewedBy':'local fixture reviewer','reviewPurpose':'synthetic task-source extraction only','nativeAuditSHA256':sha(reportfile.read_bytes()),'beforeCaptureId':oldmeta['captureId'],'afterCaptureId':meta['captureId'],'beforeNativeSHA256':sha(oldnative),'afterNativeSHA256':sha(native),'beforeSourceCatalogSHA256':sha((before/'scripts.json').read_bytes()),'afterSourceCatalogSHA256':sha((after/'scripts.json').read_bytes()),'sourceDeltas':source_deltas,'nativeDeltaDigests':[{'path':d['path'],'kind':d['kind'],'sha256':sha(canon(d))} for d in native_deltas],'publicationAuthorized':False,'cleanupAuthorized':False,'ownerIdentityConfirmed':False,'publicationHoldReason':'Synthetic QA remains; no cleanup or publishing'}
reviewfile=root/'review.json';put(reviewfile,review)
cmd=[sys.executable,str(tool),'--capture',str(after),'--before',str(before),'--frozen',str(pinfile),'--native-report',str(reportfile),'--concurrent-review',str(reviewfile),'--destination',str(root/'outputs')]
result=subprocess.run(cmd,capture_output=True,text=True);assert result.returncode==0,result.stderr
assert not (root/'outputs').exists()
cases=[{'name':'exact-closed-review-read-only','passed':True}]
for name,mutate in [('missing-source-row',lambda r:r['sourceDeltas'].pop()),('wrong-native-delta',lambda r:r['nativeDeltaDigests'][0].update(sha256='3'*64)),('wrong-before-catalog',lambda r:r.update(beforeSourceCatalogSHA256='3'*64)),('wrong-audit',lambda r:r.update(nativeAuditSHA256='3'*64)),('publication-authorized',lambda r:r.update(publicationAuthorized=True)),('cleanup-authorized',lambda r:r.update(cleanupAuthorized=True)),('extra-review-field',lambda r:r.update(allowAllConcurrent=True)),('unapproved-review',lambda r:r.update(approvedForTaskSourceExportOnly=False))]:
 bad=json.loads(json.dumps(review));mutate(bad);put(reviewfile,bad);result=subprocess.run(cmd,capture_output=True,text=True);assert result.returncode!=0 and not (root/'outputs').exists(),name;cases.append({'name':name+'-blocked','passed':True})
put(reviewfile,review)
bad=dict(report,errors={'task':'wrong pin'});put(reportfile,bad);badreview=dict(review,nativeAuditSHA256=sha(reportfile.read_bytes()));put(reviewfile,badreview);result=subprocess.run(cmd,capture_output=True,text=True);assert result.returncode!=0 and not (root/'outputs').exists();cases.append({'name':'own-scope-error-blocked','passed':True})
bad=dict(report);bad.pop('errors');put(reportfile,bad);badreview=dict(review,nativeAuditSHA256=sha(reportfile.read_bytes()));put(reviewfile,badreview);result=subprocess.run(cmd,capture_output=True,text=True);assert result.returncode!=0 and not (root/'outputs').exists();cases.append({'name':'missing-own-error-inventory-blocked','passed':True})
put(reportfile,report);put(reviewfile,review)
result=subprocess.run(cmd+['--write'],capture_output=True,text=True);assert result.returncode==0,result.stderr
manifest=json.loads((root/'outputs/manifest.json').read_bytes());assert manifest['verified'] is False and manifest['strictNativeAuditVerified'] is False and manifest['wholeForestPreservedBeyondTaskScope'] is False and manifest['taskSourceExportVerified'] is True and manifest['publicationAuthorized'] is False and manifest['cleanupAuthorized'] is False
assert len(list((root/'outputs').glob('*.luau')))==6 and len(manifest['fullSourceCatalog'])==8
assert not any('source' in r for r in manifest['fullSourceCatalog'])
cases.append({'name':'six-only-export-keeps-strict-false-and-no-foreign-sources','passed':True})
out={'schema':'lobby-polish-concurrent-export-local-fixtures-v1','verified':True,'executionScope':'Synthetic local fixtures only; no Studio/native parser/Git/index actions','cases':cases}
(repo/'artifacts/lobby-polish-20261002/materials/concurrent-export-fixtures.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out))
