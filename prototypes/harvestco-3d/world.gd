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
var _hud: Hud
var _store: Store
var _buildings: Array = []           # [{node, kind, aabb}] homestead buildings (tappable)
var _bot_nodes: Array = []           # parallel to sim.bots: {root, task, phase, prev}
var _zone_markers: Array = []        # tinted tiles showing the shared bot work area
var _tool: int = -1                  # active tool: -1 = hand (manual farm), 0 = paint work area
# One shared work area for ALL bots. Paint it once; every specialist bot (current
# and future) works inside it autonomously — till, plant, water, harvest in turn.
var _shared_zone: Dictionary = {}
# event visuals (Phase H) — created lazily, shown/hidden by _sync_events from sim state
var _rain: GPUParticles3D
var _ufo: Node3D
var _birds: Node3D
var _trader: Node3D
var _scarecrow: Node3D
var _last_event_seq: int = 0         # toast fires when sim bumps event_seq
# ambient life (always-on, not event-driven): gentle motion so the farm feels alive
var _windmill_hub: Node3D            # spinning windmill blades
var _homestead: Node3D               # container for buildings+scenery, slides back as the field grows
var _props_back_z: float = 0.0       # field back-edge z at build time, to track homestead offset
var _bed: MeshInstance3D             # raised soil bed under the plot (rebuilt on expand)
var _sway: Array = []                # [{node, phase, amp}] trees/bushes that sway in the breeze
var _butterflies: Array = []         # [{node, phase, center, wings:[l,r]}] wandering butterflies
var _amb_t: float = 0.0              # ambient animation clock
var _bird_phase: float = 0.0         # bird wing-flap clock
var _wet: bool = false               # soil is visibly darkened/damp while it rains
var _clouds: Array = []              # [{node, speed}] soft clouds drifting across the sky
var _critters: Array = []            # [{node, center, phase, speed, radius}] wandering chickens
var _smoke: Array = []               # [{node, mat, phase}] chimney smoke puffs
var _smoke_base: Vector3 = Vector3.ZERO  # local origin of the chimney smoke column
var _sfx: Node                       # procedural action sounds (till/plant/water/harvest)
const PICK_Y := 0.10                 # soil surface height for tap raycast
const BOT_SCALE := 1.45              # robots read clearly at the pulled-back camera
const B_FARM := "farm"
const B_WELL := "well"
const B_DEPOT := "depot"
const B_MILL := "mill"

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

	_build_hud()

	# cozy generative background music — synthesized live, no audio assets needed.
	# loaded by path (not class_name) so it works in headless runs without an editor import.
	add_child((load("res://music.gd") as GDScript).new())

	# procedural action sound effects (till/plant/water/harvest) — also loaded by path.
	_sfx = (load("res://sfx.gd") as GDScript).new()
	add_child(_sfx)

	if OS.has_environment("VERIFY_SHOT"):
		_shoot()

# ---------------------------------------------------------------- HUD (Phase F)
func _build_hud() -> void:
	_hud = Hud.new()
	add_child(_hud)
	_hud.build(sim)
	_hud.sell_pressed.connect(_on_sell)
	_hud.buy_water_pressed.connect(_on_buy_water)
	_hud.seed_selected.connect(_on_seed_selected)
	_hud.store_pressed.connect(_on_open_store)
	_hud.tool_selected.connect(_on_tool_selected)
	_hud.clear_zone_pressed.connect(_on_clear_zone)

	_store = Store.new()
	add_child(_store)
	_store.build(sim)
	_store.buy_requested.connect(_on_store_buy)

	_hud.refresh_tools(sim, _tool)

func _on_open_store() -> void:
	_store.open_store(sim, 0)

# Player bought something in the store. Run the sim, react to the result.
func _on_store_buy(id: int) -> void:
	var res: Dictionary = sim.buy_item(id)
	if not res["bought"]:
		_hud.toast("Para yetmiyor")
		return
	# expanding the field adds a row of tiles — rebuild the plot so it shows up
	if res["row"] >= 0:
		_rebuild_field()
	_hud.refresh(sim)
	_store.refresh(sim)
	if res["close"]:
		# a bot was bought — it joins the shared workforce: copy the current work
		# area into it so it works the same zone automatically. We do NOT switch the
		# player into paint mode (that used to block harvesting) — stay in hand mode.
		_store.close_store()
		var nb = sim.bots[sim.bots.size() - 1]
		for k in _shared_zone:
			nb.zone[k] = true
		_hud.refresh_tools(sim, _tool)
		_update_zone_view()
		if _shared_zone.is_empty():
			_hud.toast("Bot geldi - Bolge'ye basip alani boya")
		else:
			_hud.toast("Bot geldi - calisiyor")
	else:
		# upgrades/buildings can change bot count visuals (e.g. repair) — keep tools fresh
		_hud.refresh_tools(sim, _tool)

# Rebuild the entire soil/crop plot after the field grows (buy_expand).
func _rebuild_field() -> void:
	for n in _soil_nodes:
		if n != null:
			n.queue_free()
	for n in _rock_nodes:
		if n != null:
			n.queue_free()
	for n in _crop_nodes:
		if n != null:
			n.queue_free()
	_soil_nodes.clear()
	_rock_nodes.clear()
	_crop_nodes.clear()
	_build_soil_tiles()
	var n2: int = sim.states.size()
	_crop_nodes.resize(n2)
	_last_state = PackedInt32Array(); _last_state.resize(n2)
	_last_bucket = PackedInt32Array(); _last_bucket.resize(n2)
	for i in range(n2):
		_crop_nodes[i] = null
		_last_state[i] = -1
		_last_bucket[i] = -1
		_refresh_crop(i)
	# field grew — slide the homestead back so the buildings stay clear of the plot
	_reposition_homestead()

func _on_sell() -> void:
	var earned: int = sim.sell_all()
	_hud.refresh(sim)
	_hud.toast("Sattin: +%d" % earned if earned > 0 else "Depo bos")

func _on_buy_water() -> void:
	if sim.buy_water():
		_hud.refresh(sim)
		_hud.toast("Su +%d" % sim.WATER_BUNDLE)
	elif sim.water >= sim.WATER_MAX:
		_hud.toast("Su deposu dolu")
	else:
		_hud.toast("Para yetmiyor")

func _on_seed_selected(idx: int) -> void:
	sim.selected_seed = idx
	_hud.refresh(sim)

# Player picked a tool: -1 = hand (manual farm), >=0 = paint that bot's zone.
func _on_tool_selected(idx: int) -> void:
	_tool = idx
	_hud.refresh_tools(sim, _tool)
	_update_zone_view()

# "Temizle" — wipe the whole shared work area (bounded, safe). Bots go idle.
func _on_clear_zone() -> void:
	_shared_zone.clear()
	for bot in sim.bots:
		bot.zone.clear()
	_update_zone_view()

func _process(delta: float) -> void:
	sim.tick(delta)
	# Rebuild a tile when it changes. On a STATE change (till/plant/water/harvest —
	# whether by the player OR a bot) refresh the whole tile so the SOIL COLOUR updates
	# too, not just the plant. On a pure growth-bucket change only the plant needs work.
	for i in range(sim.states.size()):
		var s: int = sim.states[i]
		var bucket: int = int(sim.grow[i] * 6.0)
		if s != _last_state[i]:
			# a bot (or anything other than a direct tap) changed this tile — play its
			# action sound. Manual taps play their own sound in _tap before refreshing.
			if _last_state[i] != -1:
				_play_action_sfx(_last_state[i], s)
			_refresh_tile(i)
		elif bucket != _last_bucket[i]:
			_refresh_crop(i)
	_sync_bots(delta)
	_sync_events(delta)
	_sync_ambient(delta)
	# bots earn/harvest autonomously every frame, so keep the readouts live (depo, para,
	# su) — otherwise the counters look frozen until the player next taps something.
	if _hud != null:
		_hud.refresh(sim)

# ---------------------------------------------------------------- input (Phase C)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_tap(event.position)
	elif event is InputEventScreenDrag:
		_paint_at(event.position, false) # finger drag adds tiles to the zone
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_tap(event.position)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_paint_at(event.position, false) # mouse drag adds tiles (editor testing)

func _tap(screen_pos: Vector2) -> void:
	if _store != null and _store.is_open():
		return
	# buildings sit above the soil plane — check them first
	var kind := _building_under(screen_pos)
	if kind != "":
		_on_building_tapped(kind)
		return
	# paint mode active -> a tap toggles that tile in/out of the work area
	if _tool >= 0:
		_paint_at(screen_pos, true)
		return
	var idx := _tile_under(screen_pos)
	if idx < 0:
		return
	var old_state: int = sim.states[idx]
	var ok: bool = sim.manual(idx)
	if ok:
		if sim.states[idx] != old_state:
			_play_action_sfx(old_state, sim.states[idx])
		elif old_state == SimState.GROWING:
			_play_action_sfx(SimState.PLANTED, SimState.GROWING)  # tending a crop = a water sound
	_refresh_tile(idx)
	_feedback(idx, ok)
	if _hud != null:
		_hud.refresh(sim)

# Edit the shared work zone at the tapped tile. A single tap (toggle=true) flips the
# tile in/out of the zone; a drag (toggle=false) only adds, so sweeping paints an area.
func _paint_at(screen_pos: Vector2, toggle: bool) -> void:
	if _store != null and _store.is_open():
		return
	if _tool < 0 or sim.bots.is_empty():
		return
	var idx := _tile_under(screen_pos)
	if idx < 0:
		return
	# edit the shared work area, then mirror it onto every bot so they all work it
	if toggle and _shared_zone.has(idx):
		_shared_zone.erase(idx)
		for bot in sim.bots:
			bot.zone.erase(idx)
	else:
		if _shared_zone.has(idx):
			return
		_shared_zone[idx] = true
		for bot in sim.bots:
			bot.zone[idx] = true
	_update_zone_view()

