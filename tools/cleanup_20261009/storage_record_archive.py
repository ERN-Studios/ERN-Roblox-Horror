"""Immutable loopback native export receiver; no mode switching or deletion."""
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

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--dest',type=Path,required=True)
    args=p.parse_args()
    dest=args.dest.resolve()
    assert dest.is_relative_to(ROOT),'Archive destination must remain in workspace'
    assert not dest.exists(),'Refuse archive overwrite'
    dest.mkdir(parents=True)
    def save(name,data):
        path=dest/name
        if path.exists():
            assert path.read_bytes()==data,'Immutable transfer changed'
        else:
            path.write_bytes(data)
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
            self.answer(b'{"schema":"folder-diagnostic-archive-v1"}')
        def do_POST(self):
            try:
                length=int(self.headers.get('Content-Length','0'))
                assert 0<length<=750000
                data=self.rfile.read(length)
                if self.path=='/finalize':
                    transfers=json.loads(data)
                    for kind in ('native','references','facts'):
                        meta=transfers[kind]
                        assert 0<meta['parts']<1000
                        raw=b''.join((dest/f'{kind}-part-{i:04d}.bin').read_bytes() for i in range(meta['parts']))
                        assert len(raw)==meta['bytes'] and hashlib.sha256(raw).hexdigest()==meta['sha256']
                        save(kind+'.rbxm' if kind!='facts' else 'facts.json',raw)
                    facts=json.loads((dest/'facts.json').read_bytes())
                    assert facts['schema']=='folder-diagnostic-archive-v1'
                    assert facts['placeId']==131311258779917 and facts['universeId']==10559217407
                    assert facts['nativeSHA256']==transfers['native']['sha256'] and facts['nativeBytes']==transfers['native']['bytes']
                    assert facts['referencesSHA256']==transfers['references']['sha256'] and facts['referencesBytes']==transfers['references']['bytes']
                    assert len(facts['roots'])==12 and all(r['class']=='Folder' and r['children']==0 for r in facts['roots'])
                    save('transfer-receipt.json',data)
                else:
                    bits=self.path.strip('/').split('/')
                    assert len(bits)==2 and bits[0] in ('native','references','facts')
                    index=int(bits[1]);assert 0<=index<1000
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
        state=client.call('get_studio_state',{'studio_id':studio['id']})
        assert 'Current Studio Mode: Edit' in state,'Keep other sessions intact; Edit unavailable'
        result=client.call('execute_luau',{'studio_id':studio['id'],'datamodel_type':'Edit',
            'code':(Path(__file__).with_name('capture_storage_records.luau')).read_text(encoding='utf8')})
        save('capture-result.txt',result.encode())
        assert (dest/'transfer-receipt.json').exists(),'Native capture failed; no deletion authorized'
        print(result)
    finally:
        # Each acquired resource gets its cleanup even when setup or another
        # cleanup fails. shutdown() requires a started serve_forever thread.
        primary=sys.exc_info()[1]
        cleanup_errors=[]
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
                cleanup_errors.append((label,error))
        if cleanup_errors:
            error=primary if primary is not None else cleanup_errors[0][1]
            for label,problem in cleanup_errors:
                error.add_note(f'Cleanup {label} failed: {problem}')
            if primary is None:
                raise error

if __name__=='__main__':
    main()
