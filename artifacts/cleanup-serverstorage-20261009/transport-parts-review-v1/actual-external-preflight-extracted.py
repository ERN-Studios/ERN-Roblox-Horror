def actual_readonly_preflight(args):
    archive = args.archive.resolve()
    dest = args.dest.resolve()
    assert archive.is_relative_to(ROOT) and archive.is_dir(), 'Existing archive inside workspace required'
    assert dest.is_relative_to(ROOT) and (not dest.exists()), 'New proof destination inside workspace required'
    inputs = {name: (archive / name).read_bytes() for name in ('native.rbxm', 'facts.json', 'capture-completion.json')}
    facts = json.loads(inputs['facts.json'])
    completion = json.loads(inputs['capture-completion.json'])
    assert facts['schema'] == 'external-held-storage-archive-v1'
    assert facts['placeId'] == 131311258779917 and facts['universeId'] == 10559217407
    assert completion['schema'] == 'external-held-storage-capture-completion-v1' and completion['report']['pass'] is True
    assert facts['nativeSHA256'] == sha(inputs['native.rbxm']) == completion['report']['nativeSHA256']
    assert facts['nativeBytes'] == len(inputs['native.rbxm']) == completion['report']['nativeBytes']
    assert len(facts['roots']) == 23 and {r['name'] for r in facts['roots']} == EXPECTED_NAMES
    assert all((r['parentIsNil'] and r['originalHeldReference'] for r in facts['roots']))
    assert len(facts['heldSources']) == 12 and len({r['path'] for r in facts['heldSources']}) == 12
    assert facts['heldNodeCount'] == len(facts['nodes']) == sum((r['nodes'] for r in facts['roots'])) <= 25000
    assert facts['nativeMutations'] == facts['sourceWrites'] == facts['modeSwitches'] == 0
    assert facts['removalAttributedToCleanup'] is False and facts['restorationCertified'] is False
    assert all((r['archivable'] is True and r['sandboxed'] is False for r in facts['nodes']))
    native = inputs['native.rbxm']
    return (inputs, facts, completion, native)