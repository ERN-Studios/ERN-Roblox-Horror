# Level 4 facelift: shared PBR material slots + export conventions. exec() this before any build script.
#
# slot(name, tint=None) -> bpy material "L4S_<name>[_rrggbb]" with the slot's PBR set from TEX:
#   <file>_albedo.png, <file>_normal.png (OpenGL), <file>_rough.png, <file>_metal.png (optional)
# Missing maps fall back to flat values, so geometry can be built before the textures exist.
# Custom props on the material (read by export_l4.py): l4_sem, l4_color, l4_tex (albedo), l4_normal,
# l4_rough, l4_metal, l4_tile (metres per repeat for box-projected UVs), l4_alpha, l4_uv ("box"|"mesh"),
# l4_emit (emission strength; >= 2 exports as Neon / emissive).
#
# Export conventions for objects under the "L4 Cinema" collection:
#   * plain mesh objects are pooled per material (architecture, detailing, ceilings);
#   * obj["l4_prop"] / obj["l4_door_leaf"] -> instanced asset placed as its own Model;
#   * collision: obj["l4_collide"] = "bounds" -> one box collider from the object's world bounds;
#     mesh["l4_col"] = JSON [[cx,cy,cz,sx,sy,sz], ...] boxes in the mesh's local metres;
#     obj["l4_seat"] = True -> the collider is a Roblox Seat (sittable) ; obj["l4_tags"] = "Tag1,Tag2";
#   * light objects in the "L4 Fixture Lights" collection export as Roblox lights
#     (obj["l4_shadows"] = True to cast shadows; light.energy/color/range via custom props l4_range, l4_brightness).
import bpy, os

TEX = r"G:\Blender\Level4_Cinema\textures\pbr"

