"""Write one immutable readonly peer receipt; never execute native code."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
PKG = ROOT/'artifacts/cleanup-20261010/storage-authoring-port-v1'
SHA = lambda raw: hashlib.sha256(raw).hexdigest()


def pin(path):
    raw = path.read_bytes()
    return {'path':path.relative_to(ROOT).as_posix(),'bytes':len(raw),'sha256':SHA(raw)}


raw = (PKG/'frozen-pins-v1.json').read_bytes()
assert SHA(raw) == 'fd251d5f8485688fd8c4be569832b5c2785cdbfe53b5a0738c9da5d958b9704f'
frozen = json.loads(raw)
assert len(frozen['pins']) == 25
assert all(pin(ROOT/r['path']) == r for r in frozen['pins'])
preparation = json.loads((PKG/'preparation-v1.json').read_bytes())
assert all(pin(ROOT/r['path']) == r for r in preparation['inputs'])
assert preparation['globalRepoParityPending'] is False
assert preparation['preservedConcurrentMirrorDifferences'] == []
config = json.loads((PKG/'trial-config.json').read_bytes())
source = (PKG/'trial-source.luau').read_bytes()
common = (ROOT/'tools/cleanup_20261009/retired_authoring_archive_common.luau').read_bytes()
core = (PKG/'transaction-core.luau').read_bytes()
suffix = (PKG/'native-trial.luau').read_bytes()
assert source == common+b'\n'+core+b'\nlocal PORT_CONFIG=A.HS:JSONDecode([====['+(PKG/'trial-config.json').read_bytes()+b']====])\n'+suffix
assert len(source)==110646 and SHA(source)=='19573ccb3fbcd7ae007d256479df5c5c5bfabb713ab45531adf3f448a9e250eb'
assert len(config['sources'])==213 and config['expectedSourceCount']==213 and config['expectedRootCount']==52
assert config['expectedSceneCount']==417075
assert config['bake']['rawSHA256']=='1f564fdde835ad89b529d9069ddf87b0ed4991636f363eacbd098cc0b342ff28'
assert config['renderer']['rawSHA256']=='0f217e5a3f56751e7672efc035861a2cec1b5f23d581a52020411a8d081790cf'
author = (PKG/'offline-faults-v1.json').read_bytes()
rerun = (HERE/'offline-rerun-v1.json').read_bytes()
assert rerun == author
replay = json.loads(rerun)
assert replay['passed'] and replay['replay']['cases']==51 and replay['replay']['checks']==3018
assert len(replay['compileUnits'])==5 and all(p['exitCode']==0 for p in replay['compileUnits'])
driver = (PKG/'run-root-trial.py').read_bytes()
assert len(driver)==7622 and SHA(driver)=='6516a4af027a16cbe24c87e9b4880e96798de342502cd01182c6c1b8c3b198bf'
value = {
    'schema':'mongotv-retired-authoring-controlled-absence-independent-peer-v1',
    'preparationEligibleForNativeTrial':True,'nativeExecuted':False,'deletionApproved':False,
    'referenceAbsenceCertified':False,'reviewedSourceSHA256':SHA(source),
    'reviewedSourceBytes':len(source),'reviewedConfig':pin(PKG/'trial-config.json'),
    'reviewedDriver':pin(PKG/'run-root-trial.py'),'frozenPins':pin(PKG/'frozen-pins-v1.json'),
    'frozenInputPinsVerified':25,'preparationInputPinsVerified':len(preparation['inputs']),
    'reviewedPins':frozen['pins'], 'independentReplay':pin(HERE/'offline-rerun-v1.json'),
    'authorReplayByteIdentical':True,'actualCoreCases':51,'actualCoreAssertions':3018,'compileUnits':5,
    'sourceAssemblyByteExact':True,'freshSourceRows':213,'freshRemoteRows':15,'freshStorageRoots':52,
    'freshGameDescendants':417075,'catalogSHA256':config['catalogSHA256'],
    'reviewedNativeAbsenceScope':[
        'Only five exact zero-script owner-retired authoring roots,1617objects; trial returns the same originals to ServerStorage.',
        'Exact8,050,869B historical native archive hash must match the current original serialization; unreadable references remain unresolved.',
        'Actual current GetManifest verifies native R4 compressed input; IsReady checks native V2 components/room masks/elevator cabins. Fresh factory tables for before,absent,restored prevent cached readiness.',
        'Six missing/incomplete read-boundary negatives per phase; no native Ready edits. Current selected three asset trees retain identity,facts and complete native serialized bytes.',
        'No Ensure,Build,Begin or actual rendering/asset download/bake invoked. GameManager lobby startup and MazeGenerator Begin remain active consumers; only data selectors are exercised.'
    ],
    'safetyReview':[
        'Actual core marks inverse ownership only after beforeWrite and immediate exact Parent/entry check, directly before setter invocation. Both first/last setter failures and commit-then-error states are read back; eligible inverses attempted independently.',
        'Unrelated Source/global epoch drift revokes final pass without blocking an eligible own inverse. Mode,lease,root tree/identity/namecollision and exact nilParent must remain valid; foreign differences retained pending.',
        'No yielding path in reviewed first-detach-to-restoration hooks: inventory/tree/source reads and actual selector methods are synchronous; serialization,reference scan,task.wait and native staging occur outside that window.',
        'Reviewed two complete module initializers only bind services/GUID/locals. Fresh empty ModuleScript require returns an uncalled factory. Bodies execute only with frozen read-service facades plus task/coroutine/spawn/delay/wait/require/Instance/AssetService/shared/_G/workspace/script denied.',
        'Fresh test ModuleScript Source/editor/name/class/Parent/children/Archivable/LinkedSource/attributes/tags guarded in callback/readback and exact owned cleanup. Foreign probe edits are retained and cause failure.',
        'All213 current original Source/editor/class/properties/attributes/tags checked during staging,trial and cleanup. Full game identities/census and exact current selected asset bytes guard unintended object drift.',
        'Fresh purpose-bound52-root ledger explicitly avoids certifying missing historical73-root/222-script/23-held ledger. Failed inverse/probe/disconnect refs remain reachable; namespace release requires no pending originals/probes/connections.',
        'Driver binds actual assembled Source to exact peer reviewedSourceSHA256 and executes one bounded request. Transport/envelope ambiguity preserves evidence and makes no subsequent native call,rollback or retry. Local client close is not cancellation.',
        'Completed output validator requires10Parentwrites,5detach/inverse readbacks,2probescreated/destroyed,3actualfreshselectorphases/18negatives,all213Sources unchanged,original/selectednative data unchanged,zero pending/cleanup/connection failures and released owned namespaces.',
        'Readonly references: LevelWorldStorage enumerates children only for exactLevel4/5/6 names; current MazeRenderer/RuntimeBake/MaterialPolish select V2/elevator/R4. Quoted retired-name guards are an additional refusal,not a general dynamic dependency proof; inaccessible native references prevent permanent-deletion certification.'
    ],
    'resolvedPreparationFindings':[
        'BeforeWrite foreign nil/Parent/name changes never gain setter/inverse ownership; second immediate detach and inverse guards present.',
        'Scoped inverse eligibility separated from global Source/epoch pass gates.',
        'Probe metadata ownership added; exact helper hashes and read facades prevent silent initializer/lifecycle scope expansion.',
        'Missing old shared context handled with explicitly new nonce-bound current-purpose ledger,not inferred historical continuity.',
        'Driver peer source binding added before freeze.'
    ],
    'nativeCalls':0,'productionWrites':0,'runtimeWrites':0,'manifestWrites':0,'indexWrites':0,'modeSwitches':0,
    'remainingGates':[
        'Root fresh Edit/place/universe check and actual one-operation native completion; this receipt is not native PASS.',
        'On transport unknown or pending owned state, no retry; Root must reconcile fresh known-ended operation/state and preserve recovery evidence.',
        'Protected/inaccessible Instance reference types and separate permanent-removal/archive gates remain pending even if this trial passes.'
    ],
    'limits':'Independent static actual-code review and actual unchanged core fault replay only. No native trial,gameplay,multiplayer,streaming,reserved-server,asset rendering/performance or permanent-deletion pass. Expected event budgets and final guards do not prove actor provenance or continuous transaction isolation.'
}
assert all(pin(ROOT/r['path'])==r for r in frozen['pins'])
with (HERE/'REVIEW.json').open('xb') as stream:
    stream.write((json.dumps(value,indent=2)+'\n').encode())
print(json.dumps({'preparationEligibleForNativeTrial':True,'nativeExecuted':False,'sourceSHA256':SHA(source),
                  'review':pin(HERE/'REVIEW.json'),'cases':51,'checks':3018,'frozenPinsVerified':25}))
