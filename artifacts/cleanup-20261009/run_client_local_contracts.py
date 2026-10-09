"""Execute actual before/candidate client authoring contracts, never production writes.

--existing NAME --phase before|candidate executes an existing meaningful suite
with proposed source supplied only to its reader. --authoring runs paired actual
construction/HELP/preview source against the owned fake engine. Reports to stdout.
"""
from pathlib import Path
import argparse
import hashlib
import importlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts/cleanup-20261009'
sys.path.insert(0, str(ROOT / 'tools/tests'))
PORTABLE_ONLY = False


def proof_path(row, phase):
    """Resolve immutable proof input, with a portable path when .git is absent."""
    keys = [f'{phase}PortablePath'] if PORTABLE_ONLY else [
        f'{phase}Path', f'{phase}PortablePath', f'{phase}CheckpointPath',
    ]
    for key in keys:
        if not row.get(key):
            continue
        path = ROOT / row[key]
        if not path.is_file():
            continue
        raw = path.read_bytes()
        assert hashlib.sha256(raw.replace(b'\r\n', b'\n')).hexdigest() == row[f'{phase}Sha256'], 'immutable saved proof input changed: ' + str(path)
        if row.get(f'{phase}ByteSha256'):
            assert hashlib.sha256(raw).hexdigest() == row[f'{phase}ByteSha256'], 'proof input byte encoding changed: ' + str(path)
        return path
    raise FileNotFoundError('No immutable proof input for ' + row['file'] + ' ' + phase)


def proposal_rows():
    return json.loads((OUT / 'remaining-clients-proposals.json').read_text(encoding='utf8'))['proposals']


def install_units():
    return json.loads((OUT / 'remaining-clients-proposals.json').read_text(encoding='utf8'))['installUnits']


