"""Studio-rest Blender Actions and honest mesh-or-capsule contact-sheet previews.

Called inside the build's single Blender process. Coordinates in Rig stay Roblox:
right +X, up +Y, forward -Z. The object x90 rotation displays them in Blender.
"""
from pathlib import Path
import json
import math
import numpy as np
import bpy
from mathutils import Matrix, Vector

ROBOT_TO_BLENDER = Matrix.Rotation(math.pi / 2, 4, 'X')

# Authored 5x7 bitmap letters keep labels legible even where Workbench skips
# FONT surfaces. Rows are top-to-bottom, lit pixels are '1'.
_FONT = {
	'A':'01110/10001/10001/11111/10001/10001/10001', 'B':'11110/10001/10001/11110/10001/10001/11110',
	'C':'01111/10000/10000/10000/10000/10000/01111', 'D':'11110/10001/10001/10001/10001/10001/11110',
	'E':'11111/10000/10000/11110/10000/10000/11111', 'F':'11111/10000/10000/11110/10000/10000/10000',
	'G':'01111/10000/10000/10111/10001/10001/01111', 'H':'10001/10001/10001/11111/10001/10001/10001',
	'I':'11111/00100/00100/00100/00100/00100/11111', 'J':'00111/00010/00010/00010/00010/10010/01100',
	'K':'10001/10010/10100/11000/10100/10010/10001', 'L':'10000/10000/10000/10000/10000/10000/11111',
	'M':'10001/11011/10101/10101/10001/10001/10001', 'N':'10001/11001/10101/10011/10001/10001/10001',
	'O':'01110/10001/10001/10001/10001/10001/01110', 'P':'11110/10001/10001/11110/10000/10000/10000',
	'Q':'01110/10001/10001/10001/10101/10010/01101', 'R':'11110/10001/10001/11110/10100/10010/10001',
	'S':'01111/10000/10000/01110/00001/00001/11110', 'T':'11111/00100/00100/00100/00100/00100/00100',
	'U':'10001/10001/10001/10001/10001/10001/01110', 'V':'10001/10001/10001/10001/10001/01010/00100',
	'W':'10001/10001/10001/10101/10101/10101/01010', 'X':'10001/10001/01010/00100/01010/10001/10001',
	'Y':'10001/10001/01010/00100/00100/00100/00100', 'Z':'11111/00001/00010/00100/01000/10000/11111',
	'0':'01110/10001/10011/10101/11001/10001/01110', '1':'00100/01100/00100/00100/00100/00100/01110',
	'2':'01110/10001/00001/00010/00100/01000/11111', '3':'11110/00001/00001/01110/00001/00001/11110',
	'4':'00010/00110/01010/10010/11111/00010/00010', '5':'11111/10000/10000/11110/00001/00001/11110',
	'6':'01110/10000/10000/11110/10001/10001/01110', '7':'11111/00001/00010/00100/01000/01000/01000',
	'8':'01110/10001/10001/01110/10001/10001/01110', '9':'01110/10001/10001/01111/00001/00001/01110',
	'.':'00000/00000/00000/00000/00000/00100/00100', '=':'00000/00000/11111/00000/11111/00000/00000',
	'_':'00000/00000/00000/00000/00000/00000/11111', '|':'00100/00100/00100/00100/00100/00100/00100',
	'-':'00000/00000/00000/11111/00000/00000/00000', ' ':'00000/00000/00000/00000/00000/00000/00000',
}


def _bitmap_labels(pixels, title, timing):
	pixels[:44, :, :] = (.91, .93, .93, 1)
	for line, bottom in ((title.upper(), 25), (timing.upper(), 6)):
		for column, char in enumerate(line):
			for row, bits in enumerate(_FONT.get(char, _FONT[' ']).split('/')):
				for x, bit in enumerate(bits):
					if bit == '1':
						x0 = 8 + column * 12 + x * 2
						y0 = bottom + (6 - row) * 2
						if x0 + 2 < pixels.shape[1]:
							pixels[y0:y0 + 2, x0:x0 + 2, :] = (.055, .075, .085, 1)