# Show the shared work area as soft tinted tiles (only while in paint mode).
const ZONE_COL := Color(0.45, 0.78, 0.95)   # calm cyan accent, not a task colour
func _update_zone_view() -> void:
	for m in _zone_markers:
		if m != null:
			m.queue_free()
	_zone_markers.clear()
	if _tool < 0:
		return
	for key in _shared_zone:
		var i: int = key
		if i >= sim.states.size():
			continue
		var cr := _tile_cr(i)
		var mk := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(TILE * 0.94, 0.02, TILE * 0.94)
		mk.mesh = bm
		var mat := _mat(ZONE_COL, 0.5, 0.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.22
		mat.emission_enabled = true
		mat.emission = ZONE_COL
		mat.emission_energy_multiplier = 0.18
		mk.material_override = mat
		mk.position = _tile_pos(cr.x, cr.y) + Vector3(0, 0.11, 0)
		add_child(mk)
		_zone_markers.append(mk)

# Physics raycast against homestead building bodies. Returns the kind or "".
func _building_under(screen_pos: Vector2) -> String:
	if _cam == null:
		return ""
	var from: Vector3 = _cam.project_ray_origin(screen_pos)
	var to: Vector3 = from + _cam.project_ray_normal(screen_pos) * 100.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return ""
	for b in _buildings:
		if b["body"] == hit.get("collider"):
			return b["kind"]
	return ""

func _on_building_tapped(kind: String) -> void:
	match kind:
		B_WELL:
			_on_buy_water()
		B_DEPOT:
			_on_sell()
		B_FARM:
			_store.open_store(sim, 0)
		B_MILL:
			_store.open_store(sim, 2)

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
# Map a tile state transition to its action sound. Fires for BOTH manual taps and bot
# work, since both go through the same EMPTY->TILLED->PLANTED->GROWING->RIPE lifecycle.
func _play_action_sfx(old_state: int, new_state: int) -> void:
	if _sfx == null:
		return
	if old_state == SimState.OBSTACLE and new_state == SimState.EMPTY:
		_sfx.play("clean")
	elif old_state == SimState.EMPTY and new_state == SimState.TILLED:
		_sfx.play("till")
	elif old_state == SimState.TILLED and new_state == SimState.PLANTED:
		_sfx.play("plant")
	elif old_state == SimState.PLANTED and new_state == SimState.GROWING:
		_sfx.play("water")
	elif old_state == SimState.RIPE and new_state == SimState.EMPTY:
		_sfx.play("harvest")

func _refresh_tile(idx: int) -> void:
	var soil: MeshInstance3D = _soil_nodes[idx]
	if soil != null:
		var col: Color = _soil_color(sim.states[idx])
		if _wet:
			col = col.darkened(0.24)   # rain soaks the soil dark
		soil.material_override = _mat(col, 0.55 if _wet else 1.0)  # damp sheen while raining
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

# Grid-space (col,row floats) -> 3D world position. Bots live in grid space (sim).
func _grid_to_world(g: Vector2) -> Vector3:
	return _origin() + Vector3(g.x * TILE, 0.0, g.y * TILE)

# ---------------------------------------------------------------- bots (Phase D)
# Spawn a view node for any new sim bot, then drive every bot's transform from its
# grid position each frame (the sim already moves gpos; we just render + animate).
func _sync_bots(delta: float) -> void:
	while _bot_nodes.size() < sim.bots.size():
		var i: int = _bot_nodes.size()
		var bot = sim.bots[i]
		var node := _make_bot(bot.task)
		add_child(node)
		node.position = _grid_to_world(bot.gpos)
		_bot_nodes.append({"root": node, "task": bot.task, "phase": 0.0})

	for i in range(sim.bots.size()):
		var bot = sim.bots[i]
		var nd: Dictionary = _bot_nodes[i]
		var root: Node3D = nd["root"]
		var ground := _grid_to_world(bot.gpos)
		var prev := root.position
		# face travel direction
		var move := Vector2(ground.x - prev.x, ground.z - prev.z)
		if move.length() > 0.0008:
			var ang := atan2(move.x, move.y)
			root.rotation.y = lerp_angle(root.rotation.y, ang, min(1.0, delta * 9.0))
		# a little working bob; rolls to a stop when moving
		var y := 0.0
		if bot.state == "working":
			nd["phase"] = float(nd["phase"]) + delta * 11.0
			y = absf(sin(float(nd["phase"]))) * 0.09
		else:
			nd["phase"] = 0.0
		root.position = Vector3(ground.x, y, ground.z)
		# shrink a touch when worn out (condition low), else full size
		if bot.condition < 0.35:
			root.scale = Vector3.ONE * BOT_SCALE * (0.9 + bot.condition * 0.1)
		else:
			root.scale = Vector3.ONE * BOT_SCALE

# A cute low-poly farm robot. Task colour shows on the belly panel, eyes, and antenna
# bulb so each specialist reads at a glance (matches the store swatches).
func _make_bot(task: int) -> Node3D:
	var accent: Color = sim.TASK_COL[task]
	var root := Node3D.new()

	var dark := Color(0.15, 0.16, 0.21)
	# the body wears a soft pastel of the task colour so each bot reads its job at a
	# glance; the head stays light for a friendly face that contrasts the coloured body.
	var body_col: Color = accent

	# smooth rounded hover-base (a soft disc instead of a boxy tracked chassis)
	var base := MeshInstance3D.new()
	var basem := CylinderMesh.new()
	basem.top_radius = 0.19; basem.bottom_radius = 0.23; basem.height = 0.12; basem.radial_segments = 18
	base.mesh = basem
	base.material_override = _mat(dark, 0.45, 0.25)
	base.position = Vector3(0, 0.10, 0)
	root.add_child(base)
	# glowing accent band wrapping the base — colour-codes the specialist
	var band := MeshInstance3D.new()
	var bandm := CylinderMesh.new()
	bandm.top_radius = 0.235; bandm.bottom_radius = 0.235; bandm.height = 0.045; bandm.radial_segments = 18
	band.mesh = bandm
	var bandmat := _mat(accent, 0.3, 0.0)
	bandmat.emission_enabled = true; bandmat.emission = accent; bandmat.emission_energy_multiplier = 0.8
	band.material_override = bandmat
	band.position = Vector3(0, 0.135, 0)
	root.add_child(band)

	# smooth capsule body, cream — rounded and friendly
	var body := MeshInstance3D.new()
	var bodym := CapsuleMesh.new()
	bodym.radius = 0.195; bodym.height = 0.50; bodym.radial_segments = 18; bodym.rings = 10
	body.mesh = bodym
	body.material_override = _mat(body_col, 0.4, 0.05)
	body.position = Vector3(0, 0.42, 0)
	root.add_child(body)

	# task-colour glowing belly orb (a cute round indicator)
	var belly := MeshInstance3D.new()
	var bem := SphereMesh.new()
	bem.radius = 0.085; bem.height = 0.17; bem.radial_segments = 14; bem.rings = 9
	belly.mesh = bem
	var belly_col: Color = accent.lightened(0.55)
	var bmat := _mat(belly_col, 0.3, 0.0)
	bmat.emission_enabled = true; bmat.emission = belly_col; bmat.emission_energy_multiplier = 0.9
	belly.material_override = bmat
	belly.position = Vector3(0, 0.40, 0.165)
	root.add_child(belly)

	# domed head + curved dark visor + two glowing eyes
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.165; hm.height = 0.30; hm.radial_segments = 18; hm.rings = 11
	head.mesh = hm
	head.material_override = _mat(accent.lightened(0.3), 0.4, 0.05)
	head.position = Vector3(0, 0.70, 0)
	root.add_child(head)
	var visor := MeshInstance3D.new()
	var vm := SphereMesh.new()
	vm.radius = 0.14; vm.height = 0.28; vm.radial_segments = 18; vm.rings = 9
	visor.mesh = vm
	visor.material_override = _mat(Color(0.09, 0.11, 0.16), 0.1, 0.5)
	visor.scale = Vector3(1.0, 0.5, 0.72)
	visor.position = Vector3(0, 0.71, 0.07)
	root.add_child(visor)
	for ex in [-0.05, 0.05]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.025; em.height = 0.05; em.radial_segments = 10; em.rings = 6
		eye.mesh = em
		var emat := _mat(accent, 0.2, 0.0)
		emat.emission_enabled = true; emat.emission = accent.lightened(0.35); emat.emission_energy_multiplier = 3.0
		eye.material_override = emat
		eye.position = Vector3(ex, 0.715, 0.155)
		root.add_child(eye)

	# slim antenna + task-colour bulb
	var ant := MeshInstance3D.new()
	var am := CylinderMesh.new()
	am.top_radius = 0.008; am.bottom_radius = 0.012; am.height = 0.14; am.radial_segments = 6
	ant.mesh = am
	ant.material_override = _mat(Color(0.30, 0.30, 0.32), 0.5, 0.3)
	ant.position = Vector3(0.0, 0.90, 0.0)
	root.add_child(ant)
	var bulb := MeshInstance3D.new()
	var blm := SphereMesh.new()
	blm.radius = 0.035; blm.height = 0.07; blm.radial_segments = 10; blm.rings = 6
	bulb.mesh = blm
	var blmat := _mat(accent, 0.2, 0.0)
	blmat.emission_enabled = true; blmat.emission = accent; blmat.emission_energy_multiplier = 2.2
	bulb.material_override = blmat
	bulb.position = Vector3(0, 0.99, 0)
	root.add_child(bulb)

	# two rounded little arms (short capsules, angled outward)
	for sx in [-0.2, 0.2]:
		var arm := MeshInstance3D.new()
		var arm_m := CapsuleMesh.new()
		arm_m.radius = 0.042; arm_m.height = 0.19; arm_m.radial_segments = 10; arm_m.rings = 4
		arm.mesh = arm_m
		arm.material_override = _mat(body_col.darkened(0.08), 0.45, 0.05)
		arm.rotation_degrees = Vector3(0, 0, 20 if sx > 0 else -20)
		arm.position = Vector3(sx, 0.42, 0.03)
		root.add_child(arm)

	root.scale = Vector3.ONE * BOT_SCALE
	return root

# ---------------------------------------------------------------- events (Phase H)
# The field is centred on the world origin (_origin() is symmetric), so the field
# centre is ~Vector3.ZERO; half-extents come straight from the grid dimensions.
func _field_half() -> Vector2:
	return Vector2((SimState.COLS - 1) * TILE * 0.5, (sim.rows - 1) * TILE * 0.5)

# Reads sim event state each frame and drives every event visual. Pure view: it never
# changes the sim — sim.tick already advanced the events; we just show what's happening.
func _sync_events(delta: float) -> void:
	if sim.event_seq != _last_event_seq:
		_last_event_seq = sim.event_seq
		if _hud:
			_hud.toast(sim.event_msg)
	_sync_rain()
	_sync_ufo(delta)
	_sync_birds(delta)
	_sync_trader()
	_sync_scarecrow()

func _sync_rain() -> void:
	var on: bool = sim.rain_t > 0.0
	if on and _rain == null:
		_rain = _make_rain()
		add_child(_rain)
	if _rain:
		_rain.emitting = on
		_rain.visible = on
	# darken every tile while it rains, restore when it stops (toggle on transitions)
	if on != _wet:
		_wet = on
		for i in range(_soil_nodes.size()):
			_refresh_tile(i)

func _sync_ufo(delta: float) -> void:
	if not sim.ufo_active:
		if _ufo:
			_ufo.visible = false
		return
	if _ufo == null:
		_ufo = _make_ufo()
		add_child(_ufo)
	_ufo.visible = true
	var f: float = clamp(sim.ufo_t / SimState.UFO_DUR, 0.0, 1.0)
	var half := _field_half()
	var x: float = lerp(-half.x - 3.0, half.x + 3.0, f)
	# hover over the target tile's z while it works the crop-circle, otherwise mid-field
	var tz := 0.0
	if sim.ufo_target >= 0:
		tz = _tile_pos(sim.ufo_target % SimState.COLS, sim.ufo_target / SimState.COLS).z
	_ufo.position = Vector3(x, 4.6, tz)
	_ufo.rotate_y(delta * 2.5)

func _sync_birds(delta: float) -> void:
	if not sim.birds_active:
		if _birds:
			_birds.visible = false
		return
	if _birds == null:
		_birds = _make_birds()
		add_child(_birds)
	_birds.visible = true
	var f: float = clamp(sim.birds_t / SimState.BIRDS_DUR, 0.0, 1.0)
	var half := _field_half()
	var x: float = lerp(-half.x - 4.0, half.x + 4.0, f)
	var y: float = 4.2 - sin(f * PI) * 2.3   # dip toward the crops at mid-flight, stay readable
	_birds.position = Vector3(x, y, 0.0)
	_birds.rotation.y = -PI * 0.5   # face the flock along its travel direction (+x)
	# flap each bird's wings smoothly. Time-based (not per-frame) so the speed is the
	# same at any framerate; each bird offset by its own stored phase so they're not
	# all synced. Wings pivot from the shoulder hinge, sweeping down-to-up.
	_bird_phase += delta * 9.0
	for b in _birds.get_children():
		var bird_phase: float = b.get_meta("phase", 0.0)
		var flap: float = sin(_bird_phase + bird_phase)
		var raise: float = 0.35 + flap * 0.55   # ~ -0.2 .. +0.9 rad
		var wings: Array = b.get_meta("wings", [])
		if wings.size() == 2:
			wings[0].rotation.z = raise     # left shoulder
			wings[1].rotation.z = -raise    # right shoulder

# Always-on ambient life: windmill spin, breeze sway on foliage, drifting butterflies.
func _sync_ambient(delta: float) -> void:
	_amb_t += delta
	if _windmill_hub != null:
		_windmill_hub.rotation.z += delta * 0.7
	for s in _sway:
		var node: Node3D = s["node"]
		node.rotation.z = sin(_amb_t * 1.1 + s["phase"]) * s["amp"]
	for bf in _butterflies:
		var node: Node3D = bf["node"]
		var ph: float = bf["phase"]
		var c: Vector3 = bf["center"]
		# lazy figure-eight drift around the patch centre, gentle bob
		node.position = c + Vector3(
				sin(_amb_t * 0.7 + ph) * 1.1,
				sin(_amb_t * 2.3 + ph) * 0.22,
				cos(_amb_t * 0.5 + ph) * 0.9)
		# face travel direction so it banks through the turns
		node.rotation.y = _amb_t * 0.5 + ph
		var fl: float = 0.7 + sin(_amb_t * 14.0 + ph) * 0.7   # rapid wing flutter
		var wings: Array = bf["wings"]
		wings[0].rotation.z = fl
		wings[1].rotation.z = -fl
	# clouds drift slowly across the sky and wrap around when they leave the frame
	for cl in _clouds:
		var node: Node3D = cl["node"]
		node.position.x += cl["speed"] * delta
		if node.position.x > 14.0:
			node.position.x = -14.0
	# chimney smoke: each puff rises, swells and fades on its own looping phase
	for sm in _smoke:
		var node: Node3D = sm["node"]
		var t: float = fmod(_amb_t * 0.35 + sm["phase"], 1.0)
		node.position = _smoke_base + Vector3(sin(t * 6.0 + sm["phase"] * 9.0) * 0.18, t * 1.7, 0.0)
		var sc: float = 0.5 + t * 1.4
		node.scale = Vector3(sc, sc, sc)
		var mat: StandardMaterial3D = sm["mat"]
		mat.albedo_color.a = (1.0 - t) * 0.5
	# chickens wander in lazy loops, hop a little, and face the way they're walking
	for cr in _critters:
		var node2: Node3D = cr["node"]
		var c: Vector3 = cr["center"]
		var ph2: float = cr["phase"]
		var sp: float = cr["speed"]
		var rad: float = cr["radius"]
		var a: float = _amb_t * sp + ph2
		var p0 := c + Vector3(cos(a) * rad, 0.0, sin(a * 0.8) * rad * 0.7)
		var a1: float = a + 0.08
		var p1 := c + Vector3(cos(a1) * rad, 0.0, sin(a1 * 0.8) * rad * 0.7)
		var hop: float = abs(sin(_amb_t * 6.0 + ph2)) * 0.05
		node2.position = p0 + Vector3(0.0, hop, 0.0)
		var head := p1 - p0
		if head.length() > 0.0001:
			node2.rotation.y = atan2(head.x, head.z)
		node2.rotation.x = sin(_amb_t * 5.0 + ph2) * 0.12   # gentle pecking bob

func _sync_trader() -> void:
	var on: bool = sim.sell_boost_t > 0.0
	if not on:
		if _trader:
			_trader.visible = false
		return
	if _trader == null:
		_trader = _make_trader()
		var half := _field_half()
		# park it in front of the plot (toward the camera) so it's clearly in frame
		_trader.position = Vector3(-1.6, 0.0, half.y + 2.0)
		add_child(_trader)
	_trader.visible = true

func _sync_scarecrow() -> void:
	var on: bool = sim.scarecrow_charges > 0
	if not on:
		if _scarecrow:
			_scarecrow.visible = false
		return
	if _scarecrow == null:
		_scarecrow = _make_scarecrow()
		# stand it on a front-corner tile so it's close to the camera and clearly readable
		_scarecrow.position = _tile_pos(0, sim.rows - 1)
		add_child(_scarecrow)
	_scarecrow.visible = true

# slanted blue raindrop streaks falling over the whole field (preprocess so a single
# headless frame already shows rain).
func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.position = Vector3(0.0, 5.0, 0.0)
	p.amount = 240
	p.lifetime = 1.1
	p.preprocess = 1.0
	var half := _field_half()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.1, -1.0, 0.0)
	mat.spread = 2.0
	mat.gravity = Vector3(0.0, -26.0, 0.0)
	mat.initial_velocity_min = 6.0
	mat.initial_velocity_max = 9.0
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(half.x + 1.5, 0.2, half.y + 1.5)
	p.process_material = mat
	var drop := BoxMesh.new()
	drop.size = Vector3(0.035, 0.42, 0.035)
	var dmat := _mat(Color(0.62, 0.80, 1.0, 0.65))
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = dmat
	p.draw_pass_1 = drop
	return p