def authoring_program(rows, mutant=None):
    import test_round_hud as hud
    table = {}
    mapping = {
        ('C04', 'Animate.LocalScript.lua'): 'Animate',
        ('C06', 'First Entry Guide.LocalScript.lua'): 'Guide',
        ('C06', 'Level4PreviewPrompt.LocalScript.lua'): 'Preview',
        ('C07', 'Lobby Loading Screen.LocalScript.lua'): 'Loading',
        ('C07', 'ZyntraStore.LocalScript.lua'): 'Store',
    }
    for row in rows:
        name = mapping.get((row['candidate'], Path(row['file']).name))
        if not name:
            continue
        for phase in ['before', 'candidate']:
            unit = next(item for item in install_units() if item['file'] == row['file'])
            source = proof_path(unit, phase).read_text(encoding='utf8')
            if phase == 'candidate' and mutant:
                import re
                if name == 'Loading' and mutant == 'drop-loading-label':
                    source = re.sub(r'^label\("Kicker".*\n', '', source, count=1, flags=re.M)
                elif name == 'Store' and mutant == 'drop-shop-outline':
                    source = source.replace('outline(shopButton, COLORS.accent, 0.22, 1.5)\n', '', 1)
                elif name == 'Preview' and mutant == 'hide-public-level6':
                    source = source.replace('local PROMPTS = {', 'local PROMPTS = {Level6DeveloperPreviewPrompt=true,', 1)
                elif name == 'Guide' and mutant == 'change-controls-copy':
                    source = source.replace('WASD to move, mouse to look, Space to jump.', 'CONTROLS REGRESSED', 1)
            if name == 'Loading':
                source = source[:source.index('local recovery =')] + '\nreturn gui\n'
            elif name == 'Store':
                source = 'local player=game:GetService("Players").LocalPlayer\n' + source[source.index('local COLORS ='):source.index('local TOUCH_MIN_TAP_HEIGHT')] + '\nreturn gui\n'
            table[name + phase] = source
    table['ZyntraConfig'] = (ROOT / 'ReplicatedStorage/ZyntraConfig.ModuleScript.lua').read_text(encoding='utf8')
    inject = 'local SOURCES = {\n' + ',\n'.join(f'{key}={hud.long_string(value)}' for key, value in table.items()) + '\n}\nlocal TREES = {}\n'
    harness = hud.HARNESS.read_text(encoding='utf8').replace('--@@INJECT@@', inject, 1)
    harness = harness.replace('local game = {GetService', 'ctx.Services=services\n\tlocal game = {GetService', 1)
    return harness + r'''
-- These are engine-boundary additions for these authoring scripts, not changes
-- to the production fake engine or replicas of gameplay decisions.
local create=Instance.new
Instance.new=function(class,parent) local object=create(class);object.Parent=parent;return object end
function methods:ClearAllChildren() for _,child in self:GetChildren() do child:Destroy() end end
local function snapshot(root)
 local rows={}
 local function visit(node,path)
  local fields={path,node.ClassName}
  for _,key in {"Text","TextSize","Font","TextWrapped","TextScaled","Position","Size","BackgroundTransparency","Color","Thickness","Transparency","Visible","Active"} do
   if node[key]~=nil then fields[#fields+1]=key.."="..tostring(node[key]) end
  end
  rows[#rows+1]=table.concat(fields,"|")
  for _,child in node:GetChildren() do visit(child,path.."/"..child.Name) end
 end
 visit(root,root.Name);table.sort(rows);return table.concat(rows,"\n")
end
local function boot(touch)
 local ctx=context({touch=touch,viewport=touch and Vector2.new(568,320) or Vector2.new(1920,1080)})
 -- The original HUD fixture has a no-op wait. These scripts own yielding
 -- lobby workers, so model a bounded manual-clock coroutine scheduler here.
 ctx.Task.wait=function(seconds) return coroutine.yield(seconds or .05) end
 ctx.Task.spawn=function(fn,...)
  local args=table.pack(...);local thread=coroutine.create(function() fn(table.unpack(args,1,args.n)) end)
  local function resume()
   local ok,delay=coroutine.resume(thread);assert(ok,delay)
   if coroutine.status(thread)~="dead" then ctx.Task.delay(delay or .05,resume) end
  end
  resume()
 end
 newInstance("PlayerScripts","PlayerScripts").Parent=ctx.Player
 ctx.Player.CharacterAdded=signal();ctx.UIS.InputBegan=signal();ctx.UIS.InputEnded=signal()
 ctx.UIS.TouchEnabled,ctx.UIS.KeyboardEnabled=touch,not touch
 ctx.Player:SetAttribute("LobbyLoadingDone",true);ctx.Player:SetAttribute("ZyntraFirstLogin",false)
 function ctx.UIDevice.Layout()
  return {IsTouch=ctx.Touch,Safe=ctx.Safe,Viewport=ctx.Viewport,
   ModalViewport={Left=80,Top=ctx.Safe.Top,Width=ctx.Safe.Width-80,Height=ctx.Safe.Height}}
 end
 function ctx.UIDevice.SuppressTouchMovement(value) ctx.Suppressed=value end
 function ctx.UIDevice.ScreenOwningModalOpen()
  for _,flag in {"HelpPanelOpen","WelcomeCardOpen","ZyntraStoreOpen","QueueModalOpen","LuckyWheelOpen"} do
   if ctx.Player:GetAttribute(flag)==true then return true end
  end return false
 end
 for _,name in {"ReplicatedFirst","ContentProvider","TeleportService","MaterialService"} do ctx.Services[name]={} end
 return ctx
end

-- Actual loading cover constructors: binding-only changes must retain both
-- labels and the entire tree/properties, on both authoring device contexts.
for _,touch in {false,true} do
 local original,candidate
 for _,phase in {"before","candidate"} do
  local ctx=boot(touch);local gui=ctx:Require("Loading"..phase)
  local cover=gui:FindFirstChild("Cover")
  check(cover~=nil and cover.Active,"loading cover still swallows clicks")
  local kicker,tip=cover:FindFirstChild("Kicker"),cover:FindFirstChild("Tip")
  check(kicker~=nil and kicker.Text=="ZYNTRA  //  FACILITY LINK","loading Kicker was constructed/parented")
  check(tip~=nil and tip.Text=="Noise attracts it. Walk. Crouch. Stay quiet.","loading Tip was constructed/parented")
  check(kicker.TextWrapped and tip.TextWrapped and kicker.TextSize==14 and tip.TextSize==14,"loading authored text properties")
  check(tip.Position.Y.Scale==1 and tip.Position.Y.Offset==-40,"loading Tip retains bottom placement")
  if phase=="before" then original=snapshot(gui) else candidate=snapshot(gui) end
 end
 check(original==candidate,"whole loading authoring subtree unchanged, touch="..tostring(touch))
end

-- Actual rail construction block, including the outline helper and call.
for _,touch in {false,true} do
 local original,candidate
 for _,phase in {"before","candidate"} do
  local ctx=boot(touch);local gui=ctx:Require("Store"..phase)
  local shop=gui:FindFirstChild("ZyntraShopButton")
  check(shop~=nil,"shop button still constructed")
  local stroke=nil
  for _,child in shop:GetChildren() do
   if child:IsA("UIStroke") and child.Name~="SquareSectionBorder" and child.Color==Color3.fromRGB(68,221,196) then stroke=child end
  end
  check(stroke~=nil and stroke.Parent==shop,"shop outline still constructed/parented")
  check(stroke.Color==Color3.fromRGB(68,221,196) and stroke.Transparency==.22 and stroke.Thickness==1.5,"shop outline authored properties: "..tostring(stroke.Color).."/"..tostring(stroke.Transparency).."/"..tostring(stroke.Thickness))
  check(shop:FindFirstChild("SectionButtonContent"):FindFirstChild("SectionCaption").Text=="Shops","shop caption retained")
  local count=0;for _,child in shop:GetChildren() do if child:IsA("UIStroke") then count+=1 end end
  check(count==3,"all three authored strokes retained: button base, accent outline, rail hover border")
  if phase=="before" then original=snapshot(gui) else candidate=snapshot(gui) end
 end
 check(original==candidate,"whole rail authoring subtree unchanged, touch="..tostring(touch))
end

-- Entire preview script, including initial enumeration and native-style
-- Enabled watcher behavior. Streamed prompts are delivered through its actual
-- DescendantAdded callback. Test allowlist failures and all identity branches.
for _,mode in {"ordinary","special","dev","special-dev","missing","error","truthy"} do
 local original,candidate
 for _,phase in {"before","candidate"} do
  local ctx=boot(false);ctx.Player.UserId=mode:find("special") and 11374988579 or 7
  local storage=newInstance("Folder","ReplicatedStorage")
  if mode~="missing" then newInstance("ModuleScript","DevAccess").Parent=storage end
  local entries={}
  for _,name in {"Level4DeveloperPreviewPrompt","Level4DeveloperPreviewReturnPrompt","Level5DeveloperPreviewPrompt","Level6DeveloperPreviewPrompt","Level6DeveloperPreviewReturnPrompt"} do
   local item=newInstance("ProximityPrompt",name);item.Enabled=true;item.Parent=ctx.Workspace;entries[name]=item
  end
  local notPrompt=newInstance("Folder","Level4DeveloperPreviewPrompt");notPrompt.Enabled=true;notPrompt.Parent=ctx.Workspace
  local allowed=mode=="dev" or mode=="special-dev"
  local fn=assert(loadstring(SOURCES["Preview"..phase]))
  setfenv(fn,setmetatable({workspace=ctx.Workspace,game={GetService=function(_,name)
   return name=="Players" and {LocalPlayer=ctx.Player} or storage end},require=function()
   if mode=="error" then error("allowlist unavailable") end
   return {IsAllowed=function() return allowed or (mode=="truthy" and "yes" or false) end}
  end},{__index=getfenv()}));fn()
  check(entries.Level4DeveloperPreviewPrompt.Enabled==allowed,"L4 initial access contract "..mode)
  check(entries.Level4DeveloperPreviewReturnPrompt.Enabled==allowed,"L4 initial return contract "..mode)
  check(entries.Level5DeveloperPreviewPrompt.Enabled and entries.Level6DeveloperPreviewPrompt.Enabled and entries.Level6DeveloperPreviewReturnPrompt.Enabled,"public L5/L6 prompts remain available "..mode)
  check(notPrompt.Enabled,"nonprompt namesake retained "..mode)
  entries.Level4DeveloperPreviewPrompt.Enabled=true
  check(entries.Level4DeveloperPreviewPrompt.Enabled==allowed,"L4 re-enable fail-closed watcher "..mode)
  local late=newInstance("ProximityPrompt","Level4DeveloperPreviewPrompt");late.Enabled=true;late.Parent=ctx.Workspace
  ctx.Workspace.DescendantAdded:Fire(late)
  check(late.Enabled==allowed,"streamed L4 prompt policy "..mode)
  late.Enabled=true;check(late.Enabled==allowed,"streamed L4 re-enable policy "..mode)
  local values={tostring(late.Enabled),tostring(notPrompt.Enabled)}
  for name,item in entries do values[#values+1]=name.."="..tostring(item.Enabled) end
  table.sort(values)
  if phase=="before" then original=table.concat(values,"|") else candidate=table.concat(values,"|") end
 end
 check(original==candidate,"whole preview outcome before/after "..mode)
end

-- Entire current guide script, actual HELP topic renderer and tutorial replay.
-- Fakes model service boundaries; they make no native geometry/font claims.
for _,touch in {false,true} do
 local original,candidate
 for _,phase in {"before","candidate"} do
  local ctx=boot(touch);ctx:Require("Guide"..phase)
  local opener=ctx.PlayerGui:FindFirstChild("HelpButton")
  check(opener~=nil,"current HELP opener built")
  opener:SetAttribute("Toggle",1)
  local gui=ctx.PlayerGui:FindFirstChild("HelpPanel")
  check(gui~=nil and ctx.Player:GetAttribute("HelpPanelOpen")==true,"actual HELP flow opened")
  local panel=gui:FindFirstChild("Panel",true);local topics=panel:FindFirstChild("Topics")
  local rows={}
  for index=1,10 do
   check(topics:FindFirstChild("Topic"..index)~=nil,"all ten current HELP topics")
   gui:SetAttribute("Topic",index);rows[#rows+1]=snapshot(panel:FindFirstChild("Content"))
  end
  gui:SetAttribute("Topic",2)
  local controls=snapshot(panel:FindFirstChild("Content"))
  check(controls:find(touch and "Left stick to move" or "WASD to move",1,true)~=nil,"current controls copy follows device")
  panel:FindFirstChild("Tutorial").Activated:Fire()
  check(ctx.Player:GetAttribute("HelpPanelOpen")==nil and gui.Parent==nil,"HELP closes/cleans before tutorial replay")
  local welcome=ctx.PlayerGui:FindFirstChild("WelcomeCard")
  check(welcome~=nil and ctx.Player:GetAttribute("WelcomeCardOpen")==true,"actual tutorial replay opened")
  for index=1,4 do welcome:SetAttribute("Page",index);rows[#rows+1]=snapshot(welcome:FindFirstChild("Card",true)) end
  welcome:FindFirstChild("Skip",true).Activated:Fire()
  check(welcome.Parent==nil and ctx.Player:GetAttribute("WelcomeCardOpen")==nil,"tutorial skip cleans flags/tree")
  opener:SetAttribute("Toggle",2);gui=ctx.PlayerGui:FindFirstChild("HelpPanel")
  check(gui~=nil,"HELP reentry after tutorial")
  ctx.Player:SetAttribute("ZyntraStoreOpen",true)
  check(gui.Parent==nil and ctx.Player:GetAttribute("HelpPanelOpen")==nil,"other screen-owning modal closes HELP")
  ctx.Player:SetAttribute("ZyntraStoreOpen",nil)
  if phase=="before" then original=table.concat(rows,"\n") else candidate=table.concat(rows,"\n") end
 end
 check(original==candidate,"actual ten-topic HELP and four-page replay before/after, touch="..tostring(touch))
end

-- Actual animation selection and step functions. Only engine collaborators
-- and the random draw are faked; both complete function bodies are extracted.
local function animation(phase)
 local source=SOURCES["Animate"..phase]
 local start=assert(source:find("function rollAnimation(animName)",1,true))
 local finish=assert(source:find("local function switchToAnim",start,true))
 local roll=source:sub(start,finish-1)
 start=assert(source:find("local lastTick = 0",1,true));finish=assert(source:find("-- connect events",start,true))
 local step=source:sub(start,finish-1)
 local env=setmetatable({animTable={walk={totalWeight=10,{weight=1},{weight=3},{weight=6}}},Roll=1,Draws=0,Events={},
  jumpAnimTime=0,pose="Standing",fallTransitionTime=.3,Humanoid={},toolAnim="None",toolAnimTime=0}, {__index=getfenv()})
 local fakeMath=table.clone(math)
 fakeMath.random=function(min,max) check(min==1 and max==10,"actual weighted selection asks valid draw");env.Draws+=1;return env.Roll end
 env.math=fakeMath
 env.playAnimation=function(name,time) env.Events[#env.Events+1]="play:"..name..":"..time end
 env.stopAllAnimations=function() env.Events[#env.Events+1]="stop-all" end
 env.stopToolAnimations=function() env.Events[#env.Events+1]="stop-tool" end
 env.animateTool=function() env.Events[#env.Events+1]="tool:"..env.toolAnim end
 env.getToolAnim=function(tool) return tool.Note end
 env.Character={FindFirstChildOfClass=function(_,kind) check(kind=="Tool","actual tool lookup");return env.Tool end}
 local fn=assert(loadstring(roll.."\n"..step.."\nreturn rollAnimation,stepAnimate"));setfenv(fn,env)
 local choose,tick=fn();return env,choose,tick
end
for _,phase in {"before","candidate"} do
 local env,choose,tick=animation(phase)
 for draw=1,10 do env.Roll=draw;local expected=draw==1 and 1 or (draw<=4 and 2 or 3)
  check(choose("walk")==expected,"weighted animation boundaries preserved") end
 check(env.Draws==10,"one random draw per animation selection")
 env.pose="FreeFall";tick(1);check(env.Events[1]=="play:fall:0.3","freefall animation branch")
 env.Events={};env.pose="Seated";tick(2);check(#env.Events==1 and env.Events[1]=="play:sit:0.5","seated returns before tool handling")
 env.Events={};env.pose="Running";tick(3);check(env.Events[1]=="play:walk:0.2" and env.Events[2]=="stop-tool","running and no-tool cleanup")
 env.Events={};env.pose="Dead";tick(4);check(env.Events[1]=="stop-all" and env.Events[2]=="stop-tool","dead animation/tool cleanup")
 env.Events={};env.pose="Standing";env.jumpAnimTime=.3
 env.Tool={Note={Value="Slash",Parent={}},FindFirstChild=function(_,name) return name=="Handle" and {} or nil end}
 tick(4.1);check(env.jumpAnimTime>0 and env.Tool.Note.Parent==nil and env.toolAnim=="Slash" and env.Events[1]=="tool:Slash","actual tool message/parent cleanup and clock")
 env.Tool.Note=nil;env.Events={};tick(4.5)
 check(env.toolAnim=="None" and env.toolAnimTime==0 and env.Events[1]=="tool:None","tool expiry reset")
end
print("Client local authoring: "..checks.." checks passed (actual source, paired tree/copy/access/lifecycle contracts; offline engine boundaries)")
'''


