"""Read-only R4 package/catalog review plus isolated localhost GET tests.

Temporary negative fixtures never modify candidate files, assets or Studio.
"""
from pathlib import Path
import copy, hashlib, importlib.util, json, re, selectors, socket, struct
import base64, subprocess, sys, tempfile, urllib.error, urllib.request

ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).parent
spec=importlib.util.spec_from_file_location('r4_server_review',ROOT/'tools/lobby_reimagined/serve_r4.py')
server=importlib.util.module_from_spec(spec);spec.loader.exec_module(server)
results=[]
def check(name,fn):
    try:fn();results.append({'name':name,'passed':True})
    except Exception as ex:results.append({'name':name,'passed':False,'error':str(ex)})
def rejected(fn):
    try:fn()
    except (AssertionError,UnicodeError,ValueError,KeyError):return
    raise AssertionError('Malformed fixture was accepted')
def sha(b):return hashlib.sha256(b).hexdigest()

package,manifest,payload=server.load_package(server.DEFAULT)
catalog=server.load_catalog(package,manifest,payload)
check('real package and exact seven-source catalog validate',lambda: (
    len(catalog['sources'])==7 or (_ for _ in ()).throw(AssertionError('source count'))))
check('nine missing asset IDs keep installer blocked',lambda: (
    catalog['readyForInstaller'] is False and len(catalog['packageBlockers'])==9
    or (_ for _ in ()).throw(AssertionError('missing-ID gate'))))

with tempfile.TemporaryDirectory(prefix='r4-serving-peer-') as td:
    temporary=Path(td)
    def bad_catalog(change):
        changed=copy.deepcopy(catalog);change(changed)
        file=temporary/'catalog.json';file.write_text(json.dumps(changed))
        rejected(lambda:server.load_catalog(package,manifest,dict(payload),file))
    for name,change in (
        ('wrong place rejected',lambda x:x.__setitem__('placeId',1)),
        ('wrong universe rejected',lambda x:x.__setitem__('universeId',1)),
        ('wrong creator group rejected',lambda x:x.__setitem__('groupId',1)),
        ('manifest digest change rejected',lambda x:x['payload'].__setitem__('manifestSHA256','0'*64)),
        ('out-of-scope Source path rejected',lambda x:x['sources'][3].__setitem__('path','ServerScriptService.Unrelated')),
        ('wrong Source class rejected',lambda x:x['sources'][0].__setitem__('class','Script')),
        ('new Source creation rejected',lambda x:x['sources'][0].__setitem__('isNew',True)),
        ('Source/editor baseline conflict rejected',lambda x:x['sources'][0].__setitem__('expectedEditorSourceSHA256','0'*64)),
        ('candidate digest change rejected',lambda x:x['sources'][0].__setitem__('afterSHA256','0'*64)),
        ('candidate byte length change rejected',lambda x:x['sources'][0].__setitem__('candidateBytes',1)),
        ('duplicate route key rejected',lambda x:x['sources'][1].__setitem__('key',x['sources'][0]['key'])),
        ('candidate path traversal rejected',lambda x:x['sources'][0].__setitem__('candidateFile','../AGENTS.md')),
    ):check(name,lambda c=change:bad_catalog(c))

    first=manifest['chunks'][0]
    original=base64.b64decode((package/first['file']).read_bytes())
    def bad_mesh(change_raw=None,change_chunk=None):
        changed=copy.deepcopy(manifest);chunk=changed['chunks'][0];raw=bytearray(original)
        if change_raw:
            change_raw(raw);chunk['sha256']=sha(raw)
        if change_chunk:change_chunk(chunk)
        file=temporary/chunk['file'];file.parent.mkdir(parents=True,exist_ok=True)
        file.write_bytes(base64.b64encode(raw));(temporary/'manifest.json').write_text(json.dumps(changed))
        rejected(lambda:server.load_package(temporary))
    check('corrupted prefab digest rejected before missing later files',lambda:bad_mesh(change_chunk=lambda c:c.__setitem__('sha256','0'*64)))
    check('NaN vertex rejected with otherwise valid byte length and digest',lambda:bad_mesh(change_raw=lambda b:struct.pack_into('<f',b,20,float('nan'))))
    def wrong_index(b):
        _,nv,nn,nu,_=struct.unpack_from('<5I',b)
        struct.pack_into('<I',b,20+nv*12+nn*12+nu*8,nv)
    check('out-of-range triangle vertex rejected with otherwise valid digest',lambda:bad_mesh(change_raw=wrong_index))
    check('invalid zero-volume prefab bounds rejected',lambda:bad_mesh(change_chunk=lambda c:c['size'].__setitem__(0,0)))

