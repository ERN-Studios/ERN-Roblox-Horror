"""Offline native move helper checks. No Studio or repository mutation."""
import importlib.util
import ast
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('native_move',Path(__file__).with_name('native_move.py'))
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

class Helpers(unittest.TestCase):
 def fixture(self,root):
  items=[]; sources=[]
  for old,rel in m.EMBEDDED.items():
   source='-- verified '+old+'\n'; raw=source.encode(); file=root/rel
   file.parent.mkdir(parents=True,exist_ok=True); file.write_bytes(raw)
   row={'studioPath':old,'file':rel,'className':'Script','sha256':m.sha(raw),'bytes':len(raw),'segments':old.split('.'),'status':'synced','sourceEditorMatches':True,'properties':{'Disabled':False}}
   items.append(row)
   sources.append({'path':old.replace('Workspace.','ServerStorage.',1),'class':'Script','sha256':m.sha(raw),'bytes':len(raw),'source':source,'sourceEditorMatches':True})
  unrelated={'file':'RoundUI.lua','studioPath':'RoundUI','sha256':'concurrent','other':['retain']}
  items.insert(1,unrelated)
  manifest={'version':7,'items':items,'unrelatedTop':'retain'}
  (root/'studio-sync-manifest.json').write_bytes(m.encoded(manifest))
  return {'sources':sources},manifest
 def test_export_only_two_entries_and_preserves_unrelated(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp); receipt,before=self.fixture(root)
   result=m.export_sources(root,receipt,root/'private-export')
   after=json.loads((root/'studio-sync-manifest.json').read_bytes())
   self.assertEqual(after['items'][1],before['items'][1]); self.assertEqual(after['unrelatedTop'],'retain')
   self.assertTrue(result['exported'])
   for old,rel in m.EMBEDDED.items():
    self.assertFalse((root/rel).exists()); self.assertTrue((root/rel.replace('Workspace/','ServerStorage/',1)).is_file())
 def test_new_path_collision_never_overwrites_or_removes_old(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp); receipt,_=self.fixture(root)
   old=next(iter(m.EMBEDDED.values())); new=root/old.replace('Workspace/','ServerStorage/',1)
   new.parent.mkdir(parents=True); new.write_bytes(b'other developer')
   before=(root/'studio-sync-manifest.json').read_bytes()
   with self.assertRaisesRegex(RuntimeError,'collision'): m.export_sources(root,receipt,root/'private-export')
   self.assertEqual(new.read_bytes(),b'other developer'); self.assertTrue((root/old).exists())
   self.assertEqual((root/'studio-sync-manifest.json').read_bytes(),before)
 def test_source_disagreement_blocks_export(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp); receipt,_=self.fixture(root); receipt['sources'][0]['source']='changed'
   with self.assertRaisesRegex(RuntimeError,'Source data differs'): m.export_sources(root,receipt,root/'private-export')
   self.assertTrue(all((root/p).is_file() for p in m.EMBEDDED.values()))
 def test_concurrent_manifest_change_retains_old_mirrors(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp); receipt,_=self.fixture(root); original=Path.mkdir
   def mkdir(path,*args,**kwargs):
    result=original(path,*args,**kwargs)
    if path==root/'ServerStorage/Level 4 Cinema Blender/Doors':
     (root/'studio-sync-manifest.json').write_bytes(b'concurrent work')
    return result
   with patch.object(Path,'mkdir',mkdir):
    with self.assertRaisesRegex(RuntimeError,'Manifest changed'): m.export_sources(root,receipt,root/'private-export')
   self.assertEqual((root/'studio-sync-manifest.json').read_bytes(),b'concurrent work')
   self.assertTrue(all((root/p).is_file() for p in m.EMBEDDED.values()))
 def test_metadata_guards_include_empty_attributes_and_runcontext(self):
  code=m.metadata_guards([{'class':'Script','properties':{'Archivable':True,'LinkedSource':'','Disabled':False,'RunContext':'Enum.RunContext.Client'},'attributes':{}}])
  self.assertIn('count==0',code); self.assertIn('Enum.RunContext.Client',code); self.assertIn('tostring(s[',code)
  with self.assertRaisesRegex(RuntimeError,'Incomplete'): m.metadata_guards([{'class':'Script','properties':{},'attributes':{}}])
 def test_all_native_command_templates_compile_and_write_guard_is_bounded(self):
  compiler=Path(os.environ.get('TEMP',''))/'codex-luau-0.737/luau-compile.exe'
  if not compiler.is_file(): self.skipTest('Luau compiler is not installed')
  tree=ast.parse(Path(m.__file__).read_text()); common=m.common()
  critical=common.split('local function criticalGuard(c)',1)[1].split('local function guard(c)',1)[0]
  self.assertNotIn('task.wait',critical)
  values={'__KEY__':'"test"','__ID__':'"test"','__PINS__':'{}','__PIN_METADATA__':'','__URL__':'"http://127.0.0.1:1"','__NATIVE__':'"hash"','__TREE__':'"hash"','__SOURCES__':''}
  with tempfile.TemporaryDirectory() as tmp:
   for name in ['capture','planmove','verify']:
    function=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name==name)
    template=max((n.value for n in ast.walk(function) if isinstance(n,ast.Constant) and isinstance(n.value,str) and '\n' in n.value),key=len)
    for token,value in values.items(): template=template.replace(token,value)
    file=Path(tmp)/(name+'.luau'); file.write_text(common+template,encoding='utf-8')
    result=subprocess.run([str(compiler),str(file)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    self.assertEqual(result.returncode,0,result.stderr.decode())

if __name__=='__main__': unittest.main()