def mat(m):
	return Matrix(np.asarray(m).tolist())


def _material(name, rgba):
	m = bpy.data.materials.new(name)
	m.diffuse_color = rgba
	return m


def _reset():
	bpy.ops.object.select_all(action='SELECT')
	bpy.ops.object.delete(use_global=False)
	for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures, bpy.data.actions):
		for block in list(datablocks):
			if block.users == 0:
				datablocks.remove(block)


def _make_armature(rig):
	data = bpy.data.armatures.new('Studio_Rest_51_Bones')
	obj = bpy.data.objects.new('Entity_Studio_Rig', data)
	bpy.context.collection.objects.link(obj)
	obj.matrix_world = ROBOT_TO_BLENDER.copy()
	bpy.context.view_layer.objects.active = obj
	obj.select_set(True)
	bpy.ops.object.mode_set(mode='EDIT')
	for name in rig.order:
		eb = data.edit_bones.new(name)
		children = [n for n in rig.order if rig.parents[n] == name]
		length = min([np.linalg.norm(rig.rest_world[n][:3, 3] - rig.rest_world[name][:3, 3]) for n in children] or [0.35])
		# A newly allocated EditBone has zero length. Setting matrix then length
		# discards its Y direction; establish a real local-Y segment first.
		eb.head = (0, 0, 0)
		eb.tail = (0, max(float(length), 0.12), 0)
		eb.matrix = mat(rig.rest_world[name])
		if rig.parents[name]:
			eb.parent = data.edit_bones[rig.parents[name]]
			eb.use_connect = False
	bpy.ops.object.mode_set(mode='OBJECT')
	rest_matrix_error = max(float(np.max(np.abs(np.array(data.bones[n].matrix_local) - rig.rest_world[n]))) for n in rig.order)
	assert rest_matrix_error < 0.001, f'Blender rest basis mismatch: {rest_matrix_error:.7f}'
	obj['studio_rest_matrix_max_abs_error'] = rest_matrix_error
	obj.show_in_front = True
	data.display_type = 'STICK'
	for bone in obj.pose.bones:
		bone.rotation_mode = 'QUATERNION'
	return obj


def _set_pose(armature, pose):
	for pb in armature.pose.bones:
		pb.matrix_basis = mat(pose.get(pb.name, np.eye(4)))
	bpy.context.view_layer.update()


def _key_actions(armature, rig, clips):
	armature.animation_data_create()
	max_error = 0.0
	for name, clip in clips.items():
		action = bpy.data.actions.new(name)
		action.use_fake_user = True
		action['fps'] = float(clip['fps'])
		action['seconds'] = float(clip.get('seconds', len(clip['poses']) / clip['fps']))
		action['loop'] = bool(clip.get('loop', False))
		action['stride'] = float(clip.get('stride', 0))
		action['authored_speed'] = float(clip.get('speed', 0))
		armature.animation_data.action = action
		previous_quaternion = {}
		# The payload wraps N samples; Blender also needs the closing interval.
		key_poses = clip['poses'] + ([clip['poses'][0]] if clip.get('loop') else [])
		for i, pose in enumerate(key_poses):
			key_frame = i + 1 if clip.get('loop') else 1 + i * len(clip['poses']) / (len(clip['poses']) - 1)
			_set_pose(armature, pose)
			for pb in armature.pose.bones:
				q = pb.rotation_quaternion.copy()
				q.normalize()
				if pb.name in previous_quaternion and q.dot(previous_quaternion[pb.name]) < 0:
					q.negate()
				pb.rotation_quaternion = q
				previous_quaternion[pb.name] = q.copy()
				pb.keyframe_insert(data_path='location', frame=key_frame, group=pb.name)
				pb.keyframe_insert(data_path='rotation_quaternion', frame=key_frame, group=pb.name)
				pb.keyframe_insert(data_path='scale', frame=key_frame, group=pb.name)
			fk = rig.fk(pose)
			for n in rig.order:
				max_error = max(max_error, float(np.linalg.norm(np.array(armature.pose.bones[n].head) - fk[n][:3, 3])))
		# Blender 4.4+ Actions use channel bags rather than Action.fcurves.
		curves = []
		if hasattr(action, 'fcurves'):
			curves = list(action.fcurves)
		else:
			for layer in action.layers:
				for strip in layer.strips:
					for bag in strip.channelbags:
						curves += list(bag.fcurves)
		for fc in curves:
			for kp in fc.keyframe_points:
				kp.interpolation = 'LINEAR'
	armature.animation_data.action = None
	_set_pose(armature, {})
	assert max_error < 0.001, f'Blender/Roblox FK mismatch: {max_error:.7f} stud'
	return max_error