# Bind a new ephemeral loopback server. Never use or stop root's server.
with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
proc=subprocess.Popen([sys.executable,str(ROOT/'tools/lobby_reimagined/serve_r4.py'),'--port',str(port)],
                      cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
try:
    selector=selectors.DefaultSelector();selector.register(proc.stdout,selectors.EVENT_READ)
    assert selector.select(10),'Isolated server readiness timed out'
    ready=json.loads(proc.stdout.readline());assert ready['passed'] and ready['sources']==7
    base=f'http://127.0.0.1:{port}'
    def route(path,expected,mime):
        with urllib.request.urlopen(base+path,timeout=5) as response:
            body=response.read();assert body==expected
            assert response.headers['Content-Type']==mime
            assert int(response.headers['Content-Length'])==len(body)
    check('HTTP exact manifest/catalog bytes and JSON types',lambda: (
        route('/manifest',payload['/manifest'],'application/json'),
        route('/catalog',payload['/catalog'],'application/json')))
    check('HTTP all seven exact Source bodies and lengths',lambda: [route('/source/'+s['key'],payload['/source/'+s['key']],'text/plain') for s in catalog['sources']])
    check('HTTP all nine PNG upload routes return exact validated PNGs',lambda: [route(p,b,'image/png') for p,b in payload.items() if p.startswith('/texture/')])
    check('HTTP prefab and atlas route return exact encoded bodies',lambda: (
        route('/chunk/0',payload['/chunk/0'],'text/plain'),
        route('/pixels/atlas',payload['/pixels/atlas'],'text/plain')))
    def absent(path):
        try:urllib.request.urlopen(base+path,timeout=5)
        except urllib.error.HTTPError as ex:assert ex.code==404;return
        raise AssertionError('Unknown route accepted')
    check('HTTP unrelated Source and traversal routes rejected',lambda: [absent(p) for p in (
        '/source/unrelated','/source/../../AGENTS.md','/../AGENTS.md','/texture/unknown/color.png')])
finally:
    proc.terminate()
    try:proc.wait(timeout=3)
    except subprocess.TimeoutExpired:proc.kill();proc.wait(timeout=3)

prepared=ROOT/'artifacts/lobby-rebuild-r4-20261001/install-r4-prepared.luau'
raw=prepared.read_bytes();text=raw.decode()
plan=json.loads(re.search(r'local PLAN=HS:JSONDecode\(\[=\[(.*?)\]=\]\)',text,re.S).group(1))
check('prepared installer is pinned and blocks before staging/mutations',lambda: (
    sha(raw)=='4b27b3958bd76574e9721791af45ea76b4d4647ab2bdbf5ad7b48b260fefb6a2'
    and plan['readyForInstaller'] is False and len(plan['sources'])==7
    and text.index('assert(PLAN.readyForInstaller==true')<text.index('local staging=Instance.new')
    or (_ for _ in ()).throw(AssertionError('prepared installer gate/hash'))))
report={'passed':all(r['passed'] for r in results),'tests':results,
        'scope':'Local package/catalog validation and isolated loopback GET server only; no Studio execution, writes, Play, asset upload or publication',
        'preparedInstallerSHA256':sha(raw),'catalogSHA256':sha(payload['/catalog']),
        'manifestSHA256':sha(payload['/manifest']),'readyForInstaller':plan['readyForInstaller']}
(OUT/'installer-serving-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'passed':report['passed'],'testCount':len(results),'failed':[r for r in results if not r['passed']],'preparedInstallerSHA256':sha(raw)},indent=2))
assert report['passed'],'Local installer-serving validation failed'
