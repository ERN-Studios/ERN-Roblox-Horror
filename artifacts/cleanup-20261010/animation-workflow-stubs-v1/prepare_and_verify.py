"""Prepare/replay two already-retired unsafe bpy entrypoints; artifact-only."""
from pathlib import Path
import argparse
import ast
import hashlib
import importlib.util
import json
import subprocess
import sys

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
S25=HERE.with_name('animation-workflow-retirement-v1')
SHA=lambda raw:hashlib.sha256(raw).hexdigest()
TARGETS=('tools/export_entity_keyframes.py','tools/export_entity_animations.py')


def save(path,raw):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('xb') as stream:assert stream.write(raw)==len(raw)


def run_cli(path,message):
    results=[]
    for flags in ([],['--help'],['--v10'],['--v3','--force']):
        run=subprocess.run([sys.executable,'-B',str(path),*flags],capture_output=True,timeout=10)
        assert run.returncode==1 and not run.stdout and run.stderr.decode().strip()==message
        results.append({'flags':flags,'exitCode':run.returncode,'retirementMessageExact':True})
    return results


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--prepare',action='store_true');ap.add_argument('--verify-installed',action='store_true');ap.add_argument('--receipt',type=Path,required=True);args=ap.parse_args()
    assert not args.receipt.exists()
    s25raw=(S25/'proposal-v1/proposal.json').read_bytes();s25=json.loads(s25raw)
    assert SHA(s25raw)=='83f67e07e7917c3b6a8e63e0b9ee974b2ee90cbd8e45aa359dd95696ec55b57b'
    harness=S25/'verify_guards.py'
    assert SHA(harness.read_bytes())=='510d2e68839d586c6ca8454171279d8664c99a03db7fa1cc75b37e392517a350'
    spec=importlib.util.spec_from_file_location('actual_s25_contract',harness);contract=importlib.util.module_from_spec(spec);spec.loader.exec_module(contract)
    retained={r['file']:(ROOT/r['file']).read_bytes() for r in s25['retainedInputsAndReceipts']}
    assert len(retained)==21 and all(SHA(retained[r['file']])==r['rawSHA256'] for r in s25['retainedInputsAndReceipts'])
    all_tools={r['file']:(ROOT/r['file']).read_bytes() for r in s25['files']}
    runtime_path=ROOT/'ServerScriptService/Level 1 Systems/EntityAnimation.Script.lua';runtime=runtime_path.read_bytes()
    published=json.loads((ROOT/'assets/animations/entity/published-assets-v10-full.json').read_bytes())
    assert len(published)==8 and all(('"'+r['id']+'"').encode() in runtime for r in published.values())
    out=HERE/'proposal-v1'
    if args.prepare:
        assert not args.verify_installed and not out.exists()
        rows=[]
        for file in TARGETS:
            s25row=next(r for r in s25['files'] if r['file']==file)
            before=all_tools[file]
            assert SHA(before)==s25row['candidateSHA256'] and s25row['importWorkflowRetired']
            assert before==(S25/'proposal-v1/candidate'/file).read_bytes()
            newline='\r\n' if b'\r\n' in before else '\n'
            body=('"""Retired Studio entity-animation export entrypoint."""\n'
                  'from __future__ import annotations\n\n'
                  '# Exact prior sources remain in the S25/S25b cleanup archives.\n'
                  'RETIRED_WORKFLOW_MESSAGE = '+repr(s25['message'])+'\n'
                  "if __name__ == '__main__':\n"
                  '    raise SystemExit(RETIRED_WORKFLOW_MESSAGE)\n'
                  'raise RuntimeError(RETIRED_WORKFLOW_MESSAGE)\n')
            after=body.replace('\n',newline).encode()
            ast.parse(after)
            save(out/'before'/file,before);save(out/'candidate'/file,after)
            original=S25/'proposal-v1/before'/file
            assert SHA(original.read_bytes())==s25row['beforeSHA256']
            rows.append({'file':file,'beforeBytes':len(before),'beforeSHA256':SHA(before),'candidateBytes':len(after),'candidateSHA256':SHA(after),'originalS25Archive':{'file':original.relative_to(ROOT).as_posix(),'rawSHA256':SHA(original.read_bytes())}})
        proposal={'schema':'mongotv-retired-bpy-export-stubs-proposal-v1','preparedOnly':True,'ownerDecision':'Root authorized reducing the two already-retired unsafe bpy exporters to retirement stubs; existing CLI/import refusal contract must remain.','files':rows,'message':s25['message'],'s25ProposalSHA256':SHA(s25raw),'s25HarnessSHA256':SHA(harness.read_bytes()),'retainedInputsAndReceipts':s25['retainedInputsAndReceipts'],'closure':'No current production/tool import,subprocess or safe_name caller for either module. Imports already raise before definitions/bpy initializer. README retirement references are documentary. Publisher/sampler seven pure helpers and shared builders remain unchanged.','runtimeIds':published,'removedBytes':sum(r['beforeBytes']-r['candidateBytes'] for r in rows),'nativeWrites':0,'productionWrites':0,'indexWrites':0,'limits':'Prepared local-authoring stubs only; no animation native forest/archive/reference/removal or gameplay/performance pass.'}
        save(out/'.gitattributes',b'* -text\n');save(out/'proposal.json',(json.dumps(proposal,indent=2)+'\n').encode())
    proposal=json.loads((out/'proposal.json').read_bytes());message=proposal['message'];results=[];mutants=[]
    for row in proposal['files']:
        file=row['file'];before=(out/'before'/file).read_bytes();after=(out/'candidate'/file).read_bytes()
        assert SHA(before)==row['beforeSHA256'] and SHA(after)==row['candidateSHA256']
        assert SHA(all_tools[file])==row['candidateSHA256' if args.verify_installed else 'beforeSHA256']
        for phase,body,executable in [('before',before,out/'before'/file if args.verify_installed else ROOT/file),('candidate',after,ROOT/file if args.verify_installed else out/'candidate'/file)]:
            clis=run_cli(executable,message);actions=[]
            try:
                with contract.load_source(file,body,actions):raise AssertionError('Retired unsafe import unexpectedly succeeded')
            except RuntimeError as error:
                assert str(error)==message and not actions
            results.append({'file':file,'phase':phase,'actualCLICases':clis,'actualImportRetirement':True,'optionalNativeBoundaryCalls':actions})
        newline=b'\r\n' if b'\r\n' in after else b'\n'
        mutant=after.replace(b'raise RuntimeError(RETIRED_WORKFLOW_MESSAGE)'+newline,b'',1)
        actions=[]
        with contract.load_source(file,mutant,actions):assert not actions
        mutants.append({'file':file,'mutation':'remove import refusal','contractRejected':True,'observed':'Import returned instead of expected retirement error'})
        mutant=after.replace(b'    raise SystemExit(RETIRED_WORKFLOW_MESSAGE)'+newline,b'    pass'+newline,1)
        actions=[]
        try:
            with contract.load_source(file,mutant,actions,cli=True):raise AssertionError('Mutant unexpectedly returned')
        except RuntimeError as error:
            assert str(error)==message and not actions
        mutants.append({'file':file,'mutation':'remove CLI refusal','contractRejected':True,'observed':'RuntimeError instead of expected SystemExit CLI contract'})
    helpers=[]
    for file in all_tools:
        if file not in TARGETS:
            row=next(r for r in s25['files'] if r['file']==file)
            assert SHA(all_tools[file])==row['candidateSHA256']
            actions=[]
            with contract.load_source(file,all_tools[file],actions) as namespace:
                assert not actions
                helpers.extend(contract.helpers(namespace,file))
    assert len(helpers)==13
    assert all((ROOT/file).read_bytes()==raw for file,raw in all_tools.items())
    assert all((ROOT/file).read_bytes()==raw for file,raw in retained.items()) and runtime_path.read_bytes()==runtime
    receipt={'schema':'mongotv-retired-bpy-export-stubs-actual-port-v1','pass':True,'verifiedInstalled':args.verify_installed,'proposalSHA256':SHA((out/'proposal.json').read_bytes()),'testSHA256':SHA(Path(__file__).read_bytes()),'cliCases':16,'importCases':4,'actualCases':results,'mutants':mutants,'retainedPureHelperCases':helpers,'retainedInputsAndReceipts':21,'allFourProductionToolsUnchangedDuringReplay':True,'runtimeIdSourceUnchanged':True,'runtimeIdSourceSHA256':SHA(runtime),'activePublishedIdCount':8,'nativeCalls':0,'assetUploads':0,'networkCalls':0,'productionWrites':0,'manifestWrites':0,'indexWrites':0,'limits':'Actual installed-before/archived-after CLI and complete Python source imports at controlled optional/native boundaries. No bpy initializer runs; seven retained publisher/sampler helpers retain13behaviors. Only two already-unimportable retired workflows lose unreachable source. No native assets/cache/reference/deletion/gameplay/performance proof.'}
    save(args.receipt,(json.dumps(receipt,indent=2)+'\n').encode())
    print(json.dumps({'pass':True,'cliCases':16,'imports':4,'mutants':4,'retainedHelpers':13,'retainedFiles':21,'removedSourceBytes':proposal['removedBytes'],'verifiedInstalled':args.verify_installed,'nativeCalls':0}))


if __name__=='__main__':main()