def _fbx_preview(rig, armature, source_fbx):
	"""Bake Watch frame 0, measure one similarity fit, then rebind by group name."""
	report = {'source': str(source_fbx), 'accepted': False}
	before = set(bpy.data.objects)
	try:
		bpy.ops.import_scene.fbx(filepath=str(source_fbx), use_anim=True)
		added = [o for o in bpy.data.objects if o not in before]
		old_rigs = [o for o in added if o.type == 'ARMATURE']
		if not old_rigs:
			raise ValueError('FBX has no armature')
		old = max(old_rigs, key=lambda o: len(o.pose.bones))
		bpy.context.scene.frame_set(0)
		bpy.context.view_layer.update()
		lookup = {pb.name.split(':')[-1]: pb for pb in old.pose.bones}
		names = [n for n in rig.order if n in lookup]
		if len(names) < 40:
			raise ValueError(f'Only {len(names)} matching bone names')
		x = np.array([old.matrix_world @ lookup[n].head for n in names], dtype=float)
		y = np.array([rig.rest_world[n][:3, 3] for n in names])
		xc, yc = x.mean(axis=0), y.mean(axis=0)
		x0, y0 = x - xc, y - yc
		u, sigma, vt = np.linalg.svd(x0.T @ y0)
		fix = np.diag([1, 1, np.linalg.det(vt.T @ u.T)])
		rotation = vt.T @ fix @ u.T
		scale = float(np.sum(sigma * np.diag(fix)) / np.sum(x0 * x0))
		translation = yc - scale * rotation @ xc
		fit = np.eye(4)
		fit[:3, :3] = scale * rotation
		fit[:3, 3] = translation
		pred = (scale * rotation @ x.T).T + translation
		error = np.linalg.norm(pred - y, axis=1)
		report.update(scale=scale, max_joint_error=float(error.max()), mean_joint_error=float(error.mean()), measured_bones=len(names), worst_bone=names[int(error.argmax())], required_tolerance=0.05)
		if float(error.max()) > 0.05:
			raise ValueError('Watch frame 0 differs from Studio rest beyond 0.05 stud')
		meshes = [o for o in added if o.type == 'MESH']
		if not meshes:
			raise ValueError('FBX has no skinned preview mesh')
		for mesh in meshes:
			bpy.context.view_layer.objects.active = mesh
			mesh.select_set(True)
			for mod in list(mesh.modifiers):
				if mod.type == 'ARMATURE':
					bpy.ops.object.modifier_apply(modifier=mod.name)
			world = np.array(mesh.matrix_world, dtype=float)
			conversion = fit @ world
			for vertex in mesh.data.vertices:
				v = np.ones(4)
				v[:3] = vertex.co
				vertex.co = tuple((conversion @ v)[:3])
			mesh.parent = None
			mesh.matrix_world = ROBOT_TO_BLENDER.copy()
			for group in mesh.vertex_groups:
				group.name = group.name.split(':')[-1]
			mod = mesh.modifiers.new('Studio_Exact_Rig', 'ARMATURE')
			mod.object = armature
			mesh.name = 'Entity_Validated_FBX_Preview'
			for polygon in mesh.data.polygons:
				polygon.use_smooth = True
		for obj in added:
			if obj.type != 'MESH':
				bpy.data.objects.remove(obj, do_unlink=True)
		report['accepted'] = True
		report['method'] = 'FBX Watch frame 0 baked, one rigid similarity fit, rebind by bone name'
		return report
	except Exception as exc:
		report['reason'] = str(exc)
		for obj in list(bpy.data.objects):
			if obj not in before:
				bpy.data.objects.remove(obj, do_unlink=True)
		return report


