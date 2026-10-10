"""Root executes the exact read-only capture packet once; no mode switch or retry."""
from pathlib import Path
import hashlib, json, sys, time
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
SID='b609b91a-e648-42ab-ba5f-a996912e9552'
PACKET=HERE/'capture-packet-v1'
SOURCE_SHA='236f5a90bec0c68032fc956783ada94247482c21a3f713ffc280683b02830a9c'
source=(PACKET/'execute.luau').read_bytes()
assert len(source)==33570 and hashlib.sha256(source).hexdigest()==SOURCE_SHA
request=json.loads((PACKET/'request.json').read_bytes())
assert request=={'schema':'mongotv-lobby-owned-native-request-v1','nativeScriptCount':213,
                 'operation':'capture','variant':'before','fault':'none'}
RUN=HERE/'root-capture-run-v1'
assert not RUN.exists(); RUN.mkdir()
def save(name,value):
    raw=value if isinstance(value,bytes) else (json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode()
    with (RUN/name).open('xb') as stream: assert stream.write(raw)==len(raw)
    return hashlib.sha256(raw).hexdigest()
save('request-provenance.json',{'studioId':SID,'sourceSHA256':SOURCE_SHA,'nativeWrites':0,'noRetry':True})
sys.path.insert(0,str(ROOT/'tools'))
from sync_from_studio import StudioMcpClient,find_mcp_batch,require_edit_state
client=StudioMcpClient(find_mcp_batch())
try:
    client.initialize(); require_edit_state(client,SID)
    started=time.monotonic()
    try:
        api=client._request('tools/call',{'name':'execute_luau','arguments':{
            'studio_id':SID,'datamodel_type':'Edit','code':source.decode()}},timeout=180)
    except BaseException as error:
        save('unknown-transport.json',{'nativeOutcome':'unknown; stop follow-up native calls',
             'error':str(error),'localTransportCloseIsNotCancellation':True})
        raise
    save('root-api.json',api)
    result=api.get('result')
    if not isinstance(result,dict) or not isinstance(result.get('content'),list):
        save('unknown-envelope.json',{'nativeOutcome':'unknown; stop follow-up native calls'})
        raise AssertionError('Unknown native completion envelope')
    raw='\n'.join(c.get('text','') for c in result['content'] if c.get('type')=='text').encode()
    raw_sha=save('root-completion-raw.txt',raw)
    assert not result.get('isError'),'Known completed tool error; no retry'
    assert len(raw)<=600000,'Bounded capture response exceeded'
    proof=json.loads(raw)
    save('root-completion.json',proof)
    assert proof['schema']=='mongotv-lobby-owned-native-baseline-v1' and proof['pass'] is True
    assert len(proof['rows'])==213 and len(proof['assetRows'])==196
    assert proof['session']['placeId']==131311258779917 and proof['session']['universeId']==10559217407
    for key in ('originalSourceWrites','modeSwitches','objectsCreated'): assert proof[key]==0,key
    assert len({r['meta']['instanceId'] for r in proof['rows']})==213
    assert len({r['instanceId'] for r in proof['assetRows']})==196
    save('root-review.json',{'pass':True,'sourceSHA256':SOURCE_SHA,'actualCompletionRawSHA256':raw_sha,
         'captureAtUtc':proof['readAtUtc'],'nativeSourceCount':213,'nativeR4Rows':196,
         'nativeManifestSHA256':proof['nativeManifestSHA256'],'nativeWrites':0,
         'wallSeconds':round(time.monotonic()-started,3),'limits':'Fresh Source/editor metadata and native R4 manifest capture; no runtime execution or gameplay/performance test.'})
    print(json.dumps({'pass':True,'rows':len(proof['rows']),'assetRows':len(proof['assetRows']),
                      'rawSHA256':raw_sha,'readAtUtc':proof['readAtUtc']}))
finally:
    client.close()
