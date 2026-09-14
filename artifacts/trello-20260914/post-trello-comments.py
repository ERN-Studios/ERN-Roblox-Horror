"""Post the owner's authorized completion comments, preserving existing content."""
from pathlib import Path
import json
import requests

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
values = {}
for line in (ROOT / 'tools/discord_trello_bot/.env').read_text(encoding='utf-8').splitlines():
    key, sep, value = line.partition('=')
    if sep and not line.lstrip().startswith('#'):
        values[key.strip()] = value.strip()
auth = {'key': values['TRELLO_KEY'], 'token': values['TRELLO_TOKEN']}
plan = json.loads((HERE / 'trello-update-plan.json').read_text(encoding='utf-8'))
results = []
session = requests.Session()

def canonical(text):
    # Trello lowercases @handles when storing comments.
    return text.replace('(@Kecoalmutt)', '(@kecoalmutt)')

def call(method, path, fields=None):
    payload = {**auth, **(fields or {})}
    try:
        response = session.request(method, 'https://api.trello.com/1' + path,
            params=payload if method == 'GET' else None,
            data=payload if method != 'GET' else None, timeout=30)
    except requests.RequestException:
        raise RuntimeError('Trello request failed; inspect remote state before retrying') from None
    if not response.ok:
        raise RuntimeError('Trello HTTP status ' + str(response.status_code))
    return response.json()

for item in plan:
    card_id = item['cardId'].rsplit('/', 1)[-1]
    existing = call('GET', '/cards/' + card_id + '/actions', {'filter': 'commentCard', 'limit': 100})
    action = next((a for a in existing if canonical(a.get('data', {}).get('text', '')) == canonical(item['comment'])), None)
    reused = action is not None
    if not action:
        action = call('POST', '/cards/' + card_id + '/actions/comments', {'text': item['comment']})
    verified = call('GET', '/actions/' + action['id'])
    assert canonical(verified['data']['text']) == canonical(item['comment']), 'Comment readback mismatch'
    results.append({'card': item['url'], 'commentId': action['id'], 'verified': True, 'reused': reused})
    (HERE / 'trello-comment-results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    print(item['url'] + ': comment verified' + (' (already present)' if reused else ''), flush=True)