class _ProxyBuilder:
	def __init__(self):
		self.vertices, self.faces, self.groups, self.materials = [], [], [], []

	def _append(self, verts, faces, bone, material):
		base = len(self.vertices)
		self.vertices += [tuple(v) for v in verts]
		self.faces += [tuple(base + i for i in f) for f in faces]
		self.groups += [(base + i, bone) for i in range(len(verts))]
		self.materials += [material] * len(faces)

	def ellipsoid(self, center, radii, bone, material=0, orientation=None):
		verts, faces = [], []
		orientation = np.eye(3) if orientation is None else np.asarray(orientation)
		for i in range(9):
			lat = -math.pi / 2 + math.pi * i / 8
			for j in range(12):
				lon = 2 * math.pi * j / 12
				p = np.array([math.cos(lat) * math.cos(lon), math.sin(lat), math.cos(lat) * math.sin(lon)]) * np.array(radii)
				verts.append(np.asarray(center) + orientation @ p)
		for i in range(8):
			for j in range(12):
				faces.append((i * 12 + j, i * 12 + (j + 1) % 12, (i + 1) * 12 + (j + 1) % 12, (i + 1) * 12 + j))
		self._append(verts, faces, bone, material)

	def segment(self, a, b, ra, rb, bone, material=0):
		a, b = np.asarray(a), np.asarray(b)
		direction = b - a
		if np.linalg.norm(direction) < 1e-6:
			return
		y = direction / np.linalg.norm(direction)
		x = np.cross(y, [0, 0, 1])
		if np.linalg.norm(x) < 0.1:
			x = np.cross(y, [1, 0, 0])
		x /= np.linalg.norm(x)
		z = np.cross(x, y)
		verts = []
		for center, r in ((a, ra), (b, rb)):
			for j in range(10):
				v = center + r * (x * math.cos(j * 2 * math.pi / 10) + z * math.sin(j * 2 * math.pi / 10))
				verts.append(v)
		faces = [(j, (j + 1) % 10, 10 + (j + 1) % 10, 10 + j) for j in range(10)]
		faces += [tuple(range(9, -1, -1)), tuple(range(10, 20))]
		self._append(verts, faces, bone, material)