def main():
    global PORTABLE_ONLY
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--existing', choices=['test_round_hud','test_round_hud_shared','test_hud_b6_b7','test_ui_regression_shared','test_zyntra_store_compact','test_first_entry_guide'])
    parser.add_argument('--phase', choices=['before','candidate'], default='before')
    parser.add_argument('--authoring', action='store_true')
    parser.add_argument('--mutant', choices=['drop-loading-label','drop-shop-outline','hide-public-level6','change-controls-copy'])
    parser.add_argument('--verify-installed', action='store_true', help='Require exact installed candidate hashes, rerun immutable saved probes and write a separate receipt')
    parser.add_argument('--portable-only', action='store_true', help='Use only portable proof inputs; no .git checkpoint reads')
    args = parser.parse_args()
    PORTABLE_ONLY = args.portable_only
    rows = proposal_rows()
    if args.verify_installed:
        units = install_units()
        manifest = json.loads((OUT / 'remaining-clients-proposals.json').read_text(encoding='utf8'))
        def verify():
            for row in rows:
                for phase in ['before','candidate']:
                    raw=proof_path(row, phase).read_bytes().replace(b'\r\n',b'\n')
                    assert hashlib.sha256(raw).hexdigest()==row[f'{phase}Sha256'], 'immutable individual proposal proof input changed: '+row['file']
            for unit in units:
                for phase in ['before','candidate']:
                    raw = proof_path(unit, phase).read_bytes().replace(b'\r\n',b'\n')
                    assert hashlib.sha256(raw).hexdigest() == unit[f'{phase}Sha256'], 'immutable saved proof input changed: '+unit['file']
                raw = (ROOT / unit['file']).read_bytes().replace(b'\r\n',b'\n')
                assert hashlib.sha256(raw).hexdigest() == unit['candidateSha256'], 'installed source differs from exact reviewed candidate: '+unit['file']
        verify()
        commands = [['--authoring']]
        for suite in ['test_round_hud','test_round_hud_shared','test_hud_b6_b7','test_ui_regression_shared','test_zyntra_store_compact','test_first_entry_guide']:
            for phase in ['before','candidate']: commands.append(['--existing',suite,'--phase',phase])
        results = []
        for command in commands:
            if PORTABLE_ONLY:
                command = [*command, '--portable-only']
            run = subprocess.run([sys.executable,str(Path(__file__)),*command],capture_output=True,text=True,timeout=180)
            results.append({'args':command,'exitCode':run.returncode,'stdout':run.stdout,'stderr':run.stderr})
            if run.returncode: break
        verify()
        compiler = manifest['compiler']
        compile_rows = []
        for unit in units:
            for optimization in [0,1]:
                result = subprocess.run([compiler,'--null','-g0',f'-O{optimization}',str(ROOT/unit['file'])],capture_output=True,text=True,timeout=30)
                compile_rows.append({'file':unit['file'],'optimization':optimization,'exitCode':result.returncode,'stdout':result.stdout,'stderr':result.stderr})
        verify()
        # Re-run the exact compiled-structure proof for comment-only C26 too.
        spec=importlib.util.spec_from_file_location('c08_verifier',OUT/'verify_C08.py')
        verifier=importlib.util.module_from_spec(spec);spec.loader.exec_module(verifier)
        c26=next(unit for unit in units if 'C26' in unit['candidateIds'])
        bytecode=[]
        for optimization in [0,1]:
            outputs={};dumps={}
            for phase,path in [('before',proof_path(c26, 'before')),('installed',ROOT/c26['file'])]:
                options=['-g0',f'-O{optimization}',str(path)]
                compiled=subprocess.run([compiler,'--binary',*options],capture_output=True,check=True,timeout=30).stdout
                outputs[phase],metadata=verifier.canonical(compiled)
                dumps[phase]=subprocess.run([compiler,'--text','--dump-constants',*options],capture_output=True,check=True,timeout=30).stdout
            assert outputs['before']==outputs['installed'] and dumps['before']==dumps['installed'], 'C26 installed compiled behavior differs'
            bytecode.append({'optimization':optimization,'functions':len(metadata),'canonicalBinaryIdentical':True,'instructionConstantDumpIdentical':True,'canonicalSha256':hashlib.sha256(outputs['installed']).hexdigest()})
        verify()
        receipt = {'mode':'verify-installed','portableOnly':PORTABLE_ONLY,'immutableProofInputsUnchanged':True,'currentCanonicalHashesMatchSavedCandidates':True,'productionWrites':False,'studioCalls':False,
                   'gates':results,'compile':compile_rows,'C26Bytecode':bytecode,'sourceHashes':{unit['file']:unit['candidateSha256'] for unit in units}}
        (OUT/'client-locals-installed-gates.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf8')
        print(json.dumps(receipt))
        raise SystemExit(1 if any(row['exitCode'] for row in results+compile_rows) else 0)
    if args.authoring:
        program = authoring_program(rows, args.mutant)
        with tempfile.TemporaryDirectory(prefix='client-authoring-') as temp:
            path = Path(temp) / 'authoring.luau'
            path.write_text(program, encoding='utf8')
            result = subprocess.run([os.environ['LUAU_BIN'], str(path)], capture_output=True, text=True, timeout=120)
        print(result.stdout + result.stderr)
        raise SystemExit(result.returncode)
    assert args.existing
    # Supply the exact proposed input to the existing source readers. Its own
    # engine boundary, assertions and production section extraction stay intact.
    values = {str((ROOT/row['file']).resolve()): proof_path(row, args.phase) for row in install_units()}
    original_read = Path.read_text
    def read(path, *pos, **kwargs):
        target = values.get(str(path.resolve()))
        return original_read(target or path, *pos, **kwargs)
    Path.read_text = read
    import test_round_hud as hud
    if args.phase == 'candidate':
        hud.SOURCES['RoundHud'] = values[str((ROOT/'ReplicatedStorage/RoundHud.ModuleScript.lua').resolve())]
    module = importlib.import_module(args.existing)
    if args.existing == 'test_ui_regression_shared':
        module.REGRESSION = values[str((ROOT/'ReplicatedStorage/UIRegression.ModuleScript.lua').resolve())]
    if args.existing == 'test_first_entry_guide':
        module.SOURCE = values[str((ROOT/'StarterPlayer/StarterPlayerScripts/First Entry Guide.LocalScript.lua').resolve())]
    module.main()


if __name__ == '__main__':
    main()
