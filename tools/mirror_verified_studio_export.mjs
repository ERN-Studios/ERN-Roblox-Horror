// One-way mechanical mirror. This tool has no Studio connection or write API.
// Input must be a fresh, Source/editor-verified export captured from Studio.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const input = process.argv[2];
const apply = process.argv.includes('--apply');
if (!input) throw new Error('Usage: node tools/mirror_verified_studio_export.mjs verified-export.json [--apply]');
const data = JSON.parse(fs.readFileSync(input, 'utf8'));
if (data.place !== 131311258779917 || data.universe !== 10559217407) throw new Error('Wrong experience');
const services = new Set(['Workspace','ReplicatedStorage','ReplicatedFirst','ServerScriptService','ServerStorage','StarterPlayer','StarterGui','StarterPack','SoundService','Lighting','Teams','MaterialService','TextChatService']);
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const hash = bytes => { let h = 5381; for (const b of bytes) h = (h * 33 + b) % 4294967296; return h; };
const files = new Map();
for (const s of data.scripts) {
  if (!s.editorRead || !s.editorMatch) throw new Error('Unresolved Studio editor source');
  if (!services.has(s.segments[0])) throw new Error('Unexpected service: '+s.segments[0]);
  if (s.segments.some(x => !x || x === '.' || x === '..' || /[/\\\x00]/.test(x))) throw new Error('Unsafe path');
  if (!['Script','LocalScript','ModuleScript'].includes(s.class)) throw new Error('Unexpected script class');
  const bytes = Buffer.from(s.source, 'utf8');
  if (bytes.length !== s.bytes || hash(bytes) !== s.hash) throw new Error('Export integrity failure: '+s.segments.join('/'));
  const rel = [...s.segments.slice(0,-1), s.segments.at(-1)+'.'+s.class+'.lua'].join('/');
  if (files.has(rel)) throw new Error('Duplicate Studio path: '+rel);
  files.set(rel, {...s, bytesBuffer:bytes});
}
const orphans = [];
function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const ent of fs.readdirSync(dir, {withFileTypes:true})) {
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(full);
    else if (ent.isFile() && /\.(?:LocalScript|ModuleScript|Script)\.lua$/.test(ent.name)) {
      const rel = path.relative(root,full).split(path.sep).join('/');
      if (!files.has(rel)) orphans.push(rel);
    }
  }
}
for (const s of services) walk(path.join(root,s));
const changed = [...files].filter(([rel,s]) => !fs.existsSync(path.join(root,rel)) || !fs.readFileSync(path.join(root,rel)).equals(s.bytesBuffer)).map(([rel])=>rel);
const report = {direction:'Studio to repository only',place:data.place,universe:data.universe,version:data.version,capturedUTC:data.capturedUTC,sourceExportSha256:sha(fs.readFileSync(input)),scriptCount:files.size,changed,orphanedMirrorFiles:orphans,wholePlaceBackup:false};
console.log(JSON.stringify(report,null,2));
if (!apply) process.exit(0);
// Orphaned mirror sources are preserved outside service folders, not deleted.
for (const rel of orphans) {
  const target = path.join(root,'studio-history','20260909-pre-sync',rel);
  if (fs.existsSync(target)) throw new Error('History target already exists: '+target);
  fs.mkdirSync(path.dirname(target),{recursive:true});
  fs.renameSync(path.join(root,rel),target);
}
for (const [rel,s] of files) {
  fs.mkdirSync(path.dirname(path.join(root,rel)),{recursive:true});
  fs.writeFileSync(path.join(root,rel),s.bytesBuffer);
}
const old = JSON.parse(execFileSync('git',['show','origin/main:studio-sync-manifest.json'],{cwd:root,encoding:'utf8'}));
const nonScripts = old.items.filter(x=>!['Script','LocalScript','ModuleScript'].includes(x.className)).map(x=>({...x,status:'not-reverified-this-export'}));
const scriptItems = [...files].map(([rel,s])=>({studioPath:s.segments.join('.'),segments:s.segments,className:s.class,file:rel,bytes:s.bytes,sha256:sha(s.bytesBuffer),status:'synced',sourceEqualsEditor:true,...(s.disabled===undefined?{}:{disabled:s.disabled,runContext:s.runContext})}));
const manifest = {formatVersion:2,source:'Read-only live Studio Source and editor source export; exact UTF-8 mirror; no repository-to-Studio writes',finalNewlineContract:'Exact Studio source bytes, including final newline. No canonicalization or transport newline exception.',studio:{name:'BACKROOMS: STAY QUIET [CO-OP HORROR]',id:'bc1cdeb3-1172-4e75-8223-dc61ec4773c6',placeId:data.place,universeId:data.universe,observedPlaceVersion:data.version,capturedUTC:data.capturedUTC},counts:{scripts:scriptItems.length,remoteEvents:nonScripts.filter(x=>x.className==='RemoteEvent').length,total:scriptItems.length+nonScripts.length,studioTrailingNewline:0},nonScriptDataVerified:false,wholePlaceBackup:false,extraMirroredFilesNotInStudio:orphans.map(x=>'studio-history/20260909-pre-sync/'+x),items:[...scriptItems,...nonScripts]};
fs.writeFileSync(path.join(root,'studio-sync-manifest.json'),JSON.stringify(manifest,null,2)+'\n');
fs.mkdirSync(path.join(root,'docs','studio-sync'),{recursive:true});
fs.writeFileSync(path.join(root,'docs','studio-sync','20260909-baseline-report.json'),JSON.stringify(report,null,2)+'\n');
for (const [rel,s] of files) if(!fs.readFileSync(path.join(root,rel)).equals(s.bytesBuffer)) throw new Error('Post-write parity failure '+rel);
console.log('Verified exact Studio source bytes for '+files.size+' scripts. No Studio mutations.');