def _capsule_preview(rig, armature):
	b = _ProxyBuilder()
	for name in rig.order:
		parent = rig.parents[name]
		if not parent or parent == 'Root':
			continue
		a = rig.rest_world[parent][:3, 3]
		end = rig.rest_world[name][:3, 3]
		if 'Hand' in parent:
			ra, rb = (0.065, 0.047) if any(s in parent for s in ('Thumb', 'Index', 'Middle', 'Ring', 'Pinky')) else (0.10, 0.068)
		elif 'Foot' in parent:
			ra, rb = .16, .13
		elif 'Leg' in parent:
			ra, rb = (.235, .19) if 'UpLeg' in parent else (.18, .13)
		elif 'Arm' in parent:
			ra, rb = (.23, .17) if 'Fore' not in parent else (.17, .13)
		elif 'Shoulder' in parent:
			ra, rb = .28, .27
		else:
			ra, rb = .34, .32
		b.segment(a, end, ra, rb, parent)
		if 'Hand' not in name and 'Toe' not in name:
			b.ellipsoid(end, [rb * 1.15] * 3, name)
	for name in rig.order:
		if name.endswith(('3', 'Thumb2')) and 'Hand' in name:
			g = rig.rest_world[name]
			length = .30 if 'Thumb' in name else .33
			b.segment(g[:3, 3], g[:3, 3] + g[:3, 1] * length, .053, .015, name, 1)
		if 'ToeBase' in name:
			g = rig.rest_world[name]
			b.segment(g[:3, 3], g[:3, 3] + g[:3, 1] * .46, .14, .09, name)
	# Ribs and pelvis: detached bone capsules cannot show torso twist alone.
	b.ellipsoid(rig.rest_world['Spine'][:3, 3] + [0, -.24, .10], [.68, .62, .34], 'Spine')
	b.ellipsoid(rig.rest_world['Spine01'][:3, 3], [.46, .54, .30], 'Spine01')
	b.ellipsoid(rig.rest_world['Hips'][:3, 3] + [0, -.15, 0], [.80, .40, .35], 'Hips')
	head = rig.rest_world['Head'][:3, 3]
	b.ellipsoid(head + [0, .65, .04], [.45, .78, .44], 'Head')
	b.ellipsoid(head + [0, .32, -.22], [.28, .34, .31], 'Head')
	for side in (-1, 1):
		b.ellipsoid(head + [side * .18, .78, -.387], [.094, .045, .026], 'Head', 2)
	mesh = bpy.data.meshes.new('Capsule_Proxy_Weighted_Body')
	mesh.from_pydata(b.vertices, [], b.faces)
	mesh.update()
	obj = bpy.data.objects.new('Entity_Capsule_Preview_NOT_REAL_MESH', mesh)
	bpy.context.collection.objects.link(obj)
	obj.matrix_world = ROBOT_TO_BLENDER.copy()
	for material in (_material('Bone graphite', (.12, .16, .18, 1)), _material('Tapered claws', (.30, .34, .34, 1)), _material('Head direction marks', (.7, .055, .025, 1))):
		mesh.materials.append(material)
	for i, polygon in enumerate(mesh.polygons):
		polygon.material_index = b.materials[i]
		polygon.use_smooth = True
	for n in rig.order:
		group = obj.vertex_groups.new(name=n)
		indices = [i for i, bone in b.groups if bone == n]
		if indices:
			group.add(indices, 1.0, 'REPLACE')
	mod = obj.modifiers.new('Studio_Exact_Rig', 'ARMATURE')
	mod.object = armature
	return obj


def _floor(floor_up):
	bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -floor_up - .015))
	floor = bpy.context.object
	floor.name = 'FLOOR_UP_REFERENCE'
	floor.data.materials.append(_material('Contact floor', (.71, .74, .74, 1)))
	# Fine study grid: all dimensions are studs, so viewers can judge stride.
	grid = _ProxyBuilder()
	for i in range(-18, 19, 2):
		grid.segment([i, -18, -floor_up], [i, 18, -floor_up], .012, .012, 'none')
		grid.segment([-18, i, -floor_up], [18, i, -floor_up], .012, .012, 'none')
	mesh = bpy.data.meshes.new('Floor_grid_2_studs')
	mesh.from_pydata(grid.vertices, [], grid.faces)
	mesh.update()
	obj = bpy.data.objects.new('Floor_grid_2_studs', mesh)
	bpy.context.collection.objects.link(obj)
	obj.data.materials.append(_material('Floor grid', (.57, .61, .62, 1)))


def _settings():
	scene = bpy.context.scene
	scene.render.engine = 'BLENDER_WORKBENCH'
	scene.render.resolution_x = 384
	scene.render.resolution_y = 384
	scene.render.resolution_percentage = 100
	scene.render.image_settings.file_format = 'PNG'
	scene.render.film_transparent = False
	scene.display.shading.light = 'STUDIO'
	scene.display.shading.color_type = 'MATERIAL'
	scene.display.shading.show_shadows = True
	scene.display.shading.show_cavity = True
	scene.display.shading.cavity_type = 'BOTH'
	scene.display.shading.curvature_ridge_factor = 1.4
	scene.display.shading.curvature_valley_factor = 1.1
	scene.display.shading.background_type = 'WORLD'
	scene.world.color = (.83, .85, .85)
	scene.view_settings.view_transform = 'Standard'
	return scene


