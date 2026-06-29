# PROTOTYPE - 2D->3D migration, Phase A+B
# world.gd — reads SimState and renders it as a low-poly 3D field.
# No input yet (Phase C). Proves the logic(sim)/view(this) split + live growth.
# Date: 2026-06-29
extends Node3D

const TILE := 1.0

var sim: SimState
var _cam: Camera3D
var _crop_nodes: Array = []          # per-tile crop Node3D (or null)
var _soil_nodes: Array = []          # per-tile soil MeshInstance3D
var _rock_nodes: Array = []          # per-tile obstacle rock (or null)
var _last_state: PackedInt32Array
var _last_bucket: PackedInt32Array   # growth bucket, to know when to rebuild
const PICK_Y := 0.10                 # soil surface height for tap raycast

func _ready() -> void:
	sim = SimState.new()
	sim.setup_demo()

	_build_environment()
	_build_ground()
	_build_soil_tiles()
	_build_props()

	var n: int = sim.states.size()
	_crop_nodes.resize(n)
	_last_state = PackedInt32Array(); _last_state.resize(n)
	_last_bucket = PackedInt32Array(); _last_bucket.resize(n)
	for i in range(n):
		_crop_nodes[i] = null
		_last_state[i] = -1
		_last_bucket[i] = -1
		_refresh_crop(i)

	if OS.has_environment("VERIFY_SHOT"):
		_shoot()

func _process(delta: float) -> void:
	sim.tick(delta)
	# Rebuild a tile's plant when its state or growth bucket changes (6 visible steps).
	for i in range(sim.states.size()):
		var s: int = sim.states[i]
		var bucket: int = int(sim.grow[i] * 6.0)
		if s != _last_state[i] or bucket != _last_bucket[i]:
			_refresh_crop(i)

# ---------------------------------------------------------------- input (Phase C)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_tap(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_tap(event.position)

func _tap(screen_pos: Vector2) -> void:
	var idx := _tile_under(screen_pos)
	if idx < 0:
		return
	var ok: bool = sim.manual(idx)
	_refresh_tile(idx)
	_feedback(idx, ok)

# Screen -> camera ray -> soil plane -> tile index (-1 if off the plot). The heart of Phase C.
func _tile_under(screen_pos: Vector2) -> int:
	if _cam == null:
		return -1
	var from: Vector3 = _cam.project_ray_origin(screen_pos)
	var dir: Vector3 = _cam.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, PICK_Y)
	var hit = plane.intersects_ray(from, dir)
	if hit == null:
		return -1
	var world: Vector3 = hit
	var o := _origin()
	var c := int(round((world.x - o.x) / TILE))
	var r := int(round((world.z - o.z) / TILE))
	if c < 0 or c >= SimState.COLS or r < 0 or r >= sim.rows:
		return -1
	return r * SimState.COLS + c

# Rebuild every visual for one tile after its state changed (soil tint, rock, plant).
func _refresh_tile(idx: int) -> void:
	var soil: MeshInstance3D = _soil_nodes[idx]
	if soil != null:
		soil.material_override = _mat(_soil_color(sim.states[idx]), 1.0)
	var rock: Node3D = _rock_nodes[idx]
	if sim.states[idx] == SimState.OBSTACLE and rock == null:
		var cr := _tile_cr(idx)
		_add_rock(idx, _tile_pos(cr.x, cr.y), 0.10)
	elif sim.states[idx] != SimState.OBSTACLE and rock != null:
		rock.queue_free()
		_rock_nodes[idx] = null
	_refresh_crop(idx)