# name: (file stem in TEX, tile metres, base rgb 0-255, roughness, metal, roblox material, sem)
SLOTS = {
    # moodboard slots (filled once the owner picks a direction)
    "CARPET_LOBBY":     ("carpet_lobby", 4.0, (90, 20, 30), 0.95, 0, "Carpet", "carpet"),
    "CARPET_ARCADE":    ("carpet_arcade", 3.0, (40, 10, 50), 0.95, 0, "Carpet", "carpet"),
    # v3 (2026-10-01): ONE dark synthwave wallpaper everywhere a wall shows plaster/wallpaper (owner: "ensartet",
    # not red). Near-black plum paper with magenta triangles + cyan squiggles, 4 pattern repeats per 1.2 m tile.
    "WALLPAPER_MAIN":   ("wallpaper_synth", 1.2, (30, 18, 34), 0.85, 0, "Fabric", "plaster"),
    # fixed slots
    "CARPET_AUD":       ("carpet_aud", 2.2, (70, 14, 22), 0.95, 0, "Carpet", "carpet"),
    "CARPET_STAFF":     ("carpet_staff", 1.8, (120, 100, 60), 0.95, 0, "Carpet", "carpet"),
    "PLASTER_PEEL":     ("plaster_peel", 3.2, (170, 80, 40), 0.85, 0, "Plaster", "plaster"),
    "WAINSCOT_LACQUER": ("wainscot_lacquer", 1.2, (20, 16, 16), 0.3, 0, "Wood", "wood"),
    "VELVET_FLUTE":     ("velvet_flute", 1.0, (90, 14, 22), 0.9, 0, "Fabric", "velvet"),
    "ACT_2x4":          ("act_2x4", 1.232, (190, 185, 170), 0.9, 0, "SmoothPlastic", "ceiling"),
    "DECK_BLACK":       ("deck_black", 2.4, (16, 15, 15), 0.9, 0, "SmoothPlastic", "ceiling"),
    "MARBLE_BLACK":     ("marble_black", 1.8, (30, 28, 28), 0.25, 0, "Marble", "marble"),
    "BRASS_AGED":       ("brass_aged", 0.8, (170, 128, 60), 0.35, 1, "Metal", "metal"),
    "CHROME_PITTED":    ("chrome_pitted", 0.8, (200, 200, 198), 0.2, 1, "Metal", "metal"),
    "STEEL_PAINTED":    ("steel_painted", 1.2, (70, 72, 76), 0.5, 0.3, "Metal", "metal"),
    "ALU_NOSING":       ("alu_nosing", 0.6, (170, 172, 175), 0.35, 1, "Metal", "metal"),
    "TILE_CREAM":       ("tile_cream", 1.2, (225, 215, 190), 0.3, 0, "CeramicTiles", "tile"),
    "TILE_TEAL":        ("tile_teal", 1.2, (40, 110, 110), 0.3, 0, "CeramicTiles", "tile"),
    "MOSAIC_BLACK":     ("mosaic_black", 0.6, (30, 30, 30), 0.35, 0, "CeramicTiles", "tile"),
    "CHECKER_VCT":      ("checker_vct", 1.2, (200, 200, 200), 0.4, 0, "CeramicTiles", "tile"),
    "FORMICA_SPECKLE":  ("formica_speckle", 1.0, (200, 195, 185), 0.35, 0, "SmoothPlastic", "plastic"),
    "LAMINATE_WOOD":    ("laminate_wood", 1.4, (110, 70, 40), 0.45, 0, "Wood", "wood"),
    "VINYL_TUFTED":     ("vinyl_tufted", 0.9, (110, 18, 26), 0.5, 0, "Leather", "velvet"),
    "VELOUR_SEAT":      ("velour_seat", 0.5, (130, 20, 30), 0.9, 0, "Fabric", "velvet"),
    "CONCRETE_SEALED":  ("concrete_sealed", 3.0, (120, 118, 112), 0.7, 0, "Concrete", "concrete"),
    "CMU_PAINT":        ("cmu_paint", 2.4, (190, 180, 160), 0.8, 0, "Concrete", "plaster"),
    "SCREEN_PERF":      ("screen_perf", 1.0, (220, 218, 210), 0.9, 0, "SmoothPlastic", "screen"),
    "RUBBER_BLACK":     ("rubber_black", 1.0, (25, 25, 25), 0.8, 0, "Rubber", "plastic"),
    "PLASTIC_BLACK":    ("plastic_black", 1.0, (22, 20, 22), 0.55, 0, "SmoothPlastic", "plastic"),
    "PORCELAIN":        ("porcelain", 1.0, (232, 230, 222), 0.15, 0, "SmoothPlastic", "plastic"),
    "GLASS_CLEAR":      (None, 1.0, (190, 205, 210), 0.05, 0, "Glass", "glass"),
    "GLASS_FROSTED":    (None, 1.0, (235, 230, 220), 0.4, 0, "Glass", "glass"),
    "MIRROR":           (None, 1.0, (200, 205, 210), 0.02, 1, "Glass", "glass"),
    "EMIT_WARM":        (None, 1.0, (255, 196, 140), 0.5, 0, "Neon", "neon"),
    "EMIT_COOL":        (None, 1.0, (225, 240, 255), 0.5, 0, "Neon", "neon"),
    "EMIT_RED":         (None, 1.0, (255, 40, 30), 0.5, 0, "Neon", "neon"),
    "EMIT_AMBER":       (None, 1.0, (255, 158, 84), 0.5, 0, "Neon", "neon"),
    # owner picked moodboard F "Synthwave Grid" (2026-09-30): magenta + cyan neon language
    "EMIT_MAGENTA":     (None, 1.0, (255, 40, 200), 0.5, 0, "Neon", "neon"),
    "EMIT_CYAN":        (None, 1.0, (40, 230, 255), 0.5, 0, "Neon", "neon"),
    "EMIT_ORANGE":      (None, 1.0, (255, 120, 40), 0.5, 0, "Neon", "neon"),
    # v3 (2026-10-01): boarded-up main entrance, starlight headliner ceilings
    "BOARD_WEATHERED":  ("board_weathered", 1.2, (120, 105, 90), 0.85, 0, "Wood", "wood"),
    "HEADLINER":        ("headliner_suede", 1.0, (10, 10, 14), 0.95, 0, "Fabric", "fabric"),
    "EMIT_STAR":        (None, 1.0, (255, 244, 225), 0.5, 0, "Neon", "neon"),
    "EMIT_STAR_COOL":   (None, 1.0, (220, 232, 255), 0.5, 0, "Neon", "neon"),
}
ALPHA = {"GLASS_CLEAR": 0.25, "GLASS_FROSTED": 0.6, "MIRROR": 0.9}


def _srgb2lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _img(path, noncolor):
    if not os.path.exists(path):
        return None
    im = bpy.data.images.get(os.path.basename(path)) or bpy.data.images.load(path)
    if noncolor:
        im.colorspace_settings.name = "Non-Color"
    return im


