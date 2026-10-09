"""Immutable receiver for read-only preservation of 23 externally detached trees.

No mode switching, original-object changes or restoration. Raw backup success
does not certify native reopen, dynamic mesh data or external references.
"""
from pathlib import Path
import argparse
import hashlib
import http.server
import json
import sys
import threading

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from sync_from_studio import StudioMcpClient,find_mcp_batch,select_studio,RELEASE_STUDIO_NAME

SCHEMA='external-held-storage-archive-v1'
EXPECTED_NAMES={
 'PoolSlideContactAnimations_20260910','PoolSlideContextDiagnosticBackup_0710',
 'PoolSlideContextDiagnosticBackup_MP6_1609Z','PoolSlideContextDiagnosticBackup_MP7_1624Z',
 'PoolSlideContextDiagnosticBackup_MP8_1633Z','PoolSlideContextDiagnosticBackup_MP9_1640Z',
 'PoolSlideInstallBackup_pipe-scale4-stage-20260909T0407Z',
 'TEMP_PipeEntityAnimations_20260909','TEMP_PipeEntityAnimations_20260909_Scale3_7_Superseded',
 'TEMP_PipeEntityLobbyRigResult_0748Z','TEMP_PipeEntityMPResult_0457Z',
 'TEMP_PipeEntityMPResult_0503Z','TEMP_PipeEntityMPResult_0508Z',
 'TEMP_PipeEntityMPResult_0638Z','TEMP_PipeEntityMPResult_0706Z',
 'TEMP_PipeEntityMPResult_1609Z','TEMP_PipeEntityMPResult_1624Z',
 'TEMP_PipeEntityMPResult_1633Z','TEMP_PipeEntityMPResult_1640Z',
 'TEMP_PipeEntityMPResult_1648Z','TEMP_PipeEntityMultiplayerLaunch',
 'TEMP_PipeEntityValidation','TrelloPoolSlideReleaseBackup_20260910',
}

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dest',type=Path,required=True)
    parser.add_argument('--observation',type=Path,default=ROOT/'artifacts/cleanup-serverstorage-20261009/external-storage-observation.json')
    args=parser.parse_args()
    dest=args.dest.resolve()
    assert dest.is_relative_to(ROOT) and not dest.exists(),'New archive destination required inside workspace'
    observation_path=args.observation.resolve()
    observation_raw=observation_path.read_bytes()
    observation=json.loads(observation_raw)
    assert observation['schema']=='external-storage-observation-v1'
    assert observation['placeId']==131311258779917 and observation['universeId']==10559217407
    assert observation['storagePortExists'] is False and observation['rootNativeWrites']==0
    observed_roots=observation['heldRemovedRoots']
    assert len(observed_roots)==23 and {row['name'] for row in observed_roots}==EXPECTED_NAMES
    assert all(row['currentParent']=='nil' and row['sameNameLive'] is False for row in observed_roots)
    observed_sources=observation['heldOutOfGameSources']
    assert len(observed_sources)==12 and all(row['editorReadable'] and row['editorMatchesSource'] and row['sourceMatchesCapture'] for row in observed_sources)
    context={'schema':SCHEMA,'roots':observed_roots,'heldOutOfGameSources':observed_sources,'observationSHA256':sha(observation_raw)}
    context_raw=json.dumps(context,separators=(',',':')).encode()
    source_path=Path(__file__).with_name('external_storage_archive_capture.luau')
    source_raw=source_path.read_bytes()
    def input_guard():
        assert observation_path.read_bytes()==observation_raw,'Concurrent observation changed'
        assert source_path.read_bytes()==source_raw,'Concurrent capture helper changed'
    input_guard()
    dest.mkdir(parents=True)
    def save(name,data):
        path=dest/name
        if path.exists():
            assert path.read_bytes()==data,'Immutable archive conflict'
        else:
            with path.open('xb') as stream:
                assert stream.write(data)==len(data)
    save('observation.json',observation_raw)
    save('capture-source.luau',source_raw)
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self,*_):
            pass
        def answer(self,data):
            self.send_response(200)
            self.send_header('Content-Length',str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        def do_GET(self):
            if self.path!='/context':
                return self.send_error(404)
            try:
                input_guard()
                self.answer(context_raw)
            except Exception as error:
                self.send_error(409,str(error))
        def do_POST(self):
            try:
                input_guard()
                length=int(self.headers.get('Content-Length','0'))
                assert 0<length<=750000
                data=self.rfile.read(length)
                assert len(data)==length,'Incomplete HTTP chunk'
                if self.path=='/finalize':
                    transfer=json.loads(data)
                    assert set(transfer)=={'native','facts'}
                    for kind in ('native','facts'):
                        info=transfer[kind]
                        assert type(info['parts']) is int and 0<info['parts']<1000
                        raw=b''.join((dest/f'{kind}-part-{i:04d}.bin').read_bytes() for i in range(info['parts']))
                        assert len(raw)==info['bytes'] and sha(raw)==info['sha256']
                        save('native.rbxm' if kind=='native' else 'facts.json',raw)
                    facts=json.loads((dest/'facts.json').read_bytes())
                    assert facts['schema']==SCHEMA and facts['placeId']==131311258779917 and facts['universeId']==10559217407
                    assert facts['nativeSHA256']==transfer['native']['sha256'] and facts['nativeBytes']==transfer['native']['bytes']
                    assert facts['observationSHA256']==context['observationSHA256']
                    assert len(facts['roots'])==23 and {row['name'] for row in facts['roots']}==EXPECTED_NAMES
                    assert all(row['parentIsNil'] is True and row['originalHeldReference'] is True for row in facts['roots'])
                    assert len(facts['heldSources'])==12
                    captured={row['path']:row for row in facts['heldSources']}
                    assert set(captured)=={row['pathCurrent'] for row in observed_sources}
                    for row in observed_sources:
                        current=captured[row['pathCurrent']]
                        assert current['sourceSHA256']==row['sourceSHA256'] and current['bytes']==row['sourceBytes']
                        assert current['editorMatchesSource'] is True and current['sourceMatchesV8'] is True
                    assert facts['nativeMutations']==facts['sourceWrites']==facts['modeSwitches']==0
                    assert facts['removalAttributedToCleanup'] is False and facts['restorationCertified'] is False
                    assert len(facts['nodes'])==facts['heldNodeCount']==sum(row['nodes'] for row in facts['roots'])
                    assert all(row['archivable'] is True and row['sandboxed'] is False for row in facts['nodes'])
                    save('transfer-receipt.json',data) # Native post-transfer guard may still fail; completion is separate.
                else:
                    bits=self.path.strip('/').split('/')
                    assert len(bits)==2 and bits[0] in ('native','facts')
                    index=int(bits[1])
                    assert 0<=index<1000
                    save(f'{bits[0]}-part-{index:04d}.bin',data)
                self.answer(b'saved')
            except Exception as error:
                self.send_error(409,str(error))
    server=thread=client=None
    started=False
    try:
        server=http.server.ThreadingHTTPServer(('127.0.0.1',18913),Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        started=True
        client=StudioMcpClient(find_mcp_batch())
        client.initialize()
        studio=select_studio(client,RELEASE_STUDIO_NAME,15)
        assert studio['id']=='1b603e69-7ae1-4572-b210-d5bf05c684ff','Wrong Studio session; preserve other windows'
        current=client.call('get_studio_state',{'studio_id':studio['id']})
        assert 'Current Studio Mode: Edit' in current,'Edit unavailable; preserve active Play'
        input_guard()
        result=client.call('execute_luau',{'studio_id':studio['id'],'datamodel_type':'Edit','code':source_raw.decode('utf8')})
        save('capture-result.txt',result.encode())
        report=json.loads(result)
        assert report['schema']==SCHEMA and report['pass'] is True,'Native read-only capture/after-cleanup guards failed'
        assert report['roots']==23 and report['heldSources']==12
        assert (dest/'transfer-receipt.json').is_file(),'No immutable native transfer receipt'
        input_guard()
        completion={'schema':'external-held-storage-capture-completion-v1','report':report,
                    'observationSHA256':sha(observation_raw),'captureSourceSHA256':sha(source_raw),
                    'transferReceiptSHA256':sha((dest/'transfer-receipt.json').read_bytes()),
                    'nativeMutations':0,'removalAttributedToCleanup':False,'restorationCertified':False}
        save('capture-completion.json',(json.dumps(completion,indent=2)+'\n').encode())
        print(json.dumps({key:report[key] for key in ('pass','roots','heldNodes','heldSources','liveSources','liveRoots','nativeSHA256','nativeBytes','restorationCertified')}))
    finally:
        primary=sys.exc_info()[1]
        errors=[]
        operations=[]
        if client is not None:
            operations.append(('client.close',client.close))
        if server is not None:
            if started:
                operations.append(('server.shutdown',server.shutdown))
            operations.append(('server.server_close',server.server_close))
        if started:
            operations.append(('thread.join',lambda:thread.join(timeout=5)))
        for label,operation in operations:
            try:
                operation()
            except BaseException as error:
                errors.append((label,error))
        if errors:
            error=primary if primary is not None else errors[0][1]
            for label,problem in errors:
                error.add_note(f'Cleanup {label} failed: {problem}')
            if primary is None:
                raise error

if __name__=='__main__':
    main()
