"""Recover retained direct-return chunks; verify Sources without a native-backup claim."""
from pathlib import Path
import argparse
import base64
import hashlib
import json

p = argparse.ArgumentParser()
p.add_argument('--directory', type=Path, required=True)
p.add_argument('--expected-catalog-sha256', required=True)
args = p.parse_args()
directory = args.directory
first = json.loads((directory / 'catalog-first.json').read_text())
second = json.loads((directory / 'catalog-second.json').read_text())
assert first['sources'] == second['sources'] and first['roots'] == second['roots']
assert first['scriptCount'] == len(first['sources']) == 231
assert (first['placeId'], first['universeId'], first['groupId']) == (131311258779917, 10559217407, 1039373905)
expected = {row['path']: row for row in first['sources']}
assert len(expected) == 231
rows, chunks = {}, {}
parts = sorted(directory.glob('part-*.json'))
assert [f.name for f in parts] == [f'part-{i:04d}.json' for i in range(len(parts))]
assert len(parts) == 209
keys = ['path', 'class', 'sourceBytes', 'sourceSha256', 'editorSourceSha256', 'editorMatch']
for part in parts:
    data = json.loads(part.read_text())
    if data['kind'] == 'small':
        for row in data['rows']:
            assert row['path'] not in rows and row['path'] not in chunks
            rows[row['path']] = row
    else:
        assert data['kind'] == 'chunk' and data['path'] not in rows
        value = base64.b64decode(data['base64'], validate=True)
        assert len(value) == data['length']
        assert all(data[key] == expected[data['path']][key] for key in keys)
        chunks.setdefault(data['path'], []).append((data['offset'], value))
for path, pieces in chunks.items():
    offset, values = 0, []
    for start, value in sorted(pieces):
        assert start == offset
        offset += len(value)
        values.append(value)
    rows[path] = dict(expected[path], source=b''.join(values).decode('utf-8'))
assert set(rows) == set(expected)
for path, row in rows.items():
    assert all(row[key] == expected[path][key] for key in keys)
    value = row['source'].encode()
    assert row['editorMatch'] and len(value) == row['sourceBytes']
    assert hashlib.sha256(value).hexdigest() == row['sourceSha256'] == row['editorSourceSha256']
value = (json.dumps([rows[path] for path in sorted(rows)], ensure_ascii=False, separators=(',', ':')) + '\n').encode()
digest = hashlib.sha256(value).hexdigest()
assert digest == args.expected_catalog_sha256
output = directory / 'scripts.json'
if output.exists():
    assert output.read_bytes() == value
else:
    output.write_bytes(value)
print(json.dumps({'sourceCount': len(rows), 'sourceCatalogSHA256': digest, 'sourceCatalogBytes': len(value), 'scriptsPath': str(output)}))