func _make_ufo() -> Node3D:
	var root := Node3D.new()
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.45; dm.bottom_radius = 1.15; dm.height = 0.3
	disc.mesh = dm
	disc.material_override = _mat(Color(0.55, 0.58, 0.66), 0.25, 0.85)
	root.add_child(disc)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.5; sm.height = 0.7
	dome.mesh = sm; dome.position.y = 0.22
	var glass := _mat(Color(0.45, 0.95, 0.6, 0.7))
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.emission_enabled = true
	glass.emission = Color(0.35, 1.0, 0.5)
	glass.emission_energy_multiplier = 1.6
	dome.material_override = glass
	root.add_child(dome)
	# glowing under-belly lights
	for a in range(6):
		var ang: float = TAU * float(a) / 6.0
		var light := MeshInstance3D.new()
		var ls := SphereMesh.new(); ls.radius = 0.1; ls.height = 0.2
		light.mesh = ls
		light.position = Vector3(cos(ang) * 0.9, -0.12, sin(ang) * 0.9)
		var lm := _mat(Color(1.0, 0.9, 0.3))
		lm.emission_enabled = true; lm.emission = Color(1.0, 0.85, 0.2); lm.emission_energy_multiplier = 2.0
		light.material_override = lm
		root.add_child(light)
	# abduction beam
	var beam := MeshInstance3D.new()
	var cone := CylinderMesh.new(); cone.top_radius = 0.25; cone.bottom_radius = 1.5; cone.height = 4.2
	beam.mesh = cone; beam.position.y = -2.3
	var bm := _mat(Color(0.4, 1.0, 0.5, 0.22))
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.emission_enabled = true; bm.emission = Color(0.4, 1.0, 0.5); bm.emission_energy_multiplier = 1.0
	beam.material_override = bm
	root.add_child(beam)
	return root

func _make_birds() -> Node3D:
	var root := Node3D.new()
	var dark := _mat(Color(0.13, 0.13, 0.16), 0.8, 0.0)
	for k in range(SimState.BIRD_COUNT):
		var b := Node3D.new()
		b.position = Vector3(randf_range(-1.8, 1.8), randf_range(-0.6, 0.6), randf_range(-1.8, 1.8))
		b.set_meta("phase", float(k) * 1.1)   # de-sync the flock's flapping
		# a small rounded body so the bird reads as more than two flat wings
		var body := MeshInstance3D.new()
		var bodym := SphereMesh.new(); bodym.radius = 0.10; bodym.height = 0.20
		body.mesh = bodym
		body.scale = Vector3(0.9, 0.8, 1.8)   # elongated head-to-tail
		body.material_override = dark
		b.add_child(body)
		# each wing pivots from a shoulder hinge at the body, mesh offset outward so it
		# sweeps like a real wing instead of spinning around its own middle.
		var wings: Array = []
		for s in [-1.0, 1.0]:
			var hinge := Node3D.new()
			b.add_child(hinge)
			var w := MeshInstance3D.new()
			var wm := BoxMesh.new(); wm.size = Vector3(0.5, 0.035, 0.24)
			w.mesh = wm
			w.material_override = dark
			w.position = Vector3(s * 0.28, 0.0, 0.0)
			hinge.add_child(w)
			wings.append(hinge)
		b.set_meta("wings", wings)
		root.add_child(b)
	return root

