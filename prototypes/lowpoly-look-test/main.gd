# PROTOTYPE - NOT FOR PRODUCTION
# Question: Does the low-poly 3D look (cozy lighting/camera) match what we want?
# Date: 2026-06-29
extends Node3D

const COLS := 5
const ROWS := 6
const TILE := 1.0

var _crop_scene: PackedScene
var _farm_scene: PackedScene

func _ready() -> void:
	if OS.has_environment("INSPECT"):
		_inspect("res://assets/crops.glb")
		_inspect("res://assets/small_farm.glb")
		get_tree().quit()
		return

	_crop_scene = load("res://assets/crops.glb")
	_farm_scene = load("res://assets/small_farm.glb")

	_build_environment()
	_build_field()
	_build_props()

	if OS.has_environment("VERIFY_SHOT"):
		_shoot()

# ---------------------------------------------------------------- environment
func _build_environment() -> void:
	# Cozy warm sky + ambient + SSAO + soft shadows + gentle glow.
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.52, 0.70, 0.92)
	sky_mat.sky_horizon_color = Color(0.86, 0.88, 0.84)
	sky_mat.ground_horizon_color = Color(0.82, 0.80, 0.74)
	sky_mat.ground_bottom_color = Color(0.55, 0.52, 0.46)
	sky_mat.sun_angle_max = 30.0
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
	env.glow_bloom = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Warm key sun with soft shadows.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.5
	sun.rotation_degrees = Vector3(-52, -42, 0)
	add_child(sun)

	# Cool fill so shadows aren't muddy.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.70, 0.80, 1.0)
	fill.light_energy = 0.25
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-30, 140, 0)
	add_child(fill)

	# Cozy angled camera framing the field in portrait.
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.global_position = Vector3(0.0, 7.4, 7.6)
	cam.look_at(Vector3(0.0, 0.0, -0.3), Vector3.UP)

# ---------------------------------------------------------------- field
func _field_origin() -> Vector3:
	return Vector3(-(COLS - 1) * TILE * 0.5, 0.0, -(ROWS - 1) * TILE * 0.5)

func _tile_pos(c: int, r: int) -> Vector3:
	return _field_origin() + Vector3(c * TILE, 0.0, r * TILE)

func _build_field() -> void:
	# Big grass ground.
	var grass := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(40, 40)
	grass.mesh = gm
	grass.material_override = _mat(Color(0.40, 0.56, 0.28), 0.95)
	grass.position = Vector3(0, -0.06, 0)
	add_child(grass)

	# Soil bed under the tiles (a single raised plot).
	var bed := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(COLS * TILE + 0.5, 0.18, ROWS * TILE + 0.5)
	bed.mesh = bm
	bed.material_override = _mat(Color(0.33, 0.23, 0.16), 1.0)
	bed.position = Vector3(0, -0.03, 0)
	add_child(bed)

	# Per-tile soil + crops at varied growth so 5 stages read clearly.
	for r in range(ROWS):
		for c in range(COLS):
			var p := _tile_pos(c, r)
			var soil := MeshInstance3D.new()
			var sm := BoxMesh.new()
			var h := 0.10 + _jitter(c, r) * 0.04
			sm.size = Vector3(TILE * 0.92, h, TILE * 0.92)
			soil.mesh = sm
			# A few tilled (darker) rows, rest planted.
			var tilled := r >= ROWS - 2
			soil.material_override = _mat(
				Color(0.30, 0.20, 0.13) if tilled else Color(0.40, 0.28, 0.18), 1.0)
			soil.position = p + Vector3(0, h * 0.5, 0)
			add_child(soil)

			if not tilled:
				# Stagger crop scale to fake growth stages across the plot.
				var stage := float((c + r) % 4 + 1) / 4.0  # 0.25 .. 1.0
				_place_model(_crop_scene, p + Vector3(0, h, 0), 0.9 * stage)

func _build_props() -> void:
	# Farmhouse behind the plot.
	_place_model(_farm_scene, Vector3(-1.4, 0.0, -(ROWS * 0.5) - 1.4), 2.6)
	# Real Quaternius crop clump used as a decorative bush cluster too.
	_place_model(_crop_scene, Vector3((COLS * 0.5) + 0.6, 0.0, -1.0), 1.1)

	# A few procedural low-poly pine trees for depth.
	for t in [Vector3(-(COLS * 0.5) - 1.2, 0, 1.5), Vector3((COLS * 0.5) + 1.4, 0, 2.4), Vector3((COLS * 0.5) + 1.0, 0, -3.0)]:
		_tree(t)

	# Cute farming bots (placeholder mesh — the real robot art comes later).
	_bot(_tile_pos(1, 1) + Vector3(0.0, 0.0, 0.0), Color(0.30, 0.72, 0.66))   # harvester
	_bot(_tile_pos(3, 2) + Vector3(0.0, 0.0, 0.0), Color(0.95, 0.72, 0.25))   # tiller
	_bot(_tile_pos(2, 4) + Vector3(0.0, 0.0, 0.0), Color(0.40, 0.62, 0.95))   # waterer

# ---------------------------------------------------------------- builders
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

func _bot(at: Vector3, col: Color) -> void:
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.42, 0.42)
	body.mesh = bm
	body.material_override = _mat(col, 0.4, 0.3)
	body.position = at + Vector3(0, 0.34, 0)
	add_child(body)
	# Head
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.30, 0.18, 0.26)
	head.mesh = hm
	head.material_override = _mat(col.lightened(0.15), 0.4, 0.3)
	head.position = at + Vector3(0, 0.66, 0)
	add_child(head)
	# Eye / lens
	var eye := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.06
	em.height = 0.12
	eye.mesh = em
	var eye_mat := _mat(Color(0.1, 0.9, 0.8), 0.2, 0.9)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.2, 1.0, 0.85)
	eye_mat.emission_energy_multiplier = 2.0
	eye.material_override = eye_mat
	eye.position = at + Vector3(0, 0.66, 0.14)
	add_child(eye)

# Instance a glb, auto-scale so its largest footprint side == target, sit on ground.
func _place_model(scn: PackedScene, at: Vector3, target: float) -> void:
	if scn == null:
		return
	var inst: Node3D = scn.instantiate()
	add_child(inst)
	var ab := _local_aabb(inst)
	var span: float = max(ab.size.x, ab.size.z)
	if span < 0.0001:
		span = max(ab.size.y, 0.0001)
	var s: float = target / span
	inst.scale = Vector3(s, s, s)
	# After scaling, lift so the model's bottom rests at 'at.y'.
	inst.position = at + Vector3(0, -ab.position.y * s, 0)

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

func _jitter(c: int, r: int) -> float:
	return abs(sin(float(c) * 12.9898 + float(r) * 78.233) * 43758.5453)\
		- floor(abs(sin(float(c) * 12.9898 + float(r) * 78.233) * 43758.5453))

# ---------------------------------------------------------------- inspect / shot
func _shoot() -> void:
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://_shot_lowpoly.png")
		get_tree().quit()
	)

func _inspect(path: String) -> void:
	var scn: PackedScene = load(path)
	if scn == null:
		push_error("FAILED to load %s" % path)
		return
	var root := scn.instantiate()
	push_error("=== %s root=%s children=%d ===" % [path, root.name, root.get_child_count()])