def _make_camera():
	data = bpy.data.cameras.new('Review_camera')
	camera = bpy.data.objects.new('Review_camera', data)
	bpy.context.collection.objects.link(camera)
	data.type = 'ORTHO'
	bpy.context.scene.camera = camera
	curve = bpy.data.curves.new('Frame_label', 'FONT')
	curve.size = .28
	curve.align_x = 'LEFT'
	curve.align_y = 'TOP_BASELINE'
	label = bpy.data.objects.new('Frame_label', curve)
	bpy.context.collection.objects.link(label)
	label.hide_render = True
	curve.materials.append(_material('Labels', (.07, .10, .11, 1)))
	return camera, label


def _bounds(rig, clip, floor_up):
	points = []
	for pose in clip['poses']:
		fk = rig.fk(pose)
		for n in rig.order:
			if n != 'Root':
				p = Vector(fk[n][:3, 3])
				points.append(np.array(ROBOT_TO_BLENDER @ p))
		# Skull cap follows Head, with its measured rest orientation.
		g = fk['Head'] @ np.linalg.inv(rig.rest_world['Head'])
		p = np.ones(4)
		p[:3] = rig.rest_world['Head'][:3, 3] + [0, 1.5, 0]
		points.append(np.array(ROBOT_TO_BLENDER @ Vector((g @ p)[:3])))
	points = np.array(points)
	lo, hi = points.min(axis=0), points.max(axis=0)
	lo[2] = min(lo[2], -floor_up)
	return points, (lo + hi) / 2


def _review_views(rig, armature, clipname, clip, out_dir, floor_up, camera, label):
	poses = clip['poses']
	if clip.get('loop'):
		phases = [0, .08, .25, .46, .5, .58, .75, .96] if clipname == 'Prowl' else [0, .08, .25, .38, .5, .58, .75, .88]
		indices = np.array([int(round(p * len(poses))) % len(poses) for p in phases])
	else:
		indices = np.linspace(0, len(poses) - 1, 8).round().astype(int)
	points, center = _bounds(rig, clip, floor_up)
	directions = {'side': np.array([1., 0., .04]), 'front': np.array([0., 1., .04]), 'threequarter': np.array([.85, 1., .32])}
	paths = []
	for view, direction in directions.items():
		direction /= np.linalg.norm(direction)
		camera.location = Vector(center + direction * 40)
		camera.rotation_euler = (Vector(center) - camera.location).to_track_quat('-Z', 'Y').to_euler()
		q = camera.rotation_euler.to_quaternion()
		right, up = np.array(q @ Vector((1, 0, 0))), np.array(q @ Vector((0, 1, 0)))
		horizontal = points @ right
		vertical = points @ up
		camera.data.ortho_scale = max(float(np.ptp(horizontal)) * 1.2, float(np.ptp(vertical)) * 1.22) + .7
		label.rotation_euler = camera.rotation_euler.copy()
		label.data.size = camera.data.ortho_scale * .019
		label.location = Vector(center) + q @ Vector((-camera.data.ortho_scale * .46, -camera.data.ortho_scale * .405, 10))
		width = bpy.context.scene.render.resolution_x
		height = bpy.context.scene.render.resolution_y
		# A separate footer preserves every rendered toe/contact pixel.
		tile_height = height + 44
		sheet = np.empty((tile_height * 2, width * 4, 4), dtype=np.float32)
		for tile, index in enumerate(indices):
			_set_pose(armature, poses[int(index)])
			phase = int(index) / (len(poses) if clip.get('loop') else max(len(poses) - 1, 1))
			time_seconds = int(index) / clip['fps'] if clip.get('loop') else phase * clip.get('seconds', len(poses) / clip['fps'])
			label.data.body = f'{clipname} | {view}\nf{int(index):02d}  t={time_seconds:.3f}s  u={phase:.3f}'
			# Headless Render Result pixel buffers are not exposed reliably by every
			# Blender build; one overwritten tile file makes readback deterministic.
			tile_path = Path(__file__).resolve().parent / 'preview_tile.png'
			bpy.context.scene.render.filepath = str(tile_path)
			bpy.ops.render.render(write_still=True)
			result = bpy.data.images.load(str(tile_path), check_existing=False)
			pixels = np.empty(width * height * 4, dtype=np.float32)
			result.pixels.foreach_get(pixels)
			pixels = pixels.reshape(height, width, 4)
			labelled_tile = np.empty((tile_height, width, 4), dtype=np.float32)
			labelled_tile[44:] = pixels
			foot_info = clip.get('feet', [])
			contacts = foot_info[int(index)] if len(foot_info) > int(index) else {}
			marks = ''.join(side[0] if contacts.get(side, {}).get('stance') else '-' for side in ('Left', 'Right'))
			_bitmap_labels(labelled_tile, f'{clipname}|{view}', f'F{int(index):02d} T={time_seconds:.3f} U={phase:.3f} {marks}')
			# Image pixels start at lower left; order the contact sheet left to right, top first.
			row = 1 - tile // 4
			col = tile % 4
			sheet[row * tile_height:(row + 1) * tile_height, col * width:(col + 1) * width] = labelled_tile
			bpy.data.images.remove(result)
		image = bpy.data.images.new(f'{clipname}_{view}_sheet', width * 4, tile_height * 2, alpha=True)
		image.pixels.foreach_set(sheet.ravel())
		image.filepath_raw = str(out_dir / 'renders' / f'{clipname}_{view}.png')
		image.file_format = 'PNG'
		image.save()
		paths.append(str(image.filepath_raw))
		bpy.data.images.remove(image)
	return {'sample_frames': [int(i) for i in indices], 'views': paths, 'render_resolution': [384, 384], 'tile_resolution': [384, 428], 'sheet_resolution': [1536, 856]}


