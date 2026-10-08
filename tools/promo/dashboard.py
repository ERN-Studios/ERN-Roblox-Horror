"""Drive the game's Creator Dashboard tab in the owner's Chrome without touching the mouse or the keyboard.

    python3 tools/promo/dashboard.py js '<expression>'       # run JavaScript in the tab, print what it returns
    python3 tools/promo/dashboard.py jsfile path.js
    python3 tools/promo/dashboard.py give path/to/picture.png # hand a file to the page's file input

It talks to the tab whose address holds the experience id, through Chrome's own scripting (AppleScript "execute
javascript"), which only works because "Allow JavaScript from Apple Events" is switched on in the owner's Chrome.
The tab may be in the background: nothing here brings Chrome forward or types or clicks for real. A picture is
handed over as base64 in pieces (an Apple Event of several megabytes is asking for trouble) and put on the page's
`<input type=file>` with a change event, which is what choosing it in the file dialog would have done.
"""
import base64
import json
import subprocess
import sys
import tempfile
from pathlib import Path

EXPERIENCE = '10559217407'
PIECE = 480_000          # characters of base64 per call

# Which tab: the first whose address holds this text. The store pages by default; the Ads Manager sets
# `dashboard.TAB = 'create.roblox.com/advertise'` (or whatever its address holds) before calling.
TAB = 'create.roblox.com/dashboard/creations/experiences/%s' % EXPERIENCE

OSA = '''on run argv
set js to read (POSIX file (item 1 of argv)) as «class utf8»
tell application "Google Chrome"
repeat with w in windows
repeat with t in tabs of w
if (URL of t) contains (item 2 of argv) then
return (execute t javascript js)
end if
end repeat
end repeat
return "NO TAB WITH " & (item 2 of argv)
end tell
end run'''


def js(source, timeout=60):
    with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False, encoding='utf-8') as f:
        f.write(source)
    try:
        done = subprocess.run(['osascript', '-e', OSA, f.name, TAB], capture_output=True, text=True, timeout=timeout)
    finally:
        Path(f.name).unlink(missing_ok=True)
    if done.returncode:
        raise RuntimeError(done.stderr.strip())
    return done.stdout.rstrip('\n')


def give(path, name=None):
    """Put one file on the page's file input, as if it had been picked in the file dialog."""
    path = Path(path)
    name = name or path.name
    data = base64.b64encode(path.read_bytes()).decode()
    key = json.dumps(name)
    js(f'(window.__up = window.__up || {{}}, window.__up[{key}] = "", "ready")')
    for i in range(0, len(data), PIECE):
        got = js(f'(window.__up[{key}] += "{data[i:i + PIECE]}", String(window.__up[{key}].length))')
        assert int(float(got)) == min(i + PIECE, len(data)), got
    kind = {'.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg'}[path.suffix.lower()]
    return js(f'''(() => {{ try {{
  const bin = atob(window.__up[{key}]);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  delete window.__up[{key}];
  const file = new File([bytes], {key}, {{type: "{kind}"}});
  const input = document.querySelector('input[type=file]');
  const dt = new DataTransfer();
  dt.items.add(file);
  input.files = dt.files;
  input.dispatchEvent(new Event('change', {{bubbles: true}}));
  return 'gave ' + file.name + ' ' + file.size + ' bytes';
}} catch (e) {{ return 'ERROR ' + e.message; }} }})()''')


def call(method, url, body=None, form=None, kind='application/json', wait=90, fields=None):
    """One request to a Roblox service FROM THE PAGE, so it carries the owner's signed-in session the way the
    dashboard's own Save button does. Roblox answers a first write with 403 and a token; the write is then sent
    again with it. `form` is {field: [names handed over with stage()]} for a multipart upload, `fields` is
    {field: text} for plain form fields. Returns (status, text).
    Chrome does not wait for a promise, so the answer is left in the page and fetched with a second look."""
    import time
    spec = json.dumps(dict(method=method, url=url, body=body, form=form, kind=kind, fields=fields))
    js("""(() => { const q = %s; window.__ans = null;
  const send = async token => {
    const init = {method: q.method, credentials: 'include', headers: {}};
    if (token) init.headers['x-csrf-token'] = token;
    if (q.form || q.fields) { const fd = new FormData(); for (const [field, names] of Object.entries(q.form || {})) for (const n of names) fd.append(field, window.__files[n], n); for (const [field, text] of Object.entries(q.fields || {})) fd.append(field, text); init.body = fd; }
    else if (q.body !== null) { init.headers['Content-Type'] = q.kind; init.body = JSON.stringify(q.body); }
    return fetch(q.url, init);
  };
  (async () => { try {
    let r = await send(window.__csrf);
    const t = r.headers.get('x-csrf-token');
    if (r.status === 403 && t) { window.__csrf = t; r = await send(t); }
    window.__ans = JSON.stringify({status: r.status, text: (await r.text()).slice(0, 20000)});
  } catch (e) { window.__ans = JSON.stringify({status: 0, text: 'ERROR ' + e.message}); } })();
  return 'sent'; })()""" % spec)
    end = time.time() + wait
    while time.time() < end:
        got = js('window.__ans || ""')
        if got:
            answer = json.loads(got)
            return answer['status'], answer['text']
        time.sleep(0.6)
    return -1, 'no answer in %d s' % wait


def stage(path, name=None):
    """Hand a file to the page and keep it there as a File (window.__files[name]) for a later upload."""
    path = Path(path)
    name = name or path.name
    data = base64.b64encode(path.read_bytes()).decode()
    key = json.dumps(name)
    js(f'(window.__up = window.__up || {{}}, window.__files = window.__files || {{}}, window.__up[{key}] = "", "ready")')
    for i in range(0, len(data), PIECE):
        got = js(f'(window.__up[{key}] += "{data[i:i + PIECE]}", String(window.__up[{key}].length))')
        assert int(float(got)) == min(i + PIECE, len(data)), got
    kind = {'.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
            '.mp3': 'audio/mpeg', '.ogg': 'audio/ogg', '.wav': 'audio/wav'}[path.suffix.lower()]
    return js(f"""(() => {{ try {{
  const bin = atob(window.__up[{key}]);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  delete window.__up[{key}];
  window.__files[{key}] = new File([bytes], {key}, {{type: "{kind}"}});
  return 'staged ' + {key} + ' ' + window.__files[{key}].size + ' bytes';
}} catch (e) {{ return 'ERROR ' + e.message; }} }})()""")


if __name__ == '__main__':
    if '--tab' in sys.argv:
        i = sys.argv.index('--tab')
        TAB = sys.argv[i + 1]
        del sys.argv[i:i + 2]
    what = sys.argv[1]
    if what == 'js':
        print(js(sys.argv[2]))
    elif what == 'jsfile':
        print(js(Path(sys.argv[2]).read_text()))
    elif what == 'give':
        print(give(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None))
