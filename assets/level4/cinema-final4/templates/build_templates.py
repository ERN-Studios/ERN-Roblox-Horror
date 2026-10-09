"""Generate (do not execute) the scoped Roblox template builder from uploaded asset IDs.

python build_templates.py RESULTS.jsonl TEXTURE_IDS.json OUTPUT.luau [--export usher_export]
python build_templates.py --selftest

Texture IDs are keyed by usher_export/textures filenames, as make_place.py expects.
Chunk IDs50000+ avoid the cinema pipeline's existing IDs. Hash-qualified results must match
the current chunk exactly; asset permission/import is verified only when the resulting Luau runs.
"""
import argparse,base64,hashlib,json,math,re,struct
from pathlib import Path

HERE=Path(__file__).resolve().parent
DEFAULT=HERE/'usher_export'
MAPS={'tex':'ColorMap','normal':'NormalMap','rough':'RoughnessMap','metal':'MetalnessMap'}

def asset_uri(value):
    if isinstance(value,dict): value=value.get('url',value.get('asset',value.get('assetId')))
    match=re.fullmatch(r'(?:rbxassetid://)?([1-9][0-9]*)',str(value))
    if not match: raise ValueError('expected a positive uploaded asset ID, got '+repr(value))
    return 'rbxassetid://'+match[1]

def packet(export,results,textures):
    manifest=json.loads((export/'manifest.json').read_text()); rig=json.loads((export/'rig.json').read_text())
    by_hash={}; by_id={}
    for r in results:
        if not r.get('asset'): continue
        if r.get('h'): by_hash[r['h']]=r['asset']
        else: by_id[int(r['id'])]=r['asset']
    chunks={}
    for c in manifest['chunks']:
        blob=(export/'chunks'/('c%05d.b64'%c['id'])).read_text().strip()
        h=hashlib.sha256(blob.encode()).hexdigest()
        if h!=c['h']: raise ValueError('chunk content changed since manifest: '+str(c['id']))
        asset=by_hash.get(h,by_id.get(c['id']))
        if asset is None: raise ValueError('no matching uploaded asset for chunk '+str(c['id'])+' hash '+h)
        chunks[str(c['id'])]=dict(c,asset=asset_uri(asset))
    materials={}
    for name,m in manifest['materials'].items():
        appearance={}
        for field,prop in MAPS.items():
            fn=m.get(field)
            if not fn: continue
            if fn not in textures: raise ValueError('missing uploaded texture: '+fn)
            appearance[prop]=asset_uri(textures[fn])
        materials[name]={'color':[x/255 for x in m['color']],'material':m['roblox'],'alpha':m.get('alpha',1),'maps':appearance}
    return {'rig':rig,'chunks':chunks,'materials':materials}