def build_preview(rig, clips, out_dir, floor_up=8.0, source_fbx=None, render=True, only=None):
	"""Build exact armature Actions, validate a preview, save blend, and render sheets."""
	out_dir = Path(out_dir)
	(out_dir / 'blend').mkdir(parents=True, exist_ok=True)
	(out_dir / 'renders').mkdir(parents=True, exist_ok=True)
	_reset()
	armature = _make_armature(rig)
	parity = _key_actions(armature, rig, clips)
	report = {'blender_fk_max_position_error': parity, 'blender_rest_matrix_max_abs_error': float(armature['studio_rest_matrix_max_abs_error']), 'floor_up': floor_up, 'clips': {}, 'proxy': 'capsules'}
	if source_fbx and Path(source_fbx).exists():
		report['fbx'] = _fbx_preview(rig, armature, source_fbx)
		if report['fbx']['accepted']:
			report['proxy'] = 'validated_fbx'
	if report['proxy'] == 'capsules':
		_capsule_preview(rig, armature)
	_floor(floor_up)
	scene = _settings()
	camera, label = _make_camera()
	if render:
		for name, clip in clips.items():
			if only and name != only:
				continue
			print(f'PREVIEW rendering {name}: 8 poses x 3 views', flush=True)
			report['clips'][name] = _review_views(rig, armature, name, clip, out_dir, floor_up, camera, label)
	first = next(iter(clips))
	armature.animation_data.action = bpy.data.actions[first]
	scene.frame_start = 1
	scene.frame_end = len(clips[first]['poses']) + (1 if clips[first].get('loop') else 0)
	scene.render.fps = 30
	scene.render.fps_base = 30 / clips[first]['fps']
	scene.frame_set(1)
	label.data.body = f'{first} | Studio rest rig\nFLOOR_UP = {floor_up:.3f} studs'
	bpy.context.preferences.filepaths.save_version = 0
	bpy.ops.wm.save_as_mainfile(filepath=str(out_dir / 'blend' / 'entity_motion.blend'))
	(Path(__file__).resolve().parent / 'preview_report.json').write_text(json.dumps(report, indent=2))
	print(f'PREVIEW FK parity max: {parity:.7f}; mesh: {report["proxy"]}', flush=True)
	return report
