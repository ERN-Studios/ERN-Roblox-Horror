"""Pure plan/manifest checks only; no Git writes or Studio calls."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('lazy_stage',Path(__file__).with_name('stage_task.py'))
s=importlib.util.module_from_spec(spec); spec.loader.exec_module(s)

def row(native,kind,operation='modify'):
 value={'studioPath':native,'className':kind,'file':s.mirror(native,kind),'operation':operation}
 if operation=='move': value.update(beforeStudioPath=native.replace('ServerStorage.','Workspace.',1),beforeFile=value['file'].replace('ServerStorage/','Workspace/',1))
 return value

def entry(value,old=False):
 return {'file':value.get('beforeFile',value['file']) if old else value['file'],'studioPath':value.get('beforeStudioPath',value['studioPath']) if old else value['studioPath'],'className':value['className'],'sha256':'new' if not old else 'old'}

class Helpers(unittest.TestCase):
 def fixture(self):
  sources=[row('ServerScriptService.Level4RoundGenerator','ModuleScript'),row('ServerScriptService.LevelWorldStorage','ModuleScript','add'),row('ServerStorage.Level 4 Cinema Blender.Doors.PushDoors','Script','move')]
  selection=s.scope({'sources':sources,'artifacts':['artifacts/lazy-levels-20261009/native_scene.luau']})
  unrelated={'file':'StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua','studioPath':'RoundUI','sha256':'concurrent','status':'dirty'}
  base={'header':'preserve','items':[entry(sources[0],True),copy.deepcopy(unrelated),entry(sources[2],True)]}
  replacements={v['file']:entry(v) for v in sources}
  return selection,base,replacements,unrelated
 def test_head_manifest_replaces_only_selected_and_adds_module(self):
  selection,base,replacements,unrelated=self.fixture()
  result=s.replace_rows(base,replacements,selection)
  self.assertEqual(result['items'][1],unrelated); self.assertEqual(result['header'],'preserve')
  self.assertEqual(s.task_rows(result,selection),replacements); self.assertEqual(len(result['items']),4)
  self.assertEqual(base['items'][0]['sha256'],'old')
 def test_real_index_manifest_can_preserve_staged_rows_and_already_moved_entries(self):
  selection,base,replacements,unrelated=self.fixture()
  indexed=s.replace_rows(base,replacements,selection); indexed['items'][1]['extra']='staged'
  result=s.replace_rows(indexed,replacements,selection,True)
  self.assertEqual(result['items'][1],indexed['items'][1]); self.assertEqual(s.task_rows(result,selection),replacements)
 def test_duplicate_move_destination_blocks(self):
  selection,base,replacements,_=self.fixture(); base['items'].append(entry(selection['sources'][2]))
  with self.assertRaisesRegex(RuntimeError,'ambiguous'): s.replace_rows(base,replacements,selection)
 def test_scope_rejects_unrelated_roundui_private_snapshots_and_wrong_before_path(self):
  with self.assertRaisesRegex(RuntimeError,'allowlist'): s.scope({'sources':[row('StarterPlayer.StarterPlayerScripts.RoundUI','LocalScript')],'artifacts':[]})
  selection,_,_,_=self.fixture(); selection['artifacts']=['artifacts/lazy-levels-20261009/candidate-source.luau']
  with self.assertRaisesRegex(RuntimeError,'snapshots'): s.scope(selection)
  selection,_,_,_=self.fixture(); selection['sources'][2]['beforeFile']='Workspace/other.Script.lua'
  with self.assertRaisesRegex(RuntimeError,'relocation'): s.scope(selection)
 def test_scope_allows_exact_qa_harnesses_and_existing_native_helpers(self):
  names=['level4_lifecycle_harness.luau','level4_native_qa.luau','round_entry_batch_harness.luau','native_scene.luau','probe_native_contract.luau']
  selection,_,_,_=self.fixture(); selection['artifacts']=[s.TASK+'/'+name for name in names]
  self.assertEqual(s.scope(selection)['artifacts'],selection['artifacts'])
 def test_qa_allowlist_rejects_lookalikes_and_private_probe_snapshots(self):
  for name in ['level4_lifecycle_harness_extra.luau','level4_native_qa_extra.luau','round_entry_batch_harness_extra.luau','Level4_native_qa.luau']:
   with self.subTest(name=name):
    selection,_,_,_=self.fixture(); selection['artifacts']=[s.TASK+'/'+name]
    with self.assertRaisesRegex(RuntimeError,'explicit native'): s.scope(selection)
  for name in ['level4_native_qa_candidate.luau','round_entry_batch_harness_baseline.luau','probe_level4_candidate.luau','probe_level4_baseline.luau','probe_sources.json.luau','probe_credentials.luau']:
   with self.subTest(name=name):
    selection,_,_,_=self.fixture(); selection['artifacts']=[s.TASK+'/'+name]
    with self.assertRaisesRegex(RuntimeError,'snapshots'): s.scope(selection)
 def test_qa_allowlist_still_rejects_nested_artifact_paths(self):
  selection,_,_,_=self.fixture(); selection['artifacts']=[s.TASK+'/private/level4_native_qa.luau']
  with self.assertRaisesRegex(RuntimeError,'artifact path'): s.scope(selection)
 def test_deferred_audio_harness_is_exact_and_private_variants_stay_excluded(self):
  selection,_,_,_=self.fixture(); selection['artifacts']=[s.TASK+'/level6_deferred_audio_harness.luau']
  self.assertEqual(s.scope(selection)['artifacts'],selection['artifacts'])
  for name in ['level6_deferred_audio_harness_extra.luau','Level6_deferred_audio_harness.luau','level6_deferred_audio.luau']:
   with self.subTest(name=name):
    selection['artifacts']=[s.TASK+'/'+name]
    with self.assertRaisesRegex(RuntimeError,'explicit native'): s.scope(selection)
  for name in ['level6_deferred_audio_harness_candidate.luau','level6_deferred_audio_harness_baseline.luau']:
   with self.subTest(name=name):
    selection['artifacts']=[s.TASK+'/'+name]
    with self.assertRaisesRegex(RuntimeError,'snapshots'): s.scope(selection)
  selection['artifacts']=[s.TASK+'/candidates/level6_deferred_audio_harness.luau']
  with self.assertRaisesRegex(RuntimeError,'artifact path'): s.scope(selection)
 def test_deletions_are_explicit_index_updates(self):
  with patch.object(s.b,'update_entries') as update:
   s.apply_entries(Path('root'),Path('alternate'),{'old.lua':None,'new.lua':['100644','a'*40]})
   self.assertEqual(update.call_args.args[2]['old.lua'],['0','0'*40])
 def test_branch_guard_precedes_any_commit_write(self):
  selection,_,_,_=self.fixture()
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp).resolve(); scope_file=root/'scope.json'; scope_file.write_bytes(s.encode(selection))
   plan={'format':1,'task':'lazy-levels-20261009','root':str(root),'scope':selection,'paths':s.paths_of(selection),'scopeFile':str(scope_file),'scopeSHA256':s.sha(scope_file.read_bytes()),'headRef':'refs/heads/main'}
   path=root/'plan.json'; path.write_bytes(s.encode(plan))
   with patch.object(s.b,'require_head_ref',side_effect=RuntimeError('HEAD branch changed')),patch.object(s,'git') as git:
    with self.assertRaisesRegex(RuntimeError,'branch changed'): s.commit(root,path,s.sha(path.read_bytes()),root/'message')
    git.assert_not_called()

if __name__=='__main__': unittest.main()
