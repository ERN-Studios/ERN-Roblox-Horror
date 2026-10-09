"""Pinned native archive -> owned off-place Roblox-engine reopen port.

No mode switching or original writes. Saves complete native reserialization;
readable data success cannot certify protected fields if native bytes differ.
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
from external_storage_archive import EXPECTED_NAMES

SCHEMA='external-held-storage-native-reopen-v1'
PART_BYTES=750000

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',type=Path,required=True)
    parser.add_argument('--dest',type=Path,required=True)
    args=parser.parse_args()
    archive=args.archive.resolve()
    dest=args.dest.resolve()
    assert archive.is_relative_to(ROOT) and archive.is_dir(),'Existing archive inside workspace required'
    assert dest.is_relative_to(ROOT) and not dest.exists(),'New proof destination inside workspace required'
    inputs={name:(archive/name).read_bytes() for name in ('native.rbxm','facts.json','capture-completion.json')}
    facts=json.loads(inputs['facts.json'])
    completion=json.loads(inputs['capture-completion.json'])
    assert facts['schema']=='external-held-storage-archive-v1'
    assert facts['placeId']==131311258779917 and facts['universeId']==10559217407
    assert completion['schema']=='external-held-storage-capture-completion-v1' and completion['report']['pass'] is True
    assert facts['nativeSHA256']==sha(inputs['native.rbxm'])==completion['report']['nativeSHA256']
    assert facts['nativeBytes']==len(inputs['native.rbxm'])==completion['report']['nativeBytes']
    assert len(facts['roots'])==23 and {r['name'] for r in facts['roots']}==EXPECTED_NAMES
    assert all(r['parentIsNil'] and r['originalHeldReference'] for r in facts['roots'])
    assert len(facts['heldSources'])==12 and len({r['path'] for r in facts['heldSources']})==12
    assert facts['heldNodeCount']==len(facts['nodes'])==sum(r['nodes'] for r in facts['roots'])<=25000
    assert facts['nativeMutations']==facts['sourceWrites']==facts['modeSwitches']==0
    assert facts['removalAttributedToCleanup'] is False and facts['restorationCertified'] is False
    assert all(r['archivable'] is True and r['sandboxed'] is False for r in facts['nodes'])
    native=inputs['native.rbxm']
    context={'schema':SCHEMA,'roots':facts['roots'],'heldSources':facts['heldSources'],
             'heldNodeCount':facts['heldNodeCount'],'nativeBytes':len(native),'nativeSHA256':sha(native),
             'nativeParts':(len(native)+PART_BYTES-1)//PART_BYTES}
    assert 0<context['nativeParts']<1000
    context_raw=json.dumps(context,separators=(',',':')).encode()
    source_path=Path(__file__).with_suffix('.luau')
    source_raw=source_path.read_bytes()
    def input_guard():
        assert source_path.read_bytes()==source_raw,'Concurrent reopen helper changed'
        for name,raw in inputs.items():
            assert (archive/name).read_bytes()==raw,'Concurrent archive input changed: '+name
    input_guard()
    dest.mkdir(parents=True)
    def save(name,data):
        path=dest/name
        if path.exists():
            assert path.read_bytes()==data,'Immutable proof conflict'
        else:
            with path.open('xb') as stream:
                assert stream.write(data)==len(data)
    save('reopen-source.luau',source_raw)
    provenance={'schema':'external-held-storage-reopen-inputs-v1','archivePath':archive.relative_to(ROOT).as_posix(),
                'files':{name:{'sha256':sha(raw),'bytes':len(raw)} for name,raw in inputs.items()},
                'reopenSourceSHA256':sha(source_raw),'placeId':131311258779917,'universeId':10559217407,
                'restorationCertified':False,'originalWrites':0}
    save('inputs.json',(json.dumps(provenance,indent=2)+'\n').encode())
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self,*_):
            pass
        def answer(self,data):
            self.send_response(200)
            self.send_header('Content-Length',str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        def do_GET(self):
            try:
                input_guard()
                if self.path=='/context':
                    return self.answer(context_raw)
                bits=self.path.strip('/').split('/')
                assert len(bits)==2 and bits[0]=='native'
                index=int(bits[1])
                assert 0<=index<context['nativeParts']
                self.answer(native[index*PART_BYTES:(index+1)*PART_BYTES])
            except Exception as error:
                self.send_error(409,str(error))
        def do_POST(self):
            try:
                input_guard()
                length=int(self.headers.get('Content-Length','0'))
                assert 0<length<=PART_BYTES
                data=self.rfile.read(length)
                assert len(data)==length,'Incomplete HTTP part'
                if self.path=='/finalize':
                    info=json.loads(data)
                    assert set(info)=={'parts','bytes','sha256'} and type(info['parts']) is int and 0<info['parts']<1000
                    raw=b''.join((dest/f'roundtrip-part-{i:04d}.bin').read_bytes() for i in range(info['parts']))
                    assert len(raw)==info['bytes'] and sha(raw)==info['sha256']
                    save('roundtrip.rbxm',raw)
                    save('transfer-receipt.json',data)
                else:
                    bits=self.path.strip('/').split('/')
                    assert len(bits)==2 and bits[0]=='roundtrip'
                    index=int(bits[1])
                    assert 0<=index<1000
                    save(f'roundtrip-part-{index:04d}.bin',data)
                self.answer(b'saved')
            except Exception as error:
                self.send_error(409,str(error))
    server=thread=client=None
    started=False
    try:
        server=http.server.ThreadingHTTPServer(('127.0.0.1',18915),Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        started=True
        client=StudioMcpClient(find_mcp_batch())
        client.initialize()
        studio=select_studio(client,RELEASE_STUDIO_NAME,15)
        assert studio['id']=='1b603e69-7ae1-4572-b210-d5bf05c684ff','Wrong Studio session'
        current=client.call('get_studio_state',{'studio_id':studio['id']})
        assert 'Current Studio Mode: Edit' in current,'Edit unavailable; preserve active Play'
        input_guard()
        result=client.call('execute_luau',{'studio_id':studio['id'],'datamodel_type':'Edit','code':source_raw.decode('utf8')})
        save('reopen-result.txt',result.encode())
        report=json.loads(result)
        assert report['schema']==SCHEMA
        assert report['pass'] is True,'Native owned-forest reopen or original/cleanup guard failed'
        assert report['createdRoots']==report['destroyedRoots']==23
        assert report['reconstructedNodes']==context['heldNodeCount'] and report['reconstructedSources']==12
        assert report['readableDataPass'] is True and report['internalReferencesPass'] is True and report['originalSourcesUnchanged'] is True
        assert report['sourceWrites']==report['originalParentWrites']==report['modeSwitches']==0
        assert report['restorationCertified'] is False and report['removalAttributedToCleanup'] is False
        assert (dest/'transfer-receipt.json').is_file()
        roundtrip=(dest/'roundtrip.rbxm').read_bytes()
        assert report['archiveSHA256']==context['nativeSHA256'] and report['roundtripSHA256']==sha(roundtrip) and report['roundtripBytes']==len(roundtrip)
        assert report['nativeSerializedBytesExact']==(roundtrip==native)
        input_guard()
        receipt={'schema':'external-held-storage-reopen-completion-v1','report':report,
                 'inputProvenanceSHA256':sha((dest/'inputs.json').read_bytes()),'reopenSourceSHA256':sha(source_raw),
                 'roundtripSHA256':sha(roundtrip),'restorationCertified':False,'originalWrites':0,
                 'nativeApiDocumentation':'https://create.roblox.com/docs/reference/engine/classes/SerializationService'}
        save('reopen-completion.json',(json.dumps(receipt,indent=2)+'\n').encode())
        print(json.dumps({key:report[key] for key in ('pass','createdRoots','destroyedRoots','reconstructedNodes','reconstructedSources','nativeSerializedBytesExact','roundtripSHA256','restorationCertified')}))
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
