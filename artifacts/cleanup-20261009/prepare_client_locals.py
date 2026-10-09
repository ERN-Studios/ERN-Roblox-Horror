"""Prepare small C04/C06/C07/C26 proposals and compiler evidence, never production writes.

Writes only owned .git checkpoint proposals and remaining-clients-proposals.json.
Run with --compiler pointing to official Luau0.737 luau-compile.exe.
"""
from pathlib import Path
import argparse
import difflib
import hashlib
import importlib.util
import json
import re
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts/cleanup-20261009'
TEMP = ROOT / '.git/mongotv-cleanup-20261009/client-proposals'
SHA = lambda data: hashlib.sha256(data).hexdigest()
LOADING = 'ReplicatedFirst/Lobby Loading Screen.LocalScript.lua'
ANNOUNCED_DEFINITION = '\tlocal function announced()\n\t\treturn tonumber(player:GetAttribute("LoadingLevel")) or tonumber(workspace:GetAttribute("SelectedLevel")) or 0\n\tend\n'


def preflight_loading_helper(source):
    """Fail closed before any proposal write if the exact helper closure changed.

    Any name reference outside the one reviewed definition is rejected,
    including aliases/comment mentions. Conservative rejection is preferable
    to mistaking a new caller for the formerly dead helper.
    """
    assert source.count(ANNOUNCED_DEFINITION) == 1, 'REFUSED C04 Loading: exact announced definition changed; no prepared artifacts written'
    begin = source.index(ANNOUNCED_DEFINITION)
    end = begin + len(ANNOUNCED_DEFINITION)
    uses = [match for match in re.finditer(r'\bannounced\b', source)
            if not begin <= match.start() < end]
    lines = [source.count('\n', 0, match.start()) + 1 for match in uses]
    assert not uses, f'REFUSED C04 Loading: announced has outside-definition references at lines {lines}; retain active helper; no prepared artifacts written'


def change(source, old, new=''):
    assert source.count(old) == 1, f'exact proposal block count: {old[:80]!r}'
    return source.replace(old, new, 1)


