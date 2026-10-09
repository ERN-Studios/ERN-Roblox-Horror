from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def edit(rel, replacements):
    path=ROOT/rel;s=path.read_text(encoding='utf-8')
    for old,new in replacements:
        assert old in s,(rel,old)
        s=s.replace(old,new)
    path.write_text(s,encoding='utf-8')

BASE='StarterPlayer/StarterPlayerScripts/'
edit(BASE+'RoundUI.LocalScript.lua',[
 ('queueCloseStroke.Color = Color3.fromRGB(255, 125, 125)','queueCloseStroke.Color = Color3.fromRGB(255, 138, 120)'),
 ('Color3.fromRGB(115, 255, 170)','Color3.fromRGB(127, 218, 166)'),
 ('Color3.fromRGB(105, 255, 165)','Color3.fromRGB(83, 204, 145)'),
 ('Color3.fromRGB(255, 82, 72)','Color3.fromRGB(255, 116, 96)'),
 ('pd.cardStroke.Thickness = 1.5','pd.cardStroke.Thickness = 1'),
 ('stroke.Thickness = thickness\n\tstroke.Parent = parent','stroke.Thickness = thickness\n\tstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border\n\tstroke.Parent = parent'),
])
for file in ['ZyntraStore.LocalScript.lua','Shop Display Client.LocalScript.lua']:
    edit(BASE+file,[
     ('Color3.fromRGB(65, 92, 98)','Color3.fromRGB(75, 94, 83)'),
     ('Color3.fromRGB(232, 240, 238)','Color3.fromRGB(231, 238, 233)'),
     ('object.Transparency = transparency or 0','object.Transparency = transparency or 0.28'),
     ('object.Thickness = thickness or 1','object.Thickness = thickness or 1\n\tobject.ApplyStrokeMode = Enum.ApplyStrokeMode.Border'),
    ])
edit(BASE+'ZyntraStore.LocalScript.lua',[
 ('radius or 8','radius or 9'),('font or Enum.Font.Gotham','font or Enum.Font.GothamMedium')])
edit(BASE+'Shop Display Client.LocalScript.lua',[
 ('makeLabel("ItemDescription", Enum.Font.Gotham,','makeLabel("ItemDescription", Enum.Font.GothamMedium,')])
edit(BASE+'NoiseReporter.LocalScript.lua',[
 ('button.BackgroundColor3 = Color3.fromRGB(8, 10, 9)','button.BackgroundColor3 = Color3.fromRGB(14, 20, 17)'),
 ('button.BackgroundTransparency = 0.52','button.BackgroundTransparency = 0.04'),
 ('stroke.Color = Color3.fromRGB(220, 228, 218)','stroke.Color = Color3.fromRGB(75, 94, 83)'),
 ('stroke.Transparency = 0.48','stroke.Transparency = 0.28'),
 ('stroke.Thickness = 1.5\n\tstroke.Parent = button','stroke.Thickness = 1\n\tstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border\n\tstroke.Parent = button'),
 ('staBg.BackgroundColor3 = Color3.new(0, 0, 0)','staBg.BackgroundColor3 = Color3.fromRGB(4, 8, 6)'),
 ('bgc.CornerRadius = UDim.new(0, 5)','bgc.CornerRadius = UDim.new(1, 0)'),
])
edit(BASE+'Level 3 Table Hiding Client.LocalScript.lua',[
 ('message.BackgroundColor3 = Color3.fromRGB(8, 10, 11)','message.BackgroundColor3 = Color3.fromRGB(4, 8, 6)'),
 ('message.BackgroundTransparency = .24','message.BackgroundTransparency = .18'),
 ('messageStroke.Color = Color3.fromRGB(79, 183, 157)','messageStroke.Color = Color3.fromRGB(75, 94, 83)'),
 ('messageStroke.Transparency = .2','messageStroke.Transparency = .28'),
 ('messageStroke.Thickness = 1.5','messageStroke.Thickness = 1\nmessageStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border'),
 ('leave.BackgroundColor3 = Color3.fromRGB(17, 22, 23)','leave.BackgroundColor3 = Color3.fromRGB(14, 20, 17)'),
 ('leave.BackgroundTransparency = .08','leave.BackgroundTransparency = .04'),
 ('leaveCorner.CornerRadius = UDim.new(0, 10)','leaveCorner.CornerRadius = UDim.new(0, 9)'),
 ('leaveStroke.Color = Color3.fromRGB(101, 224, 187)','leaveStroke.Color = Color3.fromRGB(75, 94, 83)'),
 ('leaveStroke.Transparency = .05','leaveStroke.Transparency = .28'),
 ('leaveStroke.Thickness = 2','leaveStroke.Thickness = 1\nleaveStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border'),
 ('leave.TextColor3 = Color3.fromRGB(236, 248, 243)','leave.TextColor3 = Color3.fromRGB(231, 238, 233)'),
])
print('Applied reference palette and border finishing to five UI files')