# Quick green (ok) / red (blocked) pop so taps read clearly while testing.
func _feedback(idx: int, ok: bool) -> void:
	var cr := _tile_cr(idx)
	var marker := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	marker.mesh = sm
	var col := Color(0.45, 0.95, 0.45) if ok else Color(0.95, 0.35, 0.30)
	var m := _mat(col, 0.3, 0.0)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.0
	marker.material_override = m
	add_child(marker)
	marker.position = _tile_pos(cr.x, cr.y) + Vector3(0, 0.5, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(marker, "scale", Vector3(2.2, 2.2, 2.2), 0.35)
	tw.tween_property(marker, "position:y", 1.1, 0.35)
	var m2 := m  # fade alpha
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tw.tween_property(m2, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(marker.queue_free)

# ---------------------------------------------------------------- layout
func _origin() -> Vector3:
	return Vector3(-(SimState.COLS - 1) * TILE * 0.5, 0.0, -(sim.rows - 1) * TILE * 0.5)

func _tile_pos(c: int, r: int) -> Vector3:
	return _origin() + Vector3(c * TILE, 0.0, r * TILE)

func _tile_cr(i: int) -> Vector2i:
	return Vector2i(i % SimState.COLS, i / SimState.COLS)

# ---------------------------------------------------------------- build
func _build_soil_tiles() -> void:
	var n: int = sim.states.size()
	_soil_nodes.resize(n)
	_rock_nodes.resize(n)
	# Raised soil bed under the plot.
	var bed := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SimState.COLS * TILE + 0.4, 0.18, sim.rows * TILE + 0.4)
	bed.mesh = bm
	bed.material_override = _mat(Color(0.30, 0.21, 0.14), 1.0)
	bed.position = Vector3(0, -0.04, 0)
	add_child(bed)

	for i in range(n):
		var cr := _tile_cr(i)
		var p := _tile_pos(cr.x, cr.y)
		var soil := MeshInstance3D.new()
		var sm := BoxMesh.new()
		var h := 0.10
		sm.size = Vector3(TILE * 0.92, h, TILE * 0.92)
		soil.mesh = sm
		soil.material_override = _mat(_soil_color(sim.states[i]), 1.0)
		soil.position = p + Vector3(0, h * 0.5, 0)
		add_child(soil)
		_soil_nodes[i] = soil
		_rock_nodes[i] = null
		if sim.states[i] == SimState.OBSTACLE:
			_add_rock(i, p, h)

func _add_rock(i: int, p: Vector3, h: float) -> void:
	var rock := MeshInstance3D.new()
	var rmesh := SphereMesh.new()
	rmesh.radius = 0.26
	rmesh.height = 0.42
	rmesh.radial_segments = 6
	rmesh.rings = 3
	rock.mesh = rmesh
	rock.material_override = _mat(Color(0.55, 0.55, 0.52), 0.95)
	rock.position = p + Vector3(0.0, h + 0.12, 0.0)
	add_child(rock)
	_rock_nodes[i] = rock

# Build a simple procedural plant so each lifecycle stage reads clearly in 3D.
# (Real per-stage Quaternius crop models come in Phase G — this proves the mapping.)
func _refresh_crop(i: int) -> void:
	_last_state[i] = sim.states[i]
	_last_bucket[i] = int(sim.grow[i] * 6.0)
	var existing: Node3D = _crop_nodes[i]
	if existing != null:
		existing.queue_free()
		_crop_nodes[i] = null
	var s: int = sim.states[i]
	if s != SimState.PLANTED and s != SimState.GROWING and s != SimState.RIPE:
		return
	var cr := _tile_cr(i)
	var holder := Node3D.new()
	add_child(holder)
	holder.position = _tile_pos(cr.x, cr.y) + Vector3(0, 0.10, 0)
	_crop_nodes[i] = holder

	var grow_f: float = sim.grow[i] if s == SimState.GROWING else (1.0 if s == SimState.RIPE else 0.0)
	var stem_h: float
	match s:
		SimState.PLANTED:
			stem_h = 0.10
		SimState.GROWING:
			stem_h = 0.14 + grow_f * 0.42
		_:
			stem_h = 0.58

	# stem
	var stem := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.05
	cm.height = stem_h
	cm.radial_segments = 5
	stem.mesh = cm
	stem.material_override = _mat(Color(0.32, 0.54, 0.25), 0.9)
	stem.position = Vector3(0, stem_h * 0.5, 0)
	holder.add_child(stem)

	# foliage
	var leaf := MeshInstance3D.new()
	var lr: float = 0.07 + stem_h * 0.20
	var sm := SphereMesh.new()
	sm.radius = lr
	sm.height = lr * 2.0
	sm.radial_segments = 6
	sm.rings = 4
	leaf.mesh = sm
	leaf.material_override = _mat(Color(0.27, 0.50, 0.23), 0.9)
	leaf.position = Vector3(0, stem_h + lr * 0.3, 0)
	holder.add_child(leaf)

	# ripe fruit — crop's signature color, gold + glow if golden
	if s == SimState.RIPE:
		var crop_col: Color = sim.CROPS[sim.crop_type[i]]["col"]
		var is_gold: bool = bool(sim.golden[i])
		var fruit := MeshInstance3D.new()
		var fr: float = 0.16 if is_gold else 0.14
		var fm := SphereMesh.new()
		fm.radius = fr
		fm.height = fr * 2.0
		fruit.mesh = fm
		var fmat := _mat(Color(0.97, 0.78, 0.18) if is_gold else crop_col, 0.45, 0.0)
		if is_gold:
			fmat.emission_enabled = true
			fmat.emission = Color(1.0, 0.84, 0.22)
			fmat.emission_energy_multiplier = 2.2
		fruit.material_override = fmat
		# sit the fruit as a crown above the foliage so its colour reads
		fruit.position = Vector3(0, stem_h + lr * 1.4 + fr * 0.5, 0)
		holder.add_child(fruit)

func _build_props() -> void:
	var back_z := _origin().z - 1.8
	var farm: PackedScene = load("res://assets/small_farm.glb")
	var inst: Node3D = farm.instantiate()
	add_child(inst)
	_scale_to(inst, 2.4, Vector3(-2.2, 0.0, back_z))

	for t in [Vector3(2.6, 0, back_z),
			Vector3(4.2, 0, back_z + 0.6),
			Vector3(-4.4, 0, back_z + 0.4)]:
		_tree(t)

func _build_ground() -> void:
	var grass := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(50, 50)
	grass.mesh = gm
	grass.material_override = _mat(Color(0.40, 0.56, 0.28), 0.95)
	grass.position = Vector3(0, -0.06, 0)
	add_child(grass)

# ---------------------------------------------------------------- environment (from look-test)
func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.52, 0.70, 0.92)
	sky_mat.sky_horizon_color = Color(0.86, 0.88, 0.84)
	sky_mat.ground_horizon_color = Color(0.82, 0.80, 0.74)
	sky_mat.ground_bottom_color = Color(0.55, 0.52, 0.46)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 2.2
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.5
	sun.rotation_degrees = Vector3(-52, -42, 0)
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.70, 0.80, 1.0)
	fill.light_energy = 0.25
	fill.rotation_degrees = Vector3(-30, 140, 0)
	add_child(fill)

	var cam := Camera3D.new()
	cam.fov = 58.0
	add_child(cam)
	cam.global_position = Vector3(0.0, 12.6, 13.2)
	cam.look_at(Vector3(0.0, 0.0, -0.4), Vector3.UP)
	_cam = cam