func _make_trader() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(1.1, 0.6, 0.8)
	body.mesh = bm; body.position.y = 0.55
	body.material_override = _mat(Color(0.55, 0.35, 0.18), 0.7)
	root.add_child(body)
	# striped canopy
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new(); tm.size = Vector3(1.25, 0.16, 0.95)
	top.mesh = tm; top.position.y = 0.95
	top.material_override = _mat(Color(0.85, 0.25, 0.25), 0.6)
	root.add_child(top)
	# goods crate (glowing accent so the boost reads at a glance)
	var crate := MeshInstance3D.new()
	var cm := BoxMesh.new(); cm.size = Vector3(0.3, 0.3, 0.3)
	crate.mesh = cm; crate.position = Vector3(0.0, 0.95 + 0.23, 0.0)
	var gold := _mat(Color(1.0, 0.84, 0.3))
	gold.emission_enabled = true; gold.emission = Color(1.0, 0.8, 0.25); gold.emission_energy_multiplier = 1.2
	crate.material_override = gold
	root.add_child(crate)
	for wz in [-0.32, 0.32]:
		for wx in [-0.45, 0.45]:
			var wheel := MeshInstance3D.new()
			var whm := CylinderMesh.new(); whm.top_radius = 0.22; whm.bottom_radius = 0.22; whm.height = 0.1
			wheel.mesh = whm
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(wx, 0.22, wz)
			wheel.material_override = _mat(Color(0.15, 0.12, 0.1))
			root.add_child(wheel)
	return root

# Detailed cozy scarecrow: weathered cross frame, stuffed burlap body with straw
# tufts bursting from the cuffs and hem, a stitched sack head, a floppy straw hat,
# and a little crow perched on one arm.
func _make_scarecrow() -> Node3D:
	var root := Node3D.new()
	var wood := Color(0.42, 0.28, 0.15)
	var straw := Color(0.86, 0.68, 0.28)
	var burlap := Color(0.74, 0.55, 0.32)
	var shirt := Color(0.55, 0.30, 0.28)   # faded plaid red

	# --- weathered wooden cross frame ---
	var post := _cyl_node(wood, 0.055, 1.75, 6)
	post.position.y = 0.875
	post.rotation.z = 0.04   # slight lean, looks hand-made
	root.add_child(post)
	var arms := _cyl_node(wood, 0.045, 1.5, 6)
	arms.rotation.z = PI * 0.5
	arms.position.y = 1.18
	root.add_child(arms)

	# --- stuffed burlap torso (a sack cinched at the waist) ---
	var torso := _ball_node(shirt, 0.30, 0.9, 8)
	torso.scale = Vector3(0.85, 1.25, 0.7)
	torso.position.y = 0.95
	root.add_child(torso)
	# rope belt
	var belt := _cyl_node(Color(0.5, 0.4, 0.2), 0.27, 0.08, 8)
	belt.position.y = 0.72
	belt.scale = Vector3(0.95, 1.0, 0.75)
	root.add_child(belt)
	# a stitched patch on the chest
	var patch := MeshInstance3D.new()
	var patm := BoxMesh.new(); patm.size = Vector3(0.16, 0.16, 0.02)
	patch.mesh = patm
	patch.material_override = _mat(Color(0.40, 0.55, 0.40), 0.95)
	patch.position = Vector3(-0.1, 1.0, 0.21)
	root.add_child(patch)

	# --- sleeves along the arms, with straw bursting from the cuffs ---
	for s in [-1.0, 1.0]:
		var sleeve := _cyl_node(shirt, 0.075, 0.62, 6)
		sleeve.rotation.z = PI * 0.5
		sleeve.position = Vector3(s * 0.42, 1.18, 0.0)
		root.add_child(sleeve)
		# straw cuff tufts (three little cones pointing outward)
		for t in range(3):
			var tuft := _cone_node(straw, 0.06, 0.22, 5)
			tuft.rotation.z = s * (PI * 0.5) + (float(t) - 1.0) * 0.4
			tuft.position = Vector3(s * 0.74, 1.18 + (float(t) - 1.0) * 0.06, 0.0)
			root.add_child(tuft)

	# --- straw bursting from the hem at the bottom ---
	for h in range(5):
		var ang: float = TAU * float(h) / 5.0
		var leg := _cone_node(straw, 0.06, 0.30, 5)
		leg.rotation.x = PI   # point down
		leg.position = Vector3(cos(ang) * 0.14, 0.58, sin(ang) * 0.10)
		root.add_child(leg)

	# --- stitched burlap sack head ---
	var head := _ball_node(burlap, 0.20, 0.95, 8)
	head.scale = Vector3(1.0, 1.1, 1.0)
	head.position.y = 1.50
	root.add_child(head)
	# cinch at the neck
	var neck := _cyl_node(Color(0.5, 0.4, 0.2), 0.09, 0.06, 6)
	neck.position.y = 1.34
	root.add_child(neck)
	# straw fringe poking out under the head
	for f in range(4):
		var fa: float = TAU * float(f) / 4.0 + 0.4
		var fr := _cone_node(straw, 0.035, 0.14, 4)
		fr.rotation.x = PI * 0.8
		fr.position = Vector3(cos(fa) * 0.14, 1.36, sin(fa) * 0.12)
		root.add_child(fr)
	# stitched X eyes + a button nose
	var dark := _mat(Color(0.15, 0.1, 0.08), 0.9)
	for s2 in [-1.0, 1.0]:
		for d in [-1.0, 1.0]:
			var st := MeshInstance3D.new()
			var stm := BoxMesh.new(); stm.size = Vector3(0.07, 0.012, 0.012)
			st.mesh = stm
			st.material_override = dark
			st.rotation.z = d * 0.8
			st.position = Vector3(s2 * 0.085, 1.53, 0.19)
			root.add_child(st)
	var nose := _ball_node(Color(0.2, 0.5, 0.25), 0.03, 0.5, 6)
	nose.position = Vector3(0.0, 1.47, 0.20)
	root.add_child(nose)

	# --- floppy straw hat: wide brim disc + cone crown + band ---
	var brim := _cyl_node(Color(0.80, 0.62, 0.26), 0.40, 0.04, 10)
	brim.position.y = 1.66
	brim.rotation.x = 0.06   # tilted, jaunty
	root.add_child(brim)
	var crown := _cone_node(Color(0.84, 0.66, 0.30), 0.24, 0.30, 8)
	crown.position.y = 1.80
	root.add_child(crown)
	var band := _cyl_node(Color(0.45, 0.30, 0.16), 0.245, 0.05, 10)
	band.position.y = 1.69
	root.add_child(band)

	# --- a cheeky little crow perched on the right arm ---
	var crow := Node3D.new()
	crow.position = Vector3(0.62, 1.27, 0.0)
	var crow_dark := _mat(Color(0.12, 0.12, 0.15), 0.7)
	var cbody := _ball_node(Color(0.12, 0.12, 0.15), 0.07, 0.7, 6)
	cbody.scale = Vector3(1.0, 1.0, 1.6)
	cbody.material_override = crow_dark
	crow.add_child(cbody)
	var chead := _ball_node(Color(0.12, 0.12, 0.15), 0.045, 0.7, 6)
	chead.material_override = crow_dark
	chead.position = Vector3(0.0, 0.06, 0.09)
	crow.add_child(chead)
	var cbeak := _cone_node(Color(0.9, 0.7, 0.2), 0.02, 0.06, 4)
	cbeak.rotation.x = PI * 0.5
	cbeak.position = Vector3(0.0, 0.06, 0.15)
	crow.add_child(cbeak)
	root.add_child(crow)
	return root

# ---------------------------------------------------------------- build
func _build_soil_tiles() -> void:
	var n: int = sim.states.size()
	_soil_nodes.resize(n)
	_rock_nodes.resize(n)
	# Raised soil bed under the plot (freed + rebuilt on expand so it doesn't stack up).
	if _bed != null:
		_bed.queue_free()
	var bed := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SimState.COLS * TILE + 0.4, 0.18, sim.rows * TILE + 0.4)
	bed.mesh = bm
	bed.material_override = _mat(Color(0.28, 0.19, 0.12), 1.0)
	bed.position = Vector3(0, -0.04, 0)
	add_child(bed)
	_bed = bed

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
	# growth scale: a sprout at PLANTED, ramps through GROWING, full size at RIPE.
	var gs: float
	match s:
		SimState.PLANTED:
			gs = 0.30
		SimState.GROWING:
			gs = 0.40 + grow_f * 0.60
		_:
			gs = 1.0
	var is_gold: bool = s == SimState.RIPE and bool(sim.golden[i])
	_build_crop(holder, sim.crop_type[i], s, gs, is_gold)

# ---- per-crop procedural plants ----------------------------------------------
# Each crop reads as itself (beet bulb, tomato vine, wheat stalks, melon on the
# ground, ...) instead of a generic stem+blob. The leafy body scales with growth;
# the signature fruit only appears at RIPE (gold + emissive on golden tiles).
const LEAF_COL := Color(0.31, 0.53, 0.24)
const LEAF_DARK := Color(0.21, 0.40, 0.19)
const WOOD_COL := Color(0.46, 0.33, 0.21)

func _build_crop(holder: Node3D, ct: int, s: int, gs: float, is_gold: bool) -> void:
	var ripe: bool = s == SimState.RIPE
	match ct:
		0: _crop_beet(holder, gs, ripe, is_gold)
		1: _crop_potato(holder, gs, ripe, is_gold)
		2: _crop_tomato(holder, gs, ripe, is_gold)
		3: _crop_wheat(holder, gs, ripe, is_gold)
		4: _crop_squash(holder, gs, ripe, is_gold)
		5: _crop_grapes(holder, gs, ripe, is_gold)
		6: _crop_watermelon(holder, gs, ripe, is_gold)
		_: _crop_beet(holder, gs, ripe, is_gold)

func _cone_node(col: Color, base_r: float, h: float, segs: int = 6) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = base_r
	cm.height = h
	cm.radial_segments = segs
	m.mesh = cm
	m.material_override = _mat(col, 0.85)
	return m

func _ball_node(col: Color, r: float, rough: float = 0.55, segs: int = 8) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segs
	sm.rings = 5
	m.mesh = sm
	m.material_override = _mat(col, rough)
	return m

func _cyl_node(col: Color, r: float, h: float, segs: int = 5) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	m.mesh = cm
	m.material_override = _mat(col, 0.8)
	return m