LUA='''-- Generated offline; builds only the five named ServerStorage templates after all mesh imports succeed.
local HS = game:GetService("HttpService")
local SS = game:GetService("ServerStorage")
local AS = game:GetService("AssetService")
local DATA = HS:JSONDecode([==[__PACKET__]==])
local function vec(a) return Vector3.new(a[1], a[2], a[3]) end
local function cf(a) return CFrame.new(table.unpack(a)) end
local function partFrame(entry)
    local r = entry.rotation or {1,0,0,0,1,0,0,0,1}
    return CFrame.new(entry.center[1],entry.center[2],entry.center[3],table.unpack(r))
end
local function physics(part, anchored)
    part.Anchored = anchored == true
    part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
    part.Massless = true
end
local staging = Instance.new("Folder")
staging.Name = "Level 4 Templates Build"
local made = {}
local function mesh(entry, model)
    assert(#entry.chunks == 1, "each exported part must contain exactly one shared-material chunk")
    local chunk = assert(DATA.chunks[tostring(entry.chunks[1])], "missing chunk")
    local ok, part = pcall(AS.CreateMeshPartAsync, AS, Content.fromUri(chunk.asset),
        {CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Automatic})
    assert(ok and part, "mesh import failed: " .. entry.name .. ": " .. tostring(part))
    part.Name = entry.name
    part.Size = vec(chunk.size)
    part.CFrame = partFrame(entry)
    part.DoubleSided = true
    physics(part, false)
    local material = assert(DATA.materials[chunk.material], "missing material")
    part.Material = Enum.Material[material.material]
    part.Color = Color3.new(table.unpack(material.color))
    part.Transparency = 1 - material.alpha
    if next(material.maps) then
        part.Color = Color3.new(1,1,1)
        local sa = Instance.new("SurfaceAppearance")
        for property, asset in pairs(material.maps) do sa[property] = asset end
        sa.Parent = part
    end
    part.Parent = model
    return part
end
local function weld(a, b)
    local joint = Instance.new("WeldConstraint")
    joint.Name = b.Name .. "Weld"
    joint.Part0, joint.Part1 = a, b
    joint.Parent = b
end
local ok, result = pcall(function()
    local rig = DATA.rig
    local model = Instance.new("Model")
    model.Name = "Usher"
    model:SetAttribute("UsherHeight", 7.6)
    model.Parent = staging
    made.Usher = model
    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.Size, root.CFrame = vec(rig.root.size), partFrame(rig.root)
    root.Transparency, root.CastShadow = 1, false
    physics(root, true)
    root.Parent = model
    model.PrimaryPart = root
    local parts = {HumanoidRootPart = root}
    for _, entry in ipairs(rig.bones) do
        local part
        if entry.invisible then
            part = Instance.new("Part")
            part.Name = entry.part
            part.Size, part.CFrame = vec(entry.size), CFrame.new(vec(entry.center))
            part.Transparency, part.CastShadow = 1, false
            physics(part, false)
            part.Parent = model
        else
            entry.name = entry.part
            part = mesh(entry, model)
        end
        part:SetAttribute("UsherBone", entry.bone)
        if entry.mergedInto then part:SetAttribute("MergedInto", entry.mergedInto) end
        parts[entry.bone] = part
    end
    for _, entry in ipairs(rig.joints) do
        local joint = Instance.new("Motor6D")
        joint.Name = entry.name
        joint.Part0, joint.Part1 = assert(parts[entry.Part0]), assert(parts[entry.Part1])
        joint.C0, joint.C1 = cf(entry.C0), cf(entry.C1)
        joint.Parent = joint.Part1
    end
    for _, entry in ipairs(rig.attachments) do
        local part = mesh(entry, model)
        parts[entry.name] = part
        weld(assert(parts[entry.Part0]), part)
        if entry.light then
            local light = Instance.new("SpotLight")
            light.Name = "TicketBeam"
            light.Face = Enum.NormalId.Front
            light.Color = Color3.new(1,0,0)
            light.Brightness, light.Range, light.Angle = entry.light.brightness, entry.light.range, entry.light.angle
            light.Enabled, light.Shadows = false, false
            light.Parent = part
        end
    end
    for name, template in pairs(rig.templates) do
        local item = Instance.new("Model")
        item.Name, item.Parent = name, staging
        made[name] = item
        local itemParts = {}
        for _, entry in ipairs(template.parts) do itemParts[entry.name] = mesh(entry, item) end
        local primary = assert(itemParts[template.primaryPart])
        item.PrimaryPart = primary
        primary.Anchored = true
        if template.pivotOffset then primary.PivotOffset = CFrame.new(vec(template.pivotOffset)) end
        for _, part in pairs(itemParts) do if part ~= primary then weld(primary, part) end end
        if template.surfaceGui then
            local gui = Instance.new("SurfaceGui")
            gui.Name = "NoteText"
            gui.Face = Enum.NormalId.Top
            gui.CanvasSize = Vector2.new(420,300)
            gui.LightInfluence = 0.6
            local text = Instance.new("TextLabel")
            text.Name = "Text"
            text.Size = UDim2.fromScale(1,1)
            text.BackgroundTransparency = 1
            text.Font = Enum.Font.PatrickHand
            text.TextColor3 = Color3.fromRGB(40,30,40)
            text.TextScaled, text.TextWrapped = true, true
            text.Text = ""
            text.Parent = gui
            gui.Parent = itemParts.Paper
        end
    end
    -- Every import succeeded. Preserve unrelated templates and replace only the explicitly owned names.
    local target = SS:FindFirstChild("Level 4 Templates")
    if target then assert(target:IsA("Folder"), "Level 4 Templates must be a Folder")
    else target = Instance.new("Folder"); target.Name = "Level 4 Templates"; target.Parent = SS end
    for _, name in ipairs({"Usher","FilmReel","Fuse","BatteryPack","Note"}) do
        local previous = target:FindFirstChild(name)
        if previous then previous:Destroy() end
        made[name].Parent = target
    end
    return "Level 4 Templates built: Usher (24 Motors), FilmReel, Fuse, BatteryPack, Note"
end)
staging:Destroy()
assert(ok, result)
return result
'''

