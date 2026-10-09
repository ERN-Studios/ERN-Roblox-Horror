"""Exercise the real imported Level 4 card block against fixture-backed UI fakes.

This verifies interaction, focus links, rereading and remount state. Native pad
focus rendering, glyph loading and safe-area pixels still require Studio QA.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "StarterPlayer/StarterPlayerScripts/Level 4 Round Client.LocalScript.lua"


def template_tree():
    root = json.loads((ROOT / "tools/tests/fixtures/hud/framewisp-dump.HUD_Screens.json").read_text(encoding="utf-8-sig"))["root"]
    selected = {item["Name"]: item for item in root["Children"] if item["Name"] in {"Keypad", "Level4Note"}}
    assert set(selected) == {"Keypad", "Level4Note"}
    def quote(value):
        return json.dumps(value, ensure_ascii=True)
    def make(node, parent, output):
        name = node["Name"]
        output.append(f"do local n = node({quote(node['ClassName'])}, {quote(name)}, {parent})")
        if "Text" in node:
            output.append(f"n.Text = {quote(node['Text'])}")
        for child in node.get("Children", []):
            make(child, "n", output)
        output.append("end")
    output = []
    for name, data in selected.items():
        output.append(f"templates[{quote(name)}] = function(parent)")
        output.append(f"local root = node({quote(data['ClassName'])}, {quote(name)}, parent)")
        for child in data.get("Children", []):
            make(child, "root", output)
        output.append("return root end")
    # JSON Unicode escapes use \uXXXX, whereas Luau uses \u{XXXX}.
    import re
    return re.sub(r"\\u([0-9a-fA-F]{4})", r"\\u{\1}", "\n".join(output))


PRELUDE = r'''
local checks = 0
local function expect(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end
local function signal()
    local s = {Callbacks = {}}
    function s:Connect(fn) table.insert(self.Callbacks, fn); return {Disconnect = function() end} end
    function s:Once(fn) return self:Connect(fn) end
    function s:Fire(...) for _, fn in ipairs(self.Callbacks) do fn(...) end end
    return s
end
local function node(class, name, parent)
    local n = {ClassName = class, Name = name, Parent = parent, Children = {}, Visible = true,
        ZIndex = 1, AnchorPoint = {}, Position = {}, Size = {}, Destroying = signal(), Activated = signal(), Signals = {}}
    if parent then table.insert(parent.Children, n) end
    function n:GetPropertyChangedSignal(key)
        self.Signals[key] = self.Signals[key] or signal(); return self.Signals[key]
    end
    function n:IsDescendantOf(other)
        local at = self.Parent
        while at do if at == other then return true end; at = at.Parent end
        return false
    end
    function n:FindFirstChild(name)
        for _, child in ipairs(self.Children) do if child.Name == name then return child end end
    end
    function n:Destroy()
        self.Destroying:Fire()
        for i = #self.Children, 1, -1 do self.Children[i]:Destroy() end
        if self.Parent then
            for i, child in ipairs(self.Parent.Children) do if child == self then table.remove(self.Parent.Children, i); break end end
        end
        self.Parent = nil
    end
    return setmetatable(n, {__newindex = function(self,key,value)
        rawset(self,key,value)
        if key == 'Parent' and value then table.insert(value.Children,self) end
    end})
end
local Instance = {new = function(class) return node(class, class) end}
local Vector2 = {new = function(x,y) return {X=x,Y=y} end}
local UDim2 = {fromScale = function(x,y) return {X=x,Y=y} end, fromOffset = function(x,y) return {X=x,Y=y} end}
local enumKeys, nextValue = {}, 10
setmetatable(enumKeys, {__index = function(t,key) nextValue += 1; local v = {Value=nextValue,Name=key}; rawset(t,key,v); return v end})
local Enum = {KeyCode=enumKeys, Font={PatrickHand='PatrickHand'}, UserInputState={Begin='Begin'},
    ContextActionResult={Pass='Pass',Sink='Sink'}, ContextActionPriority={High={Value=100}}}
local gui = node('ScreenGui', 'Level4RoundGui'); gui.Enabled = true
local attrs = {InRound=true, Level4_NoteOrder='B1 > B3 > A2 > B2'}
local hum = {Health=100}
local player = {Character = {FindFirstChild = function() return {Position=42} end, FindFirstChildOfClass=function() return hum end}}
local Players = {GetPlayerByUserId=function() return nil end}
function player:GetAttribute(key) return attrs[key] end
function player:SetAttribute(key,value) attrs[key]=value end
local modal, touch, pad = false, false, true
local UIDevice = {Changed=signal()}
function UIDevice.IsTouch() return touch end
function UIDevice.IsGamepadOnly() return pad end
function UIDevice.LastInput() return pad and 'Gamepad' or 'Keyboard' end
function UIDevice.ScreenOwningModalOpen() return modal end
function UIDevice.Layout() return {IsTouch=touch,Safe={Left=0,Top=0,Right=1000,Bottom=800,Width=1000,Height=800},Zones={Controls={Left=1000}}} end
function UIDevice.LocalPosition(_,x,y) return {X=x,Y=y} end
local GuiService = {SelectedObject=nil,MenuIsOpen=false}
local UserInputService = {MouseEnabled=true,InputBegan=signal()}
function UserInputService:GetFocusedTextBox() return nil end
local game = {GetService=function() return {FindFirstChildOfClass=function() return nil end} end}
local ContextActionService = {Actions={}}
function ContextActionService:BindActionAtPriority(name,fn) self.Actions[name]=fn end
local Binder = {Palette={RailTeal='RailTeal'}}
function Binder.at(root,path)
    local at=root
    for part in string.gmatch(path,'[^/]+') do at=at and at:FindFirstChild(part) end
    return at
end
local templates = {}
local RoundHud = {Mounts=0}
function RoundHud.Mount(_,path,parent,opts)
    local root=templates[path](parent); root.Name=opts.Name; RoundHud.Mounts += 1; return root
end
function RoundHud.Keycap(chip,keyboard,gamepad) if chip then chip.Binding={keyboard,gamepad} end end
local sent = {}
local remote = {FireServer=function(_,text) table.insert(sent,text) end}
local ReplicatedStorage = {FindFirstChild=function() return {FindFirstChild=function() return remote end} end}
local REMOTES_NAME='Level 4 Remotes'
local AUDIO={Keypad=1}
local function playSound() end
local function say() end
local delayed = {}
local task = {delay=function(_,fn) table.insert(delayed,fn) end}
local function involved() return attrs.InRound == true end
local reopenNote
'''


TESTS = r'''
expect(#keypadKeys,12,'all imported keys bound')
for i,key in ipairs(keypadKeys) do
    local left,right,up,down=focusNeighbours(i)
    expect(key.NextSelectionLeft,keypadKeys[left],'left focus link')
    expect(key.NextSelectionRight,keypadKeys[right],'right focus link')
    expect(key.NextSelectionUp,keypadKeys[up],'up focus link')
    expect(key.NextSelectionDown,keypadKeys[down],'down focus link')
end
expect(keypadKeys[1].NextSelectionLeft,keypadKeys[3],'row wraps left')
expect(keypadKeys[1].NextSelectionUp,keypadKeys[10],'column wraps up')
openKeypad()
expect(GuiService.SelectedObject,keypadKeys[1],'pad gets first key focus')
press('1');press('2');press('3');press('4');press('5')
expect(entered,'1234','input caps at four digits')
expect(display.Text,'1234','real imported DisplayBox/Display filled')
press('OK')
expect(sent[1],'1234','exact code submitted')
handleKeypadResult({Ok=false})
expect(keypadStatus.Text,'WRONG CODE','actual wrong-code event copy')
expect(keypadStatus.Visible,true,'wrong-code status appears')
expect(entered,'','wrong-code response resets entry state')
delayed[1]()
expect(display.Text,'----','existing wrong-code timer resets display')
expect(keypadStatus.Visible,false,'wrong-code timer clears transient status')
press('C');press('OK')
expect(#sent,1,'incomplete code not submitted')
expect(display.Text,'----','clear resets display')
expect(ContextActionService.Actions.Level4CloseCard(nil,'Begin',{KeyCode=Enum.KeyCode.ButtonB}),'Sink','B closes keypad')
expect(keypad.Visible,false,'keypad closed')
expect(GuiService.SelectedObject,nil,'focus handed back')
openNote('POWER\nB1  >  B3  >  A2  >  B2\n\n- in this order -',true)
expect(noteCard.Visible,true,'note shown')
expect(Binder.at(noteCard,'Body/Items/BodyLine1').Text,'POWER','note line one')
expect(Binder.at(noteCard,'Body/Items/BodyLine2').Text,'B1 \u{203A} B3 \u{203A} A2 \u{203A} B2','order on line two')
expect(Binder.at(noteCard,'Body/Items/BodyLine4').Text,'in this order','note line four')
expect(Binder.at(noteCard,'Body/Items/BodyLine1').Font,'PatrickHand','paper keeps handwriting')
expect(noteOrigin,42,'pickup distance leash retained')
expect(ContextActionService.Actions.Level4CloseCard(nil,'Begin',{KeyCode=Enum.KeyCode.E}),'Sink','E closes note')
expect(noteCard.Visible,false,'note closed by E')
expect(ContextActionService.Actions.Level4ReopenNote(nil,'Begin'),'Sink','N/dpad reread path')
expect(noteCard.Visible,true,'known order reopens note')
expect(noteOrigin,nil,'reread has no pickup leash')
closeNote();modal=true
expect(ContextActionService.Actions.Level4ReopenNote(nil,'Begin'),'Pass','modal owns input')
expect(noteCard.Visible,false,'modal cannot reopen note')
modal=false;attrs.Level4_NoteOrder=nil
expect(ContextActionService.Actions.Level4ReopenNote(nil,'Begin'),'Pass','unknown order cannot reopen')
attrs.Level4_NoteOrder='B1 > B3 > A2 > B2'
hum.Health=0
expect(ContextActionService.Actions.Level4ReopenNote(nil,'Begin'),'Pass','a dead player cannot reopen private note')
hum.Health=100
touch=true;pad=false;openNote(nil,false);UIDevice.Changed:Fire()
expect(noteCard.Visible,true,'device remount retains note visibility')
expect(Binder.at(noteCard,'TapToClose').Visible,true,'touch close copy')
expect(Binder.at(noteCard,'CloseHint').Visible,false,'touch has no keycap instruction')
expect(#gui.Children,2,'one mounted instance of each card')
noteCard.Activated:Fire()
expect(noteCard.Visible,false,'whole paper tap closes')
openKeypad();press('7');press('8');UIDevice.Changed:Fire()
expect(entered,'78','device remount retains code input')
expect(display.Text,'78--','remounted code drawn')
expect(Binder.at(keypad,'CloseHit').Size.Y,44,'touch close has 44px hit target')
publishCard()
expect(attrs.Level4CardOpen,true,'touch cards publish exclusion')
closeKeypad();publishCard()
expect(attrs.Level4CardOpen,nil,'closing clears exclusion')
expect(ContextActionService.Actions.Level4CloseCard(nil,'Begin',{KeyCode=Enum.KeyCode.ButtonB}),'Pass','hidden cards pass B')
print('Level 4 note/keypad runtime: '..checks..' checks passed')
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN to an official Luau interpreter")
    source = CLIENT.read_text(encoding="utf-8-sig")
    begin = source.index("-- ---------------------------------------------------------------- note and keypad (B7")
    end = source.index("-- ---------------------------------------------------------------- the Usher (local rig)", begin)
    compiler = os.environ.get("LUAU_COMPILE_BIN") or str(Path(binary).with_name("luau-compile.exe"))
    result = subprocess.run([compiler, "--binary", str(CLIENT)], capture_output=True)
    if result.returncode:
        raise SystemExit(result.stderr.decode("utf-8", errors="replace"))
    with tempfile.TemporaryDirectory(prefix="level4-cards-") as directory:
        path = Path(directory) / "level4_cards.luau"
        subject_begin = source.index("local function objectiveSubject()")
        subject_end = source.index("-- B4_LEVEL4_STATE_BEGIN", subject_begin)
        result_begin = source.index('\telseif kind == "KeypadResult" then') + len('\telseif kind == "KeypadResult" then')
        result_end = source.index('\telseif kind == "Finale" then', result_begin)
        result_handler = "\nlocal function handleKeypadResult(payload)\n" + source[result_begin:result_end] + "\nend\n"
        path.write_text(PRELUDE + template_tree() + "\n" + source[subject_begin:subject_end] + source[begin:end] + result_handler + TESTS, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=20)
    print("Level 4 client compiled successfully; templates came from the actual HUD_Screens fixture")


if __name__ == "__main__":
    main()