func _fruit_mat(col: Color, is_gold: bool) -> StandardMaterial3D:
	var m := _mat(Color(0.97, 0.78, 0.18) if is_gold else col, 0.4, 0.0)
	if is_gold:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.84, 0.22)
		m.emission_energy_multiplier = 2.0
	return m

# A fan of upright leaves around the centre — the green top of root crops.
func _leaf_fan(holder: Node3D, count: int, spread: float, h: float, col: Color, base_y: float) -> void:
	for k in count:
		var ang: float = TAU * float(k) / float(count)
		var leaf := _cone_node(col, h * 0.16, h)
		leaf.rotation = Vector3(deg_to_rad(26.0), ang, 0.0)
		leaf.position = Vector3(cos(ang) * spread, base_y + h * 0.42, sin(ang) * spread)
		holder.add_child(leaf)

func _crop_beet(holder: Node3D, gs: float, ripe: bool, is_gold: bool) -> void:
	var h: float = 0.34 * gs
	_leaf_fan(holder, 6, 0.05 * gs, h, LEAF_COL, 0.02)
	if ripe:
		var col: Color = sim.CROPS[0]["col"]
		var bulb := _ball_node(col, 0.16)
		bulb.material_override = _fruit_mat(col, is_gold)
		bulb.scale = Vector3(1.0, 0.85, 1.0)
		bulb.position = Vector3(0, 0.10, 0)
		holder.add_child(bulb)

func _crop_potato(holder: Node3D, gs: float, ripe: bool, is_gold: bool) -> void:
	var bush_h: float = 0.26 * gs
	var clumps := [Vector3(0, 0, 0), Vector3(0.10, 0.04, 0.06), Vector3(-0.09, 0.02, -0.07), Vector3(0.05, 0.06, -0.09)]
	for k in clumps.size():
		var c: Vector3 = clumps[k]
		var clump := _ball_node(LEAF_COL if k % 2 == 0 else LEAF_DARK, 0.11 * gs, 0.7)
		clump.position = Vector3(c.x, bush_h + c.y, c.z)
		holder.add_child(clump)
	if ripe:
		var col: Color = sim.CROPS[1]["col"]
		for p in [Vector3(0.12, 0.05, 0.0), Vector3(-0.10, 0.05, 0.08), Vector3(0.02, 0.05, -0.12)]:
			var tuber := _ball_node(col, 0.075, 0.7)
			tuber.material_override = _fruit_mat(col, is_gold)
			tuber.scale = Vector3(1.2, 0.8, 1.0)
			tuber.position = p
			holder.add_child(tuber)

func _crop_tomato(holder: Node3D, gs: float, ripe: bool, is_gold: bool) -> void:
	var h: float = 0.55 * gs
	var stake := _cyl_node(WOOD_COL, 0.018, h)
	stake.position = Vector3(0, h * 0.5, 0)
	holder.add_child(stake)
	for fy in [0.35, 0.62, 0.85]:
		var clump := _ball_node(LEAF_COL, 0.14 * gs, 0.7)
		clump.position = Vector3(0, h * fy, 0)
		holder.add_child(clump)
	if ripe:
		var col: Color = sim.CROPS[2]["col"]
		var spots := [Vector3(0.12, h * 0.45, 0.04), Vector3(-0.11, h * 0.55, -0.05), Vector3(0.06, h * 0.66, 0.11), Vector3(-0.04, h * 0.40, -0.10)]
		for p in spots:
			var t := _ball_node(col, 0.072, 0.35)
			t.material_override = _fruit_mat(col, is_gold)
			t.position = p
			holder.add_child(t)

func _crop_wheat(holder: Node3D, gs: float, ripe: bool, is_gold: bool) -> void:
	var h: float = 0.62 * gs
	var stalk_col: Color = Color(0.83, 0.72, 0.32) if ripe else Color(0.62, 0.70, 0.34)
	var offs := [Vector2(0, 0), Vector2(0.07, 0.05), Vector2(-0.06, 0.05), Vector2(0.05, -0.07), Vector2(-0.07, -0.04), Vector2(0.0, 0.09)]
	var col: Color = sim.CROPS[3]["col"]
	for o in offs:
		var stalk := _cyl_node(stalk_col, 0.012, h, 4)
		stalk.rotation = Vector3(o.y * 0.6, 0, -o.x * 0.6)
		stalk.position = Vector3(o.x, h * 0.5, o.y)
		holder.add_child(stalk)
		if ripe:
			var head := _ball_node(col, 0.055, 0.6, 6)
			head.material_override = _fruit_mat(col, is_gold)
			head.scale = Vector3(0.7, 1.6, 0.7)
			head.position = Vector3(o.x, h + 0.05, o.y)
			holder.add_child(head)

func _crop_squash(holder: Node3D, gs: float, ripe: bool, is_gold: bool) -> void:
	for k in 5:
		var ang: float = TAU * float(k) / 5.0
		var leaf := _ball_node(LEAF_COL if k % 2 == 0 else LEAF_DARK, 0.20 * gs, 0.8)
		leaf.scale = Vector3(1.3, 0.25, 1.0)
		leaf.position = Vector3(cos(ang) * 0.18, 0.06, sin(ang) * 0.18)
		holder.add_child(leaf)
	if ripe:
		var col: Color = sim.CROPS[4]["col"]
		var pump := _ball_node(col, 0.24, 0.45)
		pump.material_override = _fruit_mat(col, is_gold)
		pump.scale = Vector3(1.15, 0.8, 1.15)
		pump.position = Vector3(0.04, 0.18, 0.04)
		holder.add_child(pump)
		var stub := _cyl_node(Color(0.40, 0.32, 0.16), 0.02, 0.08)
		stub.position = Vector3(0.04, 0.34, 0.04)
		holder.add_child(stub)

func _crop_grapes(holder: Node3D, gs: float, ripe: bool, is_gold: bool) -> void:
	var h: float = 0.50 * gs
	var post := _cyl_node(WOOD_COL, 0.02, h)
	post.position = Vector3(0, h * 0.5, 0)
	holder.add_child(post)
	var bar := _cyl_node(WOOD_COL, 0.014, 0.34)
	bar.rotation = Vector3(0, 0, deg_to_rad(90))
	bar.position = Vector3(0, h, 0)
	holder.add_child(bar)
	for lx in [-0.13, 0.13]:
		var leaf := _ball_node(LEAF_COL, 0.10 * gs, 0.7)
		leaf.scale = Vector3(1.2, 0.5, 1.2)
		leaf.position = Vector3(lx, h, 0)
		holder.add_child(leaf)
	if ripe:
		for cx in [-0.12, 0.12]:
			_grape_cluster(holder, Vector3(cx, h - 0.06, 0.0), is_gold)

func _grape_cluster(holder: Node3D, top: Vector3, is_gold: bool) -> void:
	var col: Color = sim.CROPS[5]["col"]
	var rows := [3, 2, 2, 1]
	for r in rows.size():
		var n: int = rows[r]
		for k in n:
			var berry := _ball_node(col, 0.038, 0.3, 6)
			berry.material_override = _fruit_mat(col, is_gold)
			var bx: float = top.x + (float(k) - float(n - 1) * 0.5) * 0.05
			berry.position = Vector3(bx, top.y - float(r) * 0.05, top.z)
			holder.add_child(berry)

func _crop_watermelon(holder: Node3D, gs: float, ripe: bool, is_gold: bool) -> void:
	for k in 4:
		var ang: float = TAU * float(k) / 4.0 + 0.6
		var leaf := _ball_node(LEAF_DARK if k % 2 == 1 else LEAF_COL, 0.13 * gs, 0.8)
		leaf.scale = Vector3(1.2, 0.22, 0.9)
		leaf.position = Vector3(cos(ang) * 0.20, 0.05, sin(ang) * 0.20)
		holder.add_child(leaf)
	if ripe:
		var col: Color = sim.CROPS[6]["col"]
		var melon := _ball_node(col, 0.26, 0.4)
		melon.material_override = _fruit_mat(col, is_gold)
		melon.scale = Vector3(1.3, 0.92, 1.0)
		melon.position = Vector3(0.02, 0.22, 0.02)
		holder.add_child(melon)
		var stub := _cyl_node(Color(0.34, 0.30, 0.16), 0.015, 0.06)
		stub.position = Vector3(0.02, 0.40, -0.18)
		holder.add_child(stub)

# Homestead band behind the field: farmhouse | windmill | well | depot (left->right),
# each tappable (well=Su Al, depot=Sat, farmhouse/mill=Magaza). Mirrors the 2D layout.
func _build_props() -> void:
	# Everything lives under _homestead so it can slide back in lockstep with the field's
	# back edge when the plot expands (otherwise the buildings end up inside the field).
	_homestead = Node3D.new()
	add_child(_homestead)
	_props_back_z = _origin().z
	var back_z := _origin().z - 3.0   # extra gap so the bigger buildings clear the plot

	var farm: PackedScene = load("res://assets/small_farm.glb")
	var inst: Node3D = farm.instantiate()
	_homestead.add_child(inst)
	_scale_to(inst, 4.6, Vector3(-4.6, 0.0, back_z - 0.7))
	_register_building(inst, B_FARM, Vector3(-4.6, 1.7, back_z - 0.7), Vector3(4.6, 4.0, 4.6))

	_build_windmill(Vector3(-1.0, 0.0, back_z - 0.2))
	_build_well(Vector3(1.7, 0.0, back_z))
	_build_depot(Vector3(4.0, 0.0, back_z))

	_build_scenery(back_z)

# Slide the homestead so it stays the same distance behind the field's back edge as
# the plot grows. Children were built at the START back edge, so we offset by the delta.
func _reposition_homestead() -> void:
	if _homestead != null:
		_homestead.position.z = _origin().z - _props_back_z

