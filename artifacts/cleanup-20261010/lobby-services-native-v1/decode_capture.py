"""Decode a known-completed bounded native capture; never contact Studio."""
from pathlib import Path
import argparse
import base64
import hashlib
import json
import sys
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / '_local/optimization-20261009/vendor'))
import zstandard
assert zstandard.__version__ == '0.25.0', 'Use the existing task-isolated reviewed dependency'

def decode(envelope):
    assert isinstance(envelope, dict)
    assert set(envelope) == {'schema', 'encoding', 'rawBytes', 'rawSHA256', 'compressedBytes', 'compressedSHA256', 'data'}
    assert envelope['schema'] == 'mongotv-lobby-native-compressed-envelope-v2' and envelope['encoding'] == 'zstd/base64'
    assert type(envelope['rawBytes']) is int and 0 < envelope['rawBytes'] <= 1000000
    assert type(envelope['compressedBytes']) is int and 0 < envelope['compressedBytes'] <= 60000
    assert isinstance(envelope['data'], str) and 0 < len(envelope['data']) <= 80000
    assert len(json.dumps(envelope, ensure_ascii=False).encode('utf-8')) <= 85000
    for key in ('rawSHA256', 'compressedSHA256'):
        value = envelope[key]
        assert isinstance(value, str) and len(value) == 64 and all(char in '0123456789abcdef' for char in value)
    compressed = base64.b64decode(envelope['data'], validate=True)
    assert len(compressed) == envelope['compressedBytes']
    assert hashlib.sha256(compressed).hexdigest() == envelope['compressedSHA256']
    frame = zstandard.get_frame_parameters(compressed)
    assert frame.content_size == envelope['rawBytes'] and frame.window_size <= 1000000
    # Header-size gate precedes decompression; API max_output_size alone is insufficient.
    raw = zstandard.ZstdDecompressor().decompress(compressed, max_output_size=envelope['rawBytes'], allow_extra_data=False)
    assert len(raw) == envelope['rawBytes'] and hashlib.sha256(raw).hexdigest() == envelope['rawSHA256']
    result = json.loads(raw.decode('utf-8'))
    assert result['schema'] == 'mongotv-lobby-owned-native-baseline-v1' and result['pass'] is True
    assert result['attributeEncoding'] == 'roblox-attribute-components-v1'
    assert result['originalSourceWrites'] == 0 and result['modeSwitches'] == 0 and result['objectsCreated'] == 0
    assert isinstance(result['rows'], list) and len(result['rows']) == 213
    assert isinstance(result['assetRows'], list) and 0 < len(result['assetRows']) <= 400
    assert len({row['meta']['instanceId'] for row in result['rows']}) == 213
    assert len({row['meta']['studioPath'] for row in result['rows']}) == 213
    for row in result['rows']:
        assert type(row['bytes']) is int and row['bytes'] >= 0
        assert row['meta']['className'] in ('ModuleScript', 'Script', 'LocalScript')
        assert isinstance(row['sha256'], str) and len(row['sha256']) == 64
    return raw, result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, help='Raw capture envelope text from a known completed successful MCP response')
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    source, target = Path(args.input), Path(args.output)
    assert not target.exists(), 'Immutable baseline already exists'
    raw, result = decode(json.loads(source.read_text(encoding='utf-8')))
    with target.open('xb') as file:
        file.write(raw)
    print(json.dumps({'pass': True, 'rawBytes': len(raw), 'rawSHA256': hashlib.sha256(raw).hexdigest(),
                      'originalRows': len(result['rows']), 'assetRows': len(result['assetRows']),
                      'nativeCalls': 0, 'productionWrites': 0}))

if __name__ == '__main__':
    main()