# ---------------------------------------------------------------- helpers
func _tree(at: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.10
	tm.bottom_radius = 0.14
	tm.height = 0.7
	trunk.mesh = tm
	trunk.material_override = _mat(Color(0.42, 0.28, 0.17), 1.0)
	trunk.position = at + Vector3(0, 0.35, 0)
	add_child(trunk)
	var greens := [Color(0.24, 0.44, 0.22), Color(0.28, 0.50, 0.25), Color(0.33, 0.56, 0.29)]
	for i in range(3):
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.55 - i * 0.13
		cm.height = 0.55
		cm.radial_segments = 7
		cone.mesh = cm
		cone.material_override = _mat(greens[i], 1.0)
		cone.position = at + Vector3(0, 0.75 + i * 0.34, 0)
		add_child(cone)

func _soil_color(s: int) -> Color:
	match s:
		SimState.EMPTY:
			return Color(0.50, 0.37, 0.23)
		SimState.OBSTACLE:
			return Color(0.46, 0.34, 0.21)
		SimState.TILLED:
			return Color(0.36, 0.26, 0.16)
		SimState.PLANTED:
			return Color(0.41, 0.30, 0.18)
		_:
			return Color(0.34, 0.25, 0.15)

# Scale a glb instance so its largest footprint == target, optionally reposition to sit on ground.
func _scale_to(inst: Node3D, target: float, at = null) -> void:
	inst.scale = Vector3.ONE
	var ab := _local_aabb(inst)
	var span: float = max(ab.size.x, ab.size.z)
	if span < 0.0001:
		span = max(ab.size.y, 0.0001)
	var sc: float = target / span
	inst.scale = Vector3(sc, sc, sc)
	if at != null:
		var pos: Vector3 = at
		inst.position = pos + Vector3(0, -ab.position.y * sc, 0)

func _local_aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for node in _all_meshes(root):
		var mi: MeshInstance3D = node
		if mi.mesh == null:
			continue
		var lt: Transform3D = inv * mi.global_transform
		var ab: AABB = lt * mi.mesh.get_aabb()
		if first:
			acc = ab
			first = false
		else:
			acc = acc.merge(ab)
	return acc

func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out

func _mat(col: Color, rough: float = 1.0, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m

func _shoot() -> void:
	if OS.has_environment("TAP_TEST"):
		_verify_taps()
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://_shot_3d.png")
		get_tree().quit()
	)

# Headless sanity check for the screen->tile->manual chain: find each tile's screen
# position via unproject (inverse of the tap raycast), tap it, assert the round-trip.
func _verify_taps() -> void:
	print("=== TAP_TEST: screen->tile round-trip ===")
	var ok := true
	for i: int in [0, 1, sim.states.size() - 1]:  # obstacle/empty corner, neighbour, front tile
		var cr := _tile_cr(i)
		var world := _tile_pos(cr.x, cr.y) + Vector3(0, PICK_Y, 0)
		var screen := _cam.unproject_position(world)
		var got: int = _tile_under(screen)
		var pass_i: bool = got == i
		ok = ok and pass_i
		print("  tile %d -> screen %s -> tile %d   %s" % [i, str(screen.round()), got, "PASS" if pass_i else "FAIL"])
	# exercise the full action on a known tile (front row is RIPE in the demo)
	var last := sim.states.size() - 1
	var before_state := sim.states[last]
	var got_action: bool = sim.manual(last)
	_refresh_tile(last)
	print("  manual(front RIPE tile): state %d -> %d, action=%s" % [before_state, sim.states[last], str(got_action)])
	print("=== TAP_TEST %s ===" % ["PASS" if ok else "FAIL"])