# Fills the green around the field with farm atmosphere: a small tree grove, leafy
# bushes, hay bales by the depot, and flower patches in the foreground. Trees avoid
# the farmhouse footprint (back-left) and stay inside the camera frame.
func _build_scenery(back_z: float) -> void:
	# trees — right side is open; left-side trees sit forward, beside the field,
	# clear of the farmhouse (which occupies the back-left).
	# a fuller tree line wrapping both sides and the back, framing the farm without
	# crowding the camera. Back-row trees sit behind the homestead band.
	for t in [Vector3(4.6, 0, back_z + 0.6),
			Vector3(5.3, 0, back_z + 2.6),
			Vector3(5.0, 0, back_z + 4.6),
			Vector3(4.4, 0, back_z + 6.4),
			Vector3(-4.7, 0, back_z + 3.2),
			Vector3(-5.3, 0, back_z + 5.2),
			Vector3(-5.0, 0, back_z + 7.0),
			Vector3(-2.6, 0, back_z - 1.4),
			Vector3(0.4, 0, back_z - 1.6),
			Vector3(2.6, 0, back_z - 1.4),
			Vector3(6.0, 0, back_z + 3.6),
			Vector3(-6.0, 0, back_z + 4.4)]:
		_tree(t)

	# leafy bushes scattered around the plot edges
	for b in [Vector3(4.3, 0, back_z + 2.6),
			Vector3(-4.2, 0, back_z + 4.8),
			Vector3(3.7, 0, back_z - 0.3),
			Vector3(-3.5, 0, back_z - 0.3),
			Vector3(5.0, 0, back_z + 1.4),
			Vector3(-4.6, 0, back_z + 1.6)]:
		_bush(b)

	# a little stack of hay bales in front of the depot (right side)
	_hay(Vector3(4.0, 0, back_z + 1.0))
	_hay(Vector3(4.45, 0, back_z + 1.05))
	_hay(Vector3(4.22, 0.36, back_z + 1.02))

	# flower patches in the foreground green, just ahead of the field
	for f in [Vector3(-3.8, 0, back_z + 7.3),
			Vector3(4.0, 0, back_z + 7.1),
			Vector3(-2.4, 0, back_z + 7.6),
			Vector3(2.4, 0, back_z + 7.6)]:
		_flowers(f)

	# more butterflies drifting over the field and the foreground green for ambient life
	var fcols := [Color(0.96, 0.78, 0.32), Color(0.92, 0.46, 0.62), Color(0.62, 0.55, 0.92),
			Color(0.95, 0.55, 0.30), Color(0.55, 0.78, 0.92)]
	var centers := [Vector3(-1.6, 0.9, back_z + 4.0), Vector3(2.0, 1.1, back_z + 3.0),
			Vector3(0.3, 0.8, back_z + 5.4), Vector3(-3.2, 0.7, back_z + 6.8),
			Vector3(3.4, 0.9, back_z + 6.2), Vector3(1.2, 1.0, back_z + 1.6)]
	for i in range(centers.size()):
		_butterfly(centers[i], fcols[i % fcols.size()], i)

	# fill the empty green behind the homestead, plus sky clouds, chimney smoke and chickens
	_build_backyard(back_z)
	_build_clouds()
	_build_smoke(Vector3(-5.5, 3.45, back_z - 1.15))
	_build_chickens(back_z)

# Fills the empty band BEHIND the homestead buildings: a rail fence, a little pond, a
# vegetable garden, extra trees/bushes and a couple of hay bales — so the back isn't bare.
# All parented to _homestead so it slides back with the field as the plot grows.
func _build_backyard(back_z: float) -> void:
	# a low rail fence running left-to-right behind the buildings
	_fence(-6.5, 6.0, back_z - 2.0)
	# a small pond off to the right-back
	_pond(Vector3(3.3, 0.0, back_z - 3.0))
	# a vegetable garden behind the farmhouse (back-left)
	_veg_garden(Vector3(-5.6, 0.0, back_z - 3.0))
	# extra trees + bushes filling the deep background
	for t in [Vector3(-3.4, 0, back_z - 3.4),
			Vector3(-1.2, 0, back_z - 3.8),
			Vector3(0.9, 0, back_z - 3.6),
			Vector3(5.6, 0, back_z - 3.8),
			Vector3(-6.6, 0, back_z - 3.2),
			Vector3(6.4, 0, back_z - 2.6)]:
		_tree(t)
	for b in [Vector3(1.9, 0, back_z - 2.6),
			Vector3(-2.3, 0, back_z - 2.5),
			Vector3(4.6, 0, back_z - 3.6)]:
		_bush(b)
	# a couple of hay bales tucked behind the depot
	_hay(Vector3(5.0, 0, back_z - 1.6))
	_hay(Vector3(5.4, 0, back_z - 1.55))

# A simple rail fence: short posts along the line with two thin rails between them.
func _fence(x0: float, x1: float, z: float) -> void:
	var wood := Color(0.50, 0.34, 0.20)
	var n := int(abs(x1 - x0) / 0.9) + 1
	for i in range(n):
		var x: float = lerp(x0, x1, float(i) / float(max(n - 1, 1)))
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new(); pm.size = Vector3(0.08, 0.55, 0.08)
		post.mesh = pm
		post.material_override = _mat(wood, 1.0)
		post.position = Vector3(x, 0.27, z)
		_homestead.add_child(post)
	# two horizontal rails spanning the run
	for ry in [0.20, 0.42]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new(); rm.size = Vector3(abs(x1 - x0), 0.05, 0.05)
		rail.mesh = rm
		rail.material_override = _mat(wood.lightened(0.05), 1.0)
		rail.position = Vector3((x0 + x1) * 0.5, ry, z)
		_homestead.add_child(rail)

# A little pond: a flat blue water disc set in a ring of small stones.
func _pond(at: Vector3) -> void:
	var water := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.95; wm.bottom_radius = 0.95; wm.height = 0.04; wm.radial_segments = 18
	water.mesh = wm
	var wmat := _mat(sim.C_WATER, 0.15, 0.0)
	wmat.emission_enabled = true
	wmat.emission = sim.C_WATER.darkened(0.25)
	wmat.emission_energy_multiplier = 0.4
	water.material_override = wmat
	water.position = at + Vector3(0, 0.03, 0)
	_homestead.add_child(water)
	# a ring of stones around the rim
	for k in range(10):
		var a: float = TAU * float(k) / 10.0
		var stone := _ball_node(Color(0.55, 0.54, 0.50), 0.12, 0.9)
		stone.scale = Vector3(1.2, 0.6, 1.2)
		stone.position = at + Vector3(cos(a) * 1.0, 0.05, sin(a) * 1.0)
		_homestead.add_child(stone)

# A vegetable garden: a small raised earth bed with a few rows of little cabbages.
func _veg_garden(at: Vector3) -> void:
	var bed := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(1.8, 0.12, 1.3)
	bed.mesh = bm
	bed.material_override = _mat(Color(0.30, 0.21, 0.13), 0.9)
	bed.position = at + Vector3(0, 0.06, 0)
	_homestead.add_child(bed)
	for gx in range(3):
		for gz in range(3):
			var cab := _ball_node(Color(0.34, 0.55, 0.30), 0.13, 0.85)
			cab.scale = Vector3(1.0, 0.8, 1.0)
			cab.position = at + Vector3(-0.55 + gx * 0.55, 0.18, -0.40 + gz * 0.42)
			_homestead.add_child(cab)

# A handful of soft low-poly clouds drifting slowly across the sky (parented to the
# scene, not the homestead — the sky stays put as the field grows).
func _build_clouds() -> void:
	var defs := [Vector3(-9.0, 9.5, -5.0), Vector3(-2.0, 10.5, -7.0),
			Vector3(5.0, 9.0, -4.0), Vector3(10.0, 11.0, -8.0)]
	for i in range(defs.size()):
		var root := Node3D.new()
		add_child(root)
		root.position = defs[i]
		var s: float = 1.0 + (i % 3) * 0.25
		root.scale = Vector3.ONE * s
		# each cloud is a cluster of overlapping flattened white balls
		for off in [Vector3(0, 0, 0), Vector3(0.9, -0.1, 0.2), Vector3(-0.9, -0.05, -0.2),
				Vector3(0.4, 0.25, -0.3), Vector3(-0.4, 0.2, 0.3)]:
			var puff := _ball_node(Color(0.97, 0.98, 1.0), 0.7, 1.0)
			puff.scale = Vector3(1.3, 0.7, 1.0)
			puff.position = off
			root.add_child(puff)
		_clouds.append({"node": root, "speed": 0.25 + 0.12 * float(i % 3)})

# Chimney smoke: a short column of soft puffs that rise, swell and fade, then loop.
# Parented to _homestead so it tracks the farmhouse as the field grows.
func _build_smoke(at: Vector3) -> void:
	_smoke_base = at
	for k in range(6):
		var puff := _ball_node(Color(0.85, 0.85, 0.88), 0.13, 1.0)
		var mat := puff.material_override as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.position = at
		_homestead.add_child(puff)
		_smoke.append({"node": puff, "mat": mat, "phase": float(k) / 6.0})

# A handful of chickens that wander in lazy loops around the farmyard, bobbing as they go.
func _build_chickens(back_z: float) -> void:
	var spots := [Vector3(-3.0, 0.0, back_z + 0.4), Vector3(2.6, 0.0, back_z - 0.6),
			Vector3(0.2, 0.0, back_z + 1.2)]
	var tints := [Color(0.96, 0.95, 0.92), Color(0.86, 0.74, 0.58), Color(0.96, 0.95, 0.92)]
	for i in range(spots.size()):
		var node := _chicken(tints[i % tints.size()])
		node.position = spots[i]
		_critters.append({"node": node, "center": spots[i], "phase": float(i) * 2.3,
				"speed": 0.5 + 0.15 * i, "radius": 0.7 + 0.2 * i})

# A small low-poly chicken: plump body, head with comb + beak, perky tail and two legs.
func _chicken(tint: Color) -> Node3D:
	var root := Node3D.new()
	_homestead.add_child(root)
	var body := _ball_node(tint, 0.16, 0.85)
	body.scale = Vector3(1.1, 0.95, 1.35)
	body.position = Vector3(0, 0.18, 0)
	root.add_child(body)
	var head := _ball_node(tint, 0.10, 0.85)
	head.position = Vector3(0, 0.30, 0.16)
	root.add_child(head)
	var comb := _cone_node(Color(0.86, 0.24, 0.20), 0.05, 0.08, 5)
	comb.position = Vector3(0, 0.40, 0.16)
	root.add_child(comb)
	var beak := _cone_node(Color(0.92, 0.66, 0.18), 0.035, 0.08, 5)
	beak.rotation_degrees = Vector3(90, 0, 0)
	beak.position = Vector3(0, 0.30, 0.27)
	root.add_child(beak)
	var tail := _cone_node(tint.darkened(0.1), 0.09, 0.16, 5)
	tail.rotation_degrees = Vector3(-55, 0, 0)
	tail.position = Vector3(0, 0.26, -0.18)
	root.add_child(tail)
	for sx in [-0.06, 0.06]:
		var leg := _cyl_node(Color(0.92, 0.66, 0.18), 0.012, 0.12)
		leg.position = Vector3(sx, 0.06, 0.0)
		root.add_child(leg)
	return root