def slot(name, tint=None, uv="box"):
    stem, tile, rgb, rough, metal, rmat, sem = SLOTS[name]
    rgb = tuple(tint) if tint else rgb
    mname = "L4S_" + name + ("" if not tint else "_%02x%02x%02x" % rgb) + ("" if uv == "box" else "_uv")
    # Rebuild old master-blend materials when a slot changes or previously missing maps arrive.
    sig = repr(("world_box_v1", SLOTS[name], rgb, uv, tuple(os.path.exists(os.path.join(TEX, stem + "_" + k + ".png"))
                                         for k in ("albedo", "normal", "rough", "metal")) if stem else ()))
    m = bpy.data.materials.get(mname)
    if m and m.get("l4_slot_config") == sig:
        return m
    m = m or bpy.data.materials.new(mname)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(b.outputs["BSDF"], nt.nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
    lin = [_srgb2lin(c / 255) for c in rgb]
    b.inputs["Base Color"].default_value = (*lin, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    files = {}
    if stem:
        base = os.path.join(TEX, stem)
        maps = {k: _img(base + "_" + k + ".png", k != "albedo") for k in ("albedo", "normal", "rough", "metal")}
        if any(maps.values()):
            if uv == "box":
                geo = nt.nodes.new("ShaderNodeNewGeometry")
                vec = nt.nodes.new("ShaderNodeVectorMath"); vec.operation = "SCALE"
                vec.inputs["Scale"].default_value = 1.0 / tile
                nt.links.new(geo.outputs["Position"], vec.inputs[0])
                # Native BOX picks a LOCAL normal axis. With world Position that stretches rotated
                # wall panels into stripes. Pick the WORLD face axis explicitly, matching export_l4.box_uv.
                pos = nt.nodes.new("ShaderNodeSeparateXYZ")
                nt.links.new(vec.outputs["Vector"], pos.inputs[0])
                normal = nt.nodes.new("ShaderNodeVectorMath"); normal.operation = "ABSOLUTE"
                nt.links.new(geo.outputs["True Normal"], normal.inputs[0])
                axes = nt.nodes.new("ShaderNodeSeparateXYZ")
                nt.links.new(normal.outputs["Vector"], axes.inputs[0])
                planes = []
                for i, j in ((1, 2), (0, 2), (0, 1)):
                    xy = nt.nodes.new("ShaderNodeCombineXYZ")
                    nt.links.new(pos.outputs[i], xy.inputs[0]); nt.links.new(pos.outputs[j], xy.inputs[1])
                    planes.append(xy.outputs[0])
                yzmax = nt.nodes.new("ShaderNodeMath"); yzmax.operation = "MAXIMUM"
                nt.links.new(axes.outputs[1], yzmax.inputs[0]); nt.links.new(axes.outputs[2], yzmax.inputs[1])
                less = nt.nodes.new("ShaderNodeMath"); less.operation = "LESS_THAN"
                nt.links.new(axes.outputs[1], less.inputs[0]); nt.links.new(axes.outputs[2], less.inputs[1])
                yz = nt.nodes.new("ShaderNodeMixRGB")
                nt.links.new(less.outputs[0], yz.inputs[0])
                nt.links.new(planes[1], yz.inputs[1]); nt.links.new(planes[2], yz.inputs[2])
                less = nt.nodes.new("ShaderNodeMath"); less.operation = "LESS_THAN"
                nt.links.new(axes.outputs[0], less.inputs[0]); nt.links.new(yzmax.outputs[0], less.inputs[1])
                xyz = nt.nodes.new("ShaderNodeMixRGB")
                nt.links.new(less.outputs[0], xyz.inputs[0])
                nt.links.new(planes[0], xyz.inputs[1]); nt.links.new(yz.outputs[0], xyz.inputs[2])
                src = xyz.outputs[0]
            else:
                src = nt.nodes.new("ShaderNodeTexCoord").outputs["UV"]

            def tex(im):
                t = nt.nodes.new("ShaderNodeTexImage"); t.image = im
                nt.links.new(src, t.inputs["Vector"])
                return t
            if maps["albedo"]:
                t = tex(maps["albedo"])
                if tint:
                    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
                    mix.inputs["Factor"].default_value = 1.0
                    mix.inputs["A"].default_value = (*[min(1.0, c / 0.75) for c in lin], 1)
                    nt.links.new(t.outputs["Color"], mix.inputs["B"]); nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])
                else:
                    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
                files["l4_tex"] = os.path.basename(maps["albedo"].filepath)
            if maps["rough"]:
                nt.links.new(tex(maps["rough"]).outputs["Color"], b.inputs["Roughness"])
                files["l4_rough"] = os.path.basename(maps["rough"].filepath)
            if maps["metal"]:
                nt.links.new(tex(maps["metal"]).outputs["Color"], b.inputs["Metallic"])
                files["l4_metal"] = os.path.basename(maps["metal"].filepath)
            if maps["normal"]:
                nm = nt.nodes.new("ShaderNodeNormalMap")
                nt.links.new(tex(maps["normal"]).outputs["Color"], nm.inputs["Color"])
                nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
                files["l4_normal"] = os.path.basename(maps["normal"].filepath)
    emit = 6.0 if sem == "neon" else 0.0
    if emit:
        b.inputs["Emission Color"].default_value = (*lin, 1)
        b.inputs["Emission Strength"].default_value = emit
    alpha = ALPHA.get(name, 1.0)
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    m.diffuse_color = (*lin, alpha)
    m["l4_slot"] = name
    m["l4_slot_config"] = sig
    m["l4_sem"] = sem
    m["l4_roblox"] = rmat
    m["l4_color"] = list(rgb)
    m["l4_tile"] = tile
    m["l4_alpha"] = alpha
    m["l4_uv"] = uv
    m["l4_emit"] = emit
    for k in ("l4_tex", "l4_normal", "l4_rough", "l4_metal"):
        m[k] = files.get(k, "")
    return m
