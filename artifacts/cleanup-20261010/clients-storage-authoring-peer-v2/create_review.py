"""Immutable independent V2 delta review; no native invocation."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
PKG=ROOT/'artifacts/cleanup-20261010/storage-authoring-port-v2'
V1=PKG.with_name('storage-authoring-port-v1')
SHA=lambda raw:hashlib.sha256(raw).hexdigest()
def pin(path):
    raw=path.read_bytes()
    return {'path':path.relative_to(ROOT).as_posix(),'bytes':len(raw),'sha256':SHA(raw)}
frozen_raw=(PKG/'frozen-pins-v1.json').read_bytes()
assert SHA(frozen_raw)=='4bc713636254ed530b20d3f2988f84af84119c59db2821a74214804c0cf0688d'
frozen=json.loads(frozen_raw)
assert len(frozen['pins'])==42
assert all(pin(ROOT/r['path'])==r for r in frozen['pins'])
old_frozen=json.loads((V1/'frozen-pins-v1.json').read_bytes())
assert len(old_frozen['pins'])==25 and all(pin(ROOT/r['path'])==r for r in old_frozen['pins'])
source=(PKG/'trial-source.luau').read_bytes()
assert len(source)==111584 and SHA(source)=='d3ae28019d2ee0a32ddd798db47f7a1e2a248ef36e8df0b4d58f097df73f6176'
assert source==(ROOT/'tools/cleanup_20261009/retired_authoring_archive_common.luau').read_bytes()+b'\n'+(PKG/'transaction-core.luau').read_bytes()+b'\nlocal PORT_CONFIG=A.HS:JSONDecode([====['+(PKG/'trial-config.json').read_bytes()+b']====])\n'+(PKG/'native-trial.luau').read_bytes()
assert SHA((PKG/'trial-config.json').read_bytes())=='69f0bd08db4630d4f822e98c3fa363e299e748db5a4e7d3c6f78c45f223001e2'
assert SHA((PKG/'run-root-trial.py').read_bytes())=='eb57d5cc9c6af3ef87ddf0b95f8434a227915794cbb274e23d136c1063ba70b9'
for peer,author,cases,checks in [('offline-core-rerun-v1.json','offline-faults-v1.json',51,3018),('offline-native-boundaries-rerun-v1.json','offline-native-boundaries-attempt-v1.json',38,2070)]:
    raw=(HERE/peer).read_bytes()
    assert raw==(PKG/author).read_bytes()
    replay=json.loads(raw)
    assert replay['passed'] and replay['replay']['cases']==cases and replay['replay']['checks']==checks
driver=subprocess.run([sys.executable,'-B',str(PKG/'run-root-trial.py')],capture_output=True,text=True,timeout=20)
assert driver.returncode==0 and not driver.stderr
assert json.loads(driver.stdout)=={'prepared':True,'nativeCalls':0,'sourceSHA256':SHA(source),'deletionApproved':False}
with (HERE/'driver-default-rerun-v1.json').open('xb') as stream:
    stream.write((json.dumps({'driver':pin(PKG/'run-root-trial.py'),'exitCode':0,'stdout':driver.stdout,'stderr':driver.stderr,'nativeCalls':0},indent=2)+'\n').encode())
completion=json.loads((V1/'native-run-v1/root-completion.json').read_bytes())
assert completion['passed'] is False and completion['parentWrites']==0 and completion['selectorPhases']==[]
assert completion['probeCreated']==completion['probeDestroyed']==2 and completion['probeRemaining']==0
assert completion['all213SourcesUnchanged'] and completion['originalNativeArchiveUnchanged']
assert completion['ownedLeaseReleased'] and completion['ownedCurrentLedgerReleased'] and completion['connectionsRetained']==0 and completion['pendingOriginals']==[]
value={
 'schema':'mongotv-retired-authoring-controlled-absence-independent-peer-v2',
 'preparationEligibleForNativeTrial':True,'nativeExecuted':False,'deletionApproved':False,
 'referenceAbsenceCertified':False,'reviewedSourceSHA256':SHA(source),'reviewedSourceBytes':len(source),
 'reviewedConfig':pin(PKG/'trial-config.json'),'reviewedDriver':pin(PKG/'run-root-trial.py'),
 'frozenPins':pin(PKG/'frozen-pins-v1.json'),'frozenInputPinsVerified':42,'v1All25FrozenPinsStillExact':True,
 'reviewedPins':frozen['pins'],'sourceAssemblyByteExact':True,
 'independentCoreReplay':pin(HERE/'offline-core-rerun-v1.json'),
 'independentNativeBoundaryReplay':pin(HERE/'offline-native-boundaries-rerun-v1.json'),
 'independentDefaultDriver':pin(HERE/'driver-default-rerun-v1.json'),
 'authorReplayByteIdentical':True,'actualCoreCases':51,'actualCoreAssertions':3018,
 'actualNativeSliceCases':38,'actualNativeSliceAssertions':2070,'coreCompileUnits':5,'boundaryCompileUnits':1,
 'v1CompletionRead':pin(V1/'native-run-v1/root-completion.json'),
 'v1KnownCompletion':'Domain refusal before any Parent write/selector phase;2probes destroyed,all213Sources/originalnative exact,leasesreleased,connections0,pending0. No V1 retry.',
 'v1Qualification':pin(HERE.with_name('clients-storage-authoring-peer-v1')/'V1_QUALIFICATION.json'),
 'exactDeltaReview':[
  'Native rollbackEligibility now requires actual entry.invoked or unchanged originalSS Parent. An uninvoked foreign nil is preserved pending; unchanged original is harmlessly disarmed. Existing lease/mode/exacttree/namecollision/Parent checks remain.',
  'Actual test extracts complete V1/V2 rollbackEligibility,setParent,B.environment and unique slices,executes unchanged core and whole current RuntimeBake. It reproduces V1 inverse adoption and V2 preservation for nested lease throw,immediate Parent CAS refusal and epoch refusal at roots1/3/5; also harmless disarm and owned commit-then-error recovery.',
  'The reviewed full native helpers have no listener/task initializer. require(probe) only returns an uncalled factory; actual helper bodies execute against narrow frozen read facades and denied task/require/Instance/AssetService/workspace/script/shared/_G boundaries.',
  'Server-data projection explicitly controls IsClientfalse/IsServertrue,while actual Edit IsClient/IsServer values are separately observed. Actual whole GetManifest client-domain rejection must occur before any asset selector; nil/true/false facade behavior is replayed offline.',
  'Native phase reports and driver explicitly require controlledServerDataDomain and21 controlled negatives across3fresh phases; this does not certify an actual server/gameplay domain.',
  'Actual nested boundaries and whole body are executed,not replaced with copied behavioral implementation. Table/metatable guards remain controlled boundaries; no engine scheduling or native forest recovery is inferred.',
  'Driver verifies both offline receipt inputpins,binds peer.reviewedSourceSHA256 to actual Source,and makes only one bounded native request. Unknown transport/envelope stops further calls,rollback and retry; raw API/completion evidence preserved.',
  'Exact scoped inverse remains independent of unrelated Source/epoch final-pass gates. Fresh probe Source/editor/hierarchy/properties/attrs/tags ownership,independent cleanup/disconnect retention,current-purpose nonce ledger and all213 finalguards remain unchanged.',
  'Native selected R4/V2/elevator data/facts/identities and original8,050,869B archive invariance remain mandatory. Protected reflected Instance references remain unresolved; permanentRemoval/deletionApproved/referenceAbsenceCertified stayfalse.'
 ],
 'supersession':'V2 eligibility applies only to this exact new executable. Original V1 code/pins/peer/qualification and known failed native execution remain immutable. V1 composed hook gap is now represented by exact-source counterexample; no old native success is fabricated.',
 'nativeCalls':0,'productionWrites':0,'runtimeWrites':0,'manifestWrites':0,'indexWrites':0,'modeSwitches':0,
 'remainingGates':['Root fresh Edit/place/universe and actual new V2 native completion; no native trial PASS here.','Unknown or pending outcome needs fresh known-ended reconciliation; never cancellation/retry assumptions.','Protected reference proof/archive and separate permanent-removal approval remain pending even on actual V2 trialPASS.'],
 'limits':'Independent exact-code delta review +offline actual core/slices/whole-body domain tests only. No actual Instance scheduling,native absence/recovery,gameplay,multiplayer,streaming,reserved-server,rendering,performance or deletion proof. Final guards are point-in-time and expected event budgets do not prove actor provenance.'
}
assert all(pin(ROOT/r['path'])==r for r in frozen['pins'])
with (HERE/'REVIEW.json').open('xb') as stream:
    stream.write((json.dumps(value,indent=2)+'\n').encode())
print(json.dumps({'preparationEligibleForNativeTrial':True,'nativeExecuted':False,'review':pin(HERE/'REVIEW.json'),'core':51,'nativeBoundaryCases':38,'frozenPinsVerified':42}))