# A butterfly: tiny body with two coloured wing quads, registered for flutter + drift.
func _butterfly(center: Vector3, col: Color, i: int) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = center
	var body := _cyl_node(Color(0.18, 0.16, 0.18), 0.018, 0.12)
	root.add_child(body)
	var wings: Array = []
	for s in [-1.0, 1.0]:
		var hinge := Node3D.new()
		root.add_child(hinge)
		var w := MeshInstance3D.new()
		var wm := BoxMesh.new(); wm.size = Vector3(0.16, 0.01, 0.11)
		w.mesh = wm
		var wmat := _mat(col, 0.5)
		wmat.emission_enabled = true; wmat.emission = col; wmat.emission_energy_multiplier = 0.4
		w.material_override = wmat
		w.position = Vector3(s * 0.09, 0.0, 0.0)
		hinge.add_child(w)
		wings.append(hinge)
	_butterflies.append({"node": root, "center": center, "phase": float(i) * 2.1, "wings": wings})

# A rounded shrub: a small cluster of overlapping green balls.
func _bush(at: Vector3) -> void:
	var root := Node3D.new()
	_homestead.add_child(root)
	root.position = at
	var greens := [Color(0.26, 0.46, 0.24), Color(0.30, 0.52, 0.27), Color(0.23, 0.42, 0.22)]
	var offs := [Vector3(0, 0.18, 0), Vector3(0.16, 0.12, 0.05), Vector3(-0.15, 0.13, -0.04), Vector3(0.02, 0.10, 0.16)]
	for i in range(offs.size()):
		var ball := _ball_node(greens[i % greens.size()], 0.20 - i * 0.015, 0.9)
		ball.scale = Vector3(1.1, 0.85, 1.1)
		ball.position = offs[i]
		root.add_child(ball)
	# bushes sway a touch more than trees and faster (lighter foliage)
	_sway.append({"node": root, "phase": at.z * 2.1 + at.x, "amp": 0.05})

# A hay bale: a short straw-coloured cylinder lying on its side with darker end caps.
func _hay(at: Vector3) -> void:
	var bale := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.18; bm.bottom_radius = 0.18; bm.height = 0.42; bm.radial_segments = 14
	bale.mesh = bm
	bale.material_override = _mat(Color(0.82, 0.69, 0.32), 1.0)
	bale.rotation_degrees = Vector3(0, 0, 90)
	bale.position = at + Vector3(0, 0.18, 0)
	_homestead.add_child(bale)

# A flower patch: a few tiny coloured blossoms on short green stems.
func _flowers(at: Vector3) -> void:
	var cols := [Color(0.95, 0.85, 0.30), Color(0.90, 0.45, 0.55), Color(0.70, 0.55, 0.90), Color(0.95, 0.95, 0.95)]
	var spots := [Vector3(0, 0, 0), Vector3(0.22, 0, 0.10), Vector3(-0.18, 0, 0.14), Vector3(0.05, 0, -0.18), Vector3(-0.10, 0, -0.08)]
	for i in range(spots.size()):
		var stem := _cyl_node(Color(0.30, 0.48, 0.24), 0.012, 0.16)
		stem.position = at + spots[i] + Vector3(0, 0.08, 0)
		_homestead.add_child(stem)
		var blossom := _ball_node(cols[i % cols.size()], 0.045, 0.7)
		blossom.position = at + spots[i] + Vector3(0, 0.18, 0)
		_homestead.add_child(blossom)

# Procedural windmill (= Degirmen): stone tower + spinning-look blades.
func _build_windmill(at: Vector3) -> void:
	var root := Node3D.new()
	_homestead.add_child(root)
	root.position = at
	root.scale = Vector3.ONE * 1.5   # bigger, more realistic against the field
	var tower := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.34
	tm.bottom_radius = 0.5
	tm.height = 1.5
	tm.radial_segments = 10
	tower.mesh = tm
	tower.material_override = _mat(Color(0.74, 0.70, 0.62), 0.95)
	tower.position = Vector3(0, 0.75, 0)
	root.add_child(tower)
	var roof := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.0
	rm.bottom_radius = 0.46
	rm.height = 0.45
	rm.radial_segments = 10
	roof.mesh = rm
	roof.material_override = _mat(Color(0.55, 0.30, 0.22), 0.9)
	roof.position = Vector3(0, 1.7, 0)
	root.add_child(roof)
	# blades (a + cross of flat boxes on the front face) — spun by _sync_ambient
	var hub := Node3D.new()
	hub.position = Vector3(0, 1.3, 0.5)
	root.add_child(hub)
	_windmill_hub = hub
	for a in range(4):
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.10, 0.7, 0.04)
		blade.mesh = bm
		blade.material_override = _mat(Color(0.90, 0.86, 0.74), 0.9)
		blade.position = Vector3(0, 0.0, 0)
		blade.rotation_degrees = Vector3(0, 0, a * 45.0 + 22.5)
		blade.position = Vector3(sin(deg_to_rad(a * 90.0)) * 0.4, cos(deg_to_rad(a * 90.0)) * 0.4, 0)
		blade.rotation_degrees = Vector3(0, 0, a * 90.0)
		hub.add_child(blade)
	_register_building(root, B_MILL, at + Vector3(0, 1.35, 0), Vector3(1.65, 3.0, 1.65))

# Procedural well (= Su Kuyusu): stone ring + water + roof on posts.
func _build_well(at: Vector3) -> void:
	var root := Node3D.new()
	_homestead.add_child(root)
	root.position = at
	root.scale = Vector3.ONE * 1.4
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 0.5
	cm.radial_segments = 12
	ring.mesh = cm
	ring.material_override = _mat(Color(0.58, 0.58, 0.55), 0.95)
	ring.position = Vector3(0, 0.25, 0)
	root.add_child(ring)
	var water := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.34
	wm.bottom_radius = 0.34
	wm.height = 0.05
	wm.radial_segments = 12
	water.mesh = wm
	var wmat := _mat(sim.C_WATER, 0.2, 0.0)
	wmat.emission_enabled = true
	wmat.emission = sim.C_WATER.darkened(0.2)
	wmat.emission_energy_multiplier = 0.5
	water.material_override = wmat
	water.position = Vector3(0, 0.46, 0)
	root.add_child(water)
	for sx in [-0.36, 0.36]:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.05
		pm.bottom_radius = 0.06
		pm.height = 0.8
		post.mesh = pm
		post.material_override = _mat(Color(0.45, 0.30, 0.18), 0.95)
		post.position = Vector3(sx, 0.9, 0)
		root.add_child(post)
	var roof := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.0
	rm.bottom_radius = 0.6
	rm.height = 0.4
	rm.radial_segments = 4
	roof.mesh = rm
	roof.material_override = _mat(Color(0.55, 0.30, 0.22), 0.9)
	roof.position = Vector3(0, 1.5, 0)
	roof.rotation_degrees = Vector3(0, 45, 0)
	root.add_child(roof)
	_register_building(root, B_WELL, at + Vector3(0, 0.84, 0), Vector3(1.4, 2.24, 1.4))

# Procedural depot (= Depo): barn-like crate with a lid.
func _build_depot(at: Vector3) -> void:
	var root := Node3D.new()
	_homestead.add_child(root)
	root.position = at
	root.scale = Vector3.ONE * 1.5
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.8, 0.8)
	body.mesh = bm
	body.material_override = _mat(Color(0.62, 0.42, 0.26), 0.95)
	body.position = Vector3(0, 0.4, 0)
	root.add_child(body)
	var lid := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.0, 0.16, 0.9)
	lid.mesh = lm
	lid.material_override = _mat(Color(0.45, 0.30, 0.18), 0.9)
	lid.position = Vector3(0, 0.88, 0)
	root.add_child(lid)
	# corner straps for a crate read
	for sx in [-0.43, 0.43]:
		var strap := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.06, 0.8, 0.82)
		strap.mesh = sm
		strap.material_override = _mat(Color(0.35, 0.24, 0.15), 0.9)
		strap.position = Vector3(sx, 0.4, 0)
		root.add_child(strap)
	_register_building(root, B_DEPOT, at + Vector3(0, 0.75, 0), Vector3(1.5, 1.5, 1.35))