def generate(data):
    return LUA.replace('__PACKET__',json.dumps(data,separators=(',',':')))

def selftest(export=DEFAULT):
    manifest=json.loads((export/'manifest.json').read_text()); rig=json.loads((export/'rig.json').read_text())
    animations=json.loads((export/'animations.json').read_text()); total=0; bounds={}
    for c in manifest['chunks']:
        blob=base64.b64decode((export/'chunks'/('c%05d.b64'%c['id'])).read_text())
        nv,nn,nu,nf=struct.unpack_from('<4I',blob)
        assert nf==c['tris'] and nv==c['verts']
        assert len(blob)==16+12*(nv+nn)+8*nu+36*nf
        offset=16+12*(nv+nn)+8*nu
        for tri in struct.iter_unpack('<9I',blob[offset:]):
            assert max(tri[0::3])<nv and max(tri[1::3])<nn and max(tri[2::3])<nu
        positions=list(struct.iter_unpack('<3f',blob[16:16+12*nv]))
        assert all(math.isfinite(x) for p in positions for x in p)
        for axis in range(3):
            span=max(p[axis] for p in positions)-min(p[axis] for p in positions)
            assert abs(max(span,.05)-c['size'][axis])<.0003
        if c['template']=='Usher': total+=nf
        bounds[c['name']]=[min(p[1] for p in positions)+c['center'][1],max(p[1] for p in positions)+c['center'][1]]
    assert total<=9000
    assert sum(c['tris'] for c in manifest['chunks'] if c['template']=='FilmReel')<=1500
    assert len(rig['bones'])==len(rig['joints'])==len(animations['Joints'])==24
    assert set(animations['Joints'])=={j['name'] for j in rig['joints']}
    assert rig['root']['size']==[2,2,1] and rig['height']==7.6
    lowest=min(bounds[name][0] for name in ('LeftFoot','RightFoot'))
    assert abs(lowest)<.0002 and abs(bounds['Head'][1]-7.6)<.0002
    assert all(bounds[c['name']][0]>=lowest-.0002 for c in manifest['chunks'] if c['template']=='Usher')
    assert all(b['center'][1]-b['size'][1]/2>=lowest-.0002 for b in rig['bones'] if b['invisible'])
    # Rest motors must align exactly: Part0*C0 == Part1*C1. This catches wrong centre/axis frames.
    def compose(a,b):
        ar=[a[3:6],a[6:9],a[9:12]]; br=[b[3:6],b[6:9],b[9:12]]
        p=[a[i]+sum(ar[i][k]*b[k] for k in range(3)) for i in range(3)]
        r=[sum(ar[i][k]*br[k][j] for k in range(3)) for i in range(3) for j in range(3)]
        return p+r
    identity=[1,0,0,0,1,0,0,0,1]
    parts={b['bone']:b['center']+identity for b in rig['bones']}
    parts['HumanoidRootPart']=rig['root']['center']+rig['root']['rotation']
    rest_error=max(max(abs(a-b) for a,b in zip(compose(parts[j['Part0']],j['C0']),compose(parts[j['Part1']],j['C1']))) for j in rig['joints'])
    assert rest_error<.0002
    # Actor-aligned local -X pitch bends toward its local -Z LookVector; local +Y rotation remains yaw.
    assert rig['jointAxes'].startswith('character aligned')
    for j in rig['joints']:
        assert max(abs(a-b) for a,b in zip(j['C1'][3:],rig['root']['rotation']))<.00001
    pitch=math.radians(-22)
    pitched_up=[0,math.cos(pitch),math.sin(pitch)]
    actor_forward=[0,0,-1]
    assert sum(a*b for a,b in zip(pitched_up,actor_forward))>0
    assert all(abs(offset[0])+abs(offset[2])==0 for clip in animations['Clips'].values() for offset in clip['HipsOffset'])
    for clip in animations['Clips'].values():
        assert len(clip['Frames'])==len(clip['HipsOffset']) and abs(clip['Length']-len(clip['Frames'])/30)<.00005
        for frame in clip['Frames']:
            assert len(frame)==24
            assert all(abs(sum(x*x for x in q)-1)<.00025 for q in frame)
    assert [x['name'] for x in rig['attachments']]==['Torch','Lens']
    assert rig['attachments'][1]['light']['face']=='Front' and not rig['attachments'][1]['light']['enabled']
    # Fabricated IDs prove argument handling/source generation only; nothing is uploaded or executed.
    results=[{'id':c['id'],'asset':900000000000+c['id'],'h':c['h']} for c in manifest['chunks']]
    textures={fn:900000000001+i for i,fn in enumerate({m[f] for m in manifest['materials'].values() for f in MAPS if m.get(f)})}
    data=packet(export,results,textures); source=generate(data)
    assert '__PACKET__' not in source and 'Motor6D' in source and 'TicketBeam' in source
    wrong=[dict(r,h='wrong') for r in results]
    try: packet(export,wrong,textures)
    except ValueError: pass
    else: raise AssertionError('wrong chunk hashes must fail')
    try: packet(export,results,{})
    except ValueError: pass
    else: raise AssertionError('missing atlas maps must fail')
    report={'passed':True,'chunks':len(manifest['chunks']),'UsherTotalTris':total,'FilmReelTris':sum(c['tris'] for c in manifest['chunks'] if c['template']=='FilmReel'),
            'joints':24,'textureFiles':len(textures),'walkFrames':len(animations['Clips']['Walk']['Frames']),
            'runFrames':len(animations['Clips']['Run']['Frames']),'generatedLuauBytes':len(source.encode()),
            'restMotorMaxError':rest_error,'feetMinimumY':lowest,'headMaximumY':bounds['Head'][1],
            'assetIds':'fabricated only for offline generator self-check; no upload or Studio execution'}
    audit_path=HERE/'templates'/'audit.json'
    if audit_path.exists():
        audit=json.loads(audit_path.read_text())
        report['jointAxes']='actor Y up, -Z forward'
        report['retarget']={name:{key:audit[name][key] for key in ('nativeVsAlignedPartFrameMaxError','nativeVsSerializedPartPositionMaxErrorStuds','authoredSpeedStudsPerSecond')} for name in ('Walk','Run')}
        assert all(report['retarget'][name]['nativeVsAlignedPartFrameMaxError']<1e-6 and report['retarget'][name]['nativeVsSerializedPartPositionMaxErrorStuds']<.003 for name in ('Walk','Run'))
    (HERE/'templates'/'builder_check.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results',nargs='?'); parser.add_argument('textures',nargs='?'); parser.add_argument('output',nargs='?')
    parser.add_argument('--export',type=Path,default=DEFAULT); parser.add_argument('--selftest',action='store_true')
    args=parser.parse_args()
    if args.selftest: selftest(args.export); return
    if not all((args.results,args.textures,args.output)): parser.error('results.jsonl textures.json output.luau are required')
    records=[json.loads(line) for line in Path(args.results).read_text().splitlines() if line.strip()]
    data=packet(args.export,records,json.loads(Path(args.textures).read_text()))
    Path(args.output).write_text(generate(data),encoding='utf-8')
    print('Wrote '+args.output+'; execute only against the intended Studio place after its fresh baseline checks.')

if __name__=='__main__': main()