def replace_comments(source, start, stop, replacement):
    begin = source.index(start)
    end = source.index(stop, begin)
    block = source[begin:end]
    assert all(not line.strip() or line.lstrip().startswith('--') for line in block.splitlines()), 'comment block contains code'
    return source[:begin] + replacement + source[end:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    args = parser.parse_args()
    # All writes, including directory creation and immutable checkpoint files,
    # must follow this current-source closure gate. Never regenerate today's
    # proposals by blindly removing a now-active helper from a newer baseline.
    preflight_loading_helper((ROOT / LOADING).read_text(encoding='utf8'))
    spec = importlib.util.spec_from_file_location('c08_verifier', OUT / 'verify_C08.py')
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    TEMP.mkdir(parents=True, exist_ok=True)
    proposals = []

    def add(candidate, path, edits, symbols, gate):
        before = (ROOT / path).read_bytes().replace(b'\r\n', b'\n')
        source = before.decode('utf8')
        after = source
        for old, new in edits:
            after = change(after, old, new)
        after = after.encode()
        index = len(proposals) + 1
        stem = f'{candidate}-{index}-{Path(path).name}'
        before_path, after_path = TEMP / (stem + '.before.lua'), TEMP / (stem + '.candidate.lua')
        before_path.write_bytes(before)
        after_path.write_bytes(after)
        rows = []
        for optimization in (0, 1):
            compiled, dumps, binaries, metas = {}, {}, {}, {}
            for tag, file in [('before', before_path), ('candidate', after_path)]:
                options = ['-g0', f'-O{optimization}', str(file)]
                run = subprocess.run([args.compiler, '--binary', *options], capture_output=True, timeout=30)
                assert run.returncode == 0, run.stderr.decode()
                binaries[tag] = run.stdout
                compiled[tag], metas[tag] = verifier.canonical(run.stdout)
                dumps[tag] = subprocess.run([args.compiler, '--text', '--dump-constants', *options], check=True, capture_output=True, timeout=30).stdout
            rows.append({'optimization': optimization, 'debug': 0, 'compile': 'PASS',
                         'canonicalBinaryIdentical': compiled['before'] == compiled['candidate'],
                         'instructionConstantDumpIdentical': dumps['before'] == dumps['candidate'],
                         'beforeBinarySha256': SHA(binaries['before']), 'candidateBinarySha256': SHA(binaries['candidate']),
                         'canonicalBeforeSha256': SHA(compiled['before']), 'canonicalCandidateSha256': SHA(compiled['candidate']),
                         'beforeFunctionCount': len(metas['before']), 'candidateFunctionCount': len(metas['candidate'])})
        for name in symbols:
            assert len(re.findall(r'\b' + re.escape(name) + r'\b', source)) >= 1
            assert not re.search(r'\b' + re.escape(name) + r'\b', after.decode()), f'removed binding remains: {name}'
        proposals.append({'candidate': candidate, 'file': path, 'beforeSha256': SHA(before), 'candidateSha256': SHA(after),
                          'beforePath': str(before_path.relative_to(ROOT)), 'candidatePath': str(after_path.relative_to(ROOT)),
                          'beforeBytes': len(before), 'candidateBytes': len(after), 'removedBytes': len(before)-len(after),
                          'symbols': symbols, 'compiler': rows, 'requiredGate': gate, 'status': 'afventer contract gate',
                          'productionApplied': False, 'nativeApplied': False, 'manifestUpdated': False})

    add('C04', 'StarterPlayer/StarterCharacter/Animate.LocalScript.lua', [('\tlocal origRoll = roll\n', ''), ('\tlocal climbFudge = 0\n', '')], ['origRoll', 'climbFudge'], 'actual weighted animation-selection and stepAnimate unchanged-body contracts; O0/O1 compile')
    add('C04', 'StarterPlayer/StarterPlayerScripts/Level 3 Reader Client.LocalScript.lua', [
        ('local MAXIMUM_RANGE = 650\nlocal ACCURACY_DEGREES = {155, 105, 64, 36, 18, 5}\nlocal DISTANCE_NOISE = {0.60, 0.42, 0.27, 0.15, 0.07, 0.0}\n', ''),
        ("-- Full bars inside a room, one bar at roughly the far side of a district: the\n-- CD bar is plain proximity, not the exit's fogged signal.\nlocal CD_SIGNAL_RANGE = 260\n", ''),
        ('-- radians/second on a sine, so ~0.8Hz -- a text pulse, never a scene flash, and\n-- it never exceeds .40 transparency so the row stays legible at its dimmest.\nlocal ROOM_BLINK_RATE = 5.0\n', ''),
        ('local MUTED = UIStyle.Color.Muted\nlocal AMBER = UIStyle.Color.Warning\n', ''),
        ("-- The room indicator's red is the shared danger token, not a fourth level\n-- inventing its own (UI_STYLE_20260915).\nlocal DANGER = UIStyle.Color.Danger\n", ''),
    ], ['MAXIMUM_RANGE', 'ACCURACY_DEGREES', 'DISTANCE_NOISE', 'CD_SIGNAL_RANGE', 'ROOM_BLINK_RATE', 'MUTED', 'AMBER', 'DANGER'], 'pure local initializer closure and exact remaining executable source; UIStyle plain table contract and actual RoundHud reader/device/respawn contracts')
    add('C04', 'StarterPlayer/StarterPlayerScripts/Level 3 Table Hiding Client.LocalScript.lua', [('local HIDDEN_TEXT = "HIDDEN UNDER TABLE"\n', '')], ['HIDDEN_TEXT'], 'pure string literal/no initializer sideeffect, exact all remaining source and O0/O1 compile')
    add('C04', 'StarterPlayer/StarterPlayerScripts/Round Exit Client.LocalScript.lua', [('local HINT_HEIGHT = 36      -- two wrapped lines of the explanation band\n', '')], ['HINT_HEIGHT'], 'actual RoundExit hold/error/cancel/device/lifecycle contracts before/after')
    add('C04', 'ReplicatedStorage/RoundHud.ModuleScript.lua', [('local TOUCH_LANE_X, TOUCH_LANE_Y = 68, 52\n', '')], ['TOUCH_LANE_X', 'TOUCH_LANE_Y'], 'both literals unused currently; actual RoundHud detector PC/touch/layout/device flip/clear contracts before/after')
    add('C04', LOADING, [(ANNOUNCED_DEFINITION, '')], ['announced'], 'uncalled private local function has no initializer execution; exact loading worker/recovery/callers retained, O0/O1 compile')
    add('C06', 'StarterPlayer/StarterPlayerScripts/First Entry Guide.LocalScript.lua', [('local KEYS = touch and {sneak = "the sneak button", sprint = "the sprint button", light = "the flashlight button", use = "Tap the prompt"}\n\tor {sneak = "Hold Ctrl", sprint = "Hold Shift", light = "F", use = "Hold E"}\n', '')], ['KEYS'], 'pure literal table branch; actual current HELP/TOPICS controls/config copy renderer before/after; old first-entry suite is stale and not a pass')
    add('C06', 'StarterPlayer/StarterPlayerScripts/Level4PreviewPrompt.LocalScript.lua', [('-- ZenMeister02 can see only the isolated Level 6 preview doorway.\nif Players.LocalPlayer.UserId == 11374988579 then\n\tPROMPTS.Level6DeveloperPreviewPrompt = nil\n\tPROMPTS.Level6DeveloperPreviewReturnPrompt = nil\nend\n', '')], [], 'whole source ordinary/special/dev/missing/error allowlist; initial+late+reenabled L4 prompts, public L5/L6 and nonprompt objects before/after')
    add('C07', 'ReplicatedFirst/Lobby Loading Screen.LocalScript.lua', [('local kicker = label(', 'label('), ('local tip = label(', 'label(')], ['kicker', 'tip'], 'exact unchanged constructor arguments; actual loading cover authoring subtree snapshots before/after inclKicker/Tip')
    add('C07', 'StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua', [('local shopButtonRing = outline(shopButton, COLORS.accent, 0.22, 1.5)\n', 'outline(shopButton, COLORS.accent, 0.22, 1.5)\n')], ['shopButtonRing'], 'exact unchanged outline call; actual store rail construction/outline snapshot and current store authoring contract before/after')

    path = 'ReplicatedStorage/UIRegression.ModuleScript.lua'
    original = (ROOT / path).read_text(encoding='utf8')
    modified = replace_comments(original, '-- Briefing text fit, resolved per device\n', 'function Fit.bodyBriefingFitMatrix()',
        '-- BriefingFitMatrix: compatibility alias for the shared HUD matrix.\n-- ---------------------------------------------------------------------------\n-- Preserves this public lane name, token ownership and borrow/restore behavior.\n-- Current coverage is Fit.bodyRoundHudMatrix: shared objectives and native\n-- text bounds across device fixtures, plus admitted feed/caption checks.\n-- It does not run the retired analytical briefing layout or localisation corpus.\n\n')
    modified = replace_comments(modified, '-- BriefingExclusionMatrix -- briefing, queue modal and the L4 shop window (was the Zyntra terminal)\n', 'function Fit.bodyBriefingExclusionMatrix()',
        '-- BriefingExclusionMatrix: compatibility alias for the shared HUD matrix.\n-- ---------------------------------------------------------------------------\n-- Current checks are delegated to Fit.bodyRoundHudMatrix. This entrypoint no\n-- longer independently sweeps legacy briefing/terminal exclusion state or\n-- developer-page keyboard captions. Those old claims are not current coverage.\n\n')
    modified = change(modified, '-- Used by BriefingFitMatrix only. GetTextBoundsAsync is the ONE way to ask what\n', '-- Retained analytical text helper. GetTextBoundsAsync can ask what\n')
    modified = change(modified, '-- and wrap width the client is not currently rendering. Hoisted here from\n-- BriefingFitMatrix, which now shares it rather than keeping a second copy.\n', '-- and wrap width the client is not currently rendering. The current shared\n-- HUD matrix uses native TextBounds; it does not call this analytical helper.\n')
    modified = change(modified, "-- All three levels' persistent objective readouts, forced into every state they\n-- have, at every device in the matrix. The question it answers is the one the\n-- old suite could not even ask: not \"does this rectangle avoid the movement\n-- zones\" -- the corridor and bottom-band placements it replaced both did -- but\n-- \"is it in the UPPER RIGHT of the true safe area\", which is where the player\n-- was told to look for it.\n", '-- ObjectiveCornerMatrix delegates to the shared HUD matrix. It stages the\n-- current shared objective for Level 1 and Level 3 across the device fixtures.\n-- The legacy placement history below explains why the helper keeps a single\n-- expected corner; the shared card reserves 16 px on touch or 24 px on PC.\n')
    modified = change(modified, '-- touch, 18 on a pointer), within AnchorSlack.\n', '-- touch, 18 on a pointer), within AnchorSlack. Shared callers reserve their\n-- additional authored 16/24 px through Fit.anchorProblems rightInset.\n')
    modified = replace_comments(modified, '-- The compact contract for the phone briefing, asserted as a MAXIMUM footprint\n', 'Fit.DispatchReference =',
        '-- DispatchCompactMatrix is a compatibility alias for Fit.bodyRoundHudMatrix.\n-- It no longer asserts the legacy phone-briefing maximum footprint below.\n-- Keep DispatchReference as retained metadata; no current matrix reads it.\n')
    modified = change(modified, '\t-- Same contract, same reason: BriefingFitMatrix owns the override too, and\n\t-- it is the only thing in this file that can say whether the dispatch copy\n\t-- fits its box on a viewport Studio is not currently rendering.\n', '\t-- Run the shared HUD matrix once. The four compatibility aliases delegate\n\t-- to that same body, so repeating them would repeat identical fixture work.\n\t-- This lane measures current shared objectives and admitted feed/captions.\n')
    add('C26', path, [(original, modified)], [], 'comment-only: all instruction/constants/upvalues/function structure binary identical after only linedefined/proto-size canonicalization; shared authoring suite and exact public alias bodies unchanged')
    row = proposals[-1]
    assert all(port['canonicalBinaryIdentical'] and port['instructionConstantDumpIdentical'] for port in row['compiler']), 'C26 changes compiled behavior'
    row['status'] = 'compiler contract passed; afventer shared authoring gate'
    units = []
    for index, path in enumerate(dict.fromkeys(row['file'] for row in proposals), 1):
        members = [row for row in proposals if row['file'] == path]
        before = (ROOT / members[0]['beforePath']).read_bytes()
        lines = before.decode('utf8').splitlines(keepends=True)
        changes = []
        for member in members:
            assert (ROOT / member['beforePath']).read_bytes() == before
            candidate = (ROOT / member['candidatePath']).read_text(encoding='utf8').splitlines(keepends=True)
            for tag, first, last, a, b in difflib.SequenceMatcher(a=lines,b=candidate,autojunk=False).get_opcodes():
                if tag != 'equal': changes.append((first,last,candidate[a:b]))
        ordered = sorted(changes)
        for a,b in zip(ordered,ordered[1:]): assert a[1] <= b[0], 'overlapping candidate changes'
        combined = lines.copy()
        for first,last,replacement in reversed(ordered): combined[first:last] = replacement
        body = ''.join(combined).encode()
        target = TEMP / f'Install-{index}-{Path(path).name}.candidate.lua'
        target.write_bytes(body)
        compile_ports = members[0]['compiler']
        if len(members)>1:
            compile_ports=[]
            for optimization in [0,1]:
                run=subprocess.run([args.compiler,'--null','-g0',f'-O{optimization}',str(target)],capture_output=True,text=True,timeout=30)
                assert run.returncode==0,run.stderr
                compile_ports.append({'optimization':optimization,'debug':0,'compile':'PASS','exitCode':run.returncode,'stdout':run.stdout,'stderr':run.stderr})
        else:
            assert SHA(body)==members[0]['candidateSha256'], 'single unit differs from compiled proposal'
        units.append({'file': path, 'class': 'ModuleScript' if path.endswith('.ModuleScript.lua') else 'LocalScript',
                      'candidateIds': [row['candidate'] for row in members], 'beforeSha256': SHA(before),
                      'candidateSha256': SHA(body), 'beforePath': members[0]['beforePath'],
                      'candidatePath': str(target.relative_to(ROOT)), 'removedBytes': len(before)-len(body),
                      'sourceRegions': [{'beforeFirstLine':a+1,'beforeLastLine':b,'replacementLines':len(c)} for a,b,c in ordered],
                      'compiler': compile_ports,
                      'status': 'afventer final proposal contracts', 'productionApplied': False})
    result = {'productionWrites': False, 'studioCalls': False, 'compiler': args.compiler, 'proposals': proposals, 'installUnits': units,
              'overlap': 'C04/C07 LobbyLoading are composed as one verified install unit, preserving both edits against their same baseline; never replace one single-purpose candidate with the other',
              'excluded': 'Preexisting dirty RoundUI is untouched and not a proposal target'}
    (OUT / 'remaining-clients-proposals.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf8')
    print(json.dumps([{'candidate': row['candidate'], 'file': row['file'], 'removedBytes': row['removedBytes'], 'compiler': row['compiler']} for row in proposals]))


if __name__ == '__main__':
    main()