# Give a building a physics body so taps can hit it (raycast in _tap).
func _register_building(node: Node3D, kind: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = center
	_homestead.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_buildings.append({"node": node, "kind": kind, "body": body})

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
	var root := Node3D.new()
	_homestead.add_child(root)
	root.position = at
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.10
	tm.bottom_radius = 0.14
	tm.height = 0.7
	trunk.mesh = tm
	trunk.material_override = _mat(Color(0.42, 0.28, 0.17), 1.0)
	trunk.position = Vector3(0, 0.35, 0)
	root.add_child(trunk)
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
		cone.position = Vector3(0, 0.75 + i * 0.34, 0)
		root.add_child(cone)
	# register for a gentle breeze sway (phase varies by x so they don't move in lockstep)
	_sway.append({"node": root, "phase": at.x * 1.7 + at.z, "amp": 0.035})

# Soil darkens as it gets worked and watered: dry sandy loam when empty, rich damp
# earth once tilled/planted. Kept subtle on purpose — a small quality bump, not a restyle.
func _soil_color(s: int) -> Color:
	match s:
		SimState.EMPTY:
			return Color(0.52, 0.39, 0.25)   # dry, lighter sandy loam
		SimState.OBSTACLE:
			return Color(0.47, 0.35, 0.22)
		SimState.TILLED:
			return Color(0.33, 0.23, 0.14)   # freshly turned, damp
		SimState.PLANTED:
			return Color(0.37, 0.27, 0.16)
		_:
			return Color(0.30, 0.22, 0.13)   # growing/ripe — richest, well-watered earth

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
	if OS.has_environment("HUD_TEST"):
		_verify_hud()
	if OS.has_environment("STORE_TEST"):
		_verify_store()
	if OS.has_environment("STORE_SHOW"):
		sim.coins = 999
		_store.open_store(sim, int(OS.get_environment("STORE_SHOW")) if OS.get_environment("STORE_SHOW").is_valid_int() else 0)
	if OS.has_environment("BOT_TEST"):
		_verify_bots()
	if OS.has_environment("EVENT_TEST"):
		_verify_events()
	var bot_show: bool = OS.has_environment("BOT_SHOW")
	if bot_show:
		_setup_bot_demo()
	var event_show: bool = OS.has_environment("EVENT_SHOW")
	if event_show:
		_setup_event_demo(OS.get_environment("EVENT_SHOW"))
	# bots need a few seconds to walk out; events are short, so shoot them mid-animation
	var wait := 2.0
	if bot_show:
		wait = 5.5
	elif event_show:
		wait = 1.5
	get_tree().create_timer(wait).timeout.connect(func() -> void:
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

# Smoke test for the HUD signal -> handler -> sim -> refresh wiring (Phase F).
func _verify_hud() -> void:
	print("=== HUD_TEST: signal -> handler -> sim ===")
	var ok := true
	# Sat: stock something, emit sell_pressed, coins must rise.
	sim.stock[2] = 3  # 3 Domates @ 8
	var c0: int = sim.coins
	_hud.sell_pressed.emit()
	var sell_ok: bool = sim.coins == c0 + 24 and sim.stock_total() == 0
	ok = ok and sell_ok
	print("  Sat: coins %d -> %d, depo=%d   %s" % [c0, sim.coins, sim.stock_total(), "PASS" if sell_ok else "FAIL"])
	# Su Al: emit buy_water_pressed, water must rise, coins drop by cost.
	var w0: int = sim.water; c0 = sim.coins
	_hud.buy_water_pressed.emit()
	var buy_ok: bool = sim.water == min(w0 + sim.WATER_BUNDLE, sim.WATER_MAX) and sim.coins == c0 - sim.WATER_COST
	ok = ok and buy_ok
	print("  Su Al: water %d -> %d, coins %d -> %d   %s" % [w0, sim.water, c0 + sim.WATER_COST, sim.coins, "PASS" if buy_ok else "FAIL"])
	# Seed picker: emit seed_selected(2), selected_seed must update.
	_hud.seed_selected.emit(2)
	var seed_ok: bool = sim.selected_seed == 2
	ok = ok and seed_ok
	print("  Seed pick: selected_seed=%d   %s" % [sim.selected_seed, "PASS" if seed_ok else "FAIL"])
	print("=== HUD_TEST %s ===" % ["PASS" if ok else "FAIL"])

# Buy a few specialist bots and paint them zones, so a screenshot shows live work.
func _setup_bot_demo() -> void:
	sim.coins = 9999
	# clear a working band so till/plant/water bots have something to do
	for i in range(min(sim.states.size(), SimState.COLS * 2)):
		if sim.states[i] != SimState.OBSTACLE:
			sim.states[i] = SimState.EMPTY
		_refresh_tile(i)
	var till = sim.buy_bot(SimState.TILL)
	var harv = sim.buy_bot(SimState.HARVEST)
	var clean = sim.buy_bot(SimState.CLEAN)
	# till bot works the cleared band; harvester works the ripe back rows; cleaner the rocks
	for i in range(SimState.COLS * 2):
		if i < sim.states.size():
			till.zone[i] = true
			clean.zone[i] = true
	for i in range(sim.states.size()):
		harv.zone[i] = true
		clean.zone[i] = true
	# mirror the union into the shared work area so the zone view renders it
	for bot in sim.bots:
		for k in bot.zone:
			_shared_zone[k] = true
	_tool = 0
	_hud.refresh_tools(sim, _tool)
	_update_zone_view()
	# advance the sim a bit so bots are already out on the field for the shot
	for _k in range(120):
		sim.tick(1.0 / 30.0)
		_sync_bots(1.0 / 30.0)

# Smoke test for the bot pipeline: buy -> paint zone -> tick -> tile worked + node spawned.
func _verify_bots() -> void:
	print("=== BOT_TEST: buy -> paint -> work ===")
	var ok := true
	sim.coins = 999
	var b = sim.buy_bot(SimState.TILL)
	var spawned: bool = b != null and sim.bots.size() >= 1
	ok = ok and spawned
	print("  buy_bot: bots=%d   %s" % [sim.bots.size(), "PASS" if spawned else "FAIL"])
	# paint a known empty tile into its zone
	var t := 2
	sim.states[t] = SimState.EMPTY
	b.zone[t] = true
	b.gpos = sim._grid_center(t)
	for _k in range(20):
		sim.tick(0.05)
	var worked: bool = sim.states[t] == SimState.TILLED
	ok = ok and worked
	print("  work: tile %d state=%d   %s" % [t, sim.states[t], "PASS" if worked else "FAIL"])
	# the view spawns a node for the bot
	_sync_bots(0.016)
	var node_ok: bool = _bot_nodes.size() == sim.bots.size() and sim.bots.size() > 0
	ok = ok and node_ok
	print("  view node spawned: %d nodes   %s" % [_bot_nodes.size(), "PASS" if node_ok else "FAIL"])
	print("=== BOT_TEST %s ===" % ["PASS" if ok else "FAIL"])

# Force one event live so a screenshot shows its 3D spectacle. EVENT_SHOW=<which>.
func _setup_event_demo(which: String) -> void:
	sim.coins = 9999
	# guarantee ripe crops so birds/UFO have something to act on, and clear smoke
	for i in range(sim.states.size()):
		if sim.states[i] != SimState.OBSTACLE:
			sim.states[i] = SimState.GROWING
			sim.grow[i] = 0.9
			sim.golden[i] = false
		_refresh_tile(i)
	match which:
		"rain":
			sim.rain_t = SimState.RAIN_DUR
			sim._emit_event("Yagmur yagiyor!")
		"ufo":
			sim.ufo_active = true; sim.ufo_t = 0.0; sim.ufo_fired = false
			sim.ufo_target = SimState.COLS * 2 + 4
			sim._emit_event("UFO geldi!")
		"birds":
			for i in range(SimState.COLS):
				sim.states[i] = SimState.RIPE; sim.grow[i] = 1.0
			sim.birds_active = true; sim.birds_t = 0.0; sim.birds_done = false
			sim.birds_blocked = false
			sim._emit_event("Kuslar geliyor!")
		"scarecrow":
			sim.scarecrow_charges = SimState.SCARECROW_MAX
			sim._emit_event("Korkuluk dikildi!")
		_:  # trader is the default spectacle
			sim.sell_boost_t = SimState.SELL_BOOST_DUR
			sim._emit_event("Gezgin tuccar geldi!")
	# advance a little so the visual is mid-animation for the shot (+1.5s real wait in _shoot
	# keeps UFO/birds/rain inside their durations: ~0.5 + 1.5 = 2.0s < every event length)
	for _k in range(15):
		sim.tick(1.0 / 30.0)

# Smoke test for the event view: each event spawns/updates its 3D node.
func _verify_events() -> void:
	print("=== EVENT_TEST: sim event -> 3D visual ===")
	var ok := true
	# rain
	sim.rain_t = SimState.RAIN_DUR
	_sync_events(0.016)
	var rain_ok: bool = _rain != null and _rain.visible
	ok = ok and rain_ok
	print("  rain visual: %s" % ["PASS" if rain_ok else "FAIL"])
	# ufo
	sim.ufo_active = true; sim.ufo_t = 1.0; sim.ufo_target = 5
	_sync_events(0.016)
	var ufo_ok: bool = _ufo != null and _ufo.visible
	ok = ok and ufo_ok
	print("  ufo visual: %s" % ["PASS" if ufo_ok else "FAIL"])
	# birds
	sim.birds_active = true; sim.birds_t = 1.0
	_sync_events(0.016)
	var birds_ok: bool = _birds != null and _birds.visible
	ok = ok and birds_ok
	print("  birds visual: %s" % ["PASS" if birds_ok else "FAIL"])
	# trader
	sim.sell_boost_t = SimState.SELL_BOOST_DUR
	_sync_events(0.016)
	var trader_ok: bool = _trader != null and _trader.visible
	ok = ok and trader_ok
	print("  trader visual: %s" % ["PASS" if trader_ok else "FAIL"])
	# scarecrow
	sim.scarecrow_charges = 3
	_sync_events(0.016)
	var scare_ok: bool = _scarecrow != null and _scarecrow.visible
	ok = ok and scare_ok
	print("  scarecrow visual: %s" % ["PASS" if scare_ok else "FAIL"])
	# toast fired on the latest event_seq bump
	sim._emit_event("test")
	_sync_events(0.016)
	var toast_ok: bool = _last_event_seq == sim.event_seq
	ok = ok and toast_ok
	print("  toast synced to event_seq: %s" % ["PASS" if toast_ok else "FAIL"])
	# events hide when their state clears
	sim.rain_t = 0.0; sim.ufo_active = false; sim.birds_active = false
	sim.sell_boost_t = 0.0; sim.scarecrow_charges = 0
	_sync_events(0.016)
	var hidden_ok: bool = not _rain.visible and not _ufo.visible and not _birds.visible \
		and not _trader.visible and not _scarecrow.visible
	ok = ok and hidden_ok
	print("  events hide when cleared: %s" % ["PASS" if hidden_ok else "FAIL"])
	print("=== EVENT_TEST %s ===" % ["PASS" if ok else "FAIL"])

# Smoke test for the store: open -> buy upgrade (coins drop) -> buy bot (store closes).
func _verify_store() -> void:
	print("=== STORE_TEST: open -> buy -> wire ===")
	var ok := true
	sim.coins = 999
	_on_open_store()
	var open_ok: bool = _store.is_open()
	ok = ok and open_ok
	print("  open: is_open=%s   %s" % [str(open_ok), "PASS" if open_ok else "FAIL"])
	# buy a depot (tab 2 building) — coins fall, storage grows, store stays open
	var c0: int = sim.coins
	var cap0: int = sim.storage_cap
	_store.buy_requested.emit(SimState.IT_DEPO)
	var depo_ok: bool = sim.coins < c0 and sim.storage_cap == cap0 + 20 and _store.is_open()
	ok = ok and depo_ok
	print("  buy depo: coins %d->%d cap %d->%d open=%s   %s" % [c0, sim.coins, cap0, sim.storage_cap, str(_store.is_open()), "PASS" if depo_ok else "FAIL"])
	# buy a bot — store should close so player can paint a zone
	var b0: int = sim.bots.size()
	_store.buy_requested.emit(SimState.TILL)
	var bot_ok: bool = sim.bots.size() == b0 + 1 and not _store.is_open()
	ok = ok and bot_ok
	print("  buy bot: bots %d->%d closed=%s   %s" % [b0, sim.bots.size(), str(not _store.is_open()), "PASS" if bot_ok else "FAIL"])
	print("=== STORE_TEST %s ===" % ["PASS" if ok else "FAIL"])
