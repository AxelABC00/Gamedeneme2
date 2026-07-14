# Procedural app-icon generator for "Durdanin Tarlalari" — draws a cozy wheat-sprig
# farm icon straight into an Image (no GPU needed) and saves PNGs at icon sizes.
# Run: godot --headless --path . --script res://_makeicon.gd
extends SceneTree

const N := 1024

func _init():
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	_background(img)
	_sun(img, 748, 250, 120)
	_hill(img)
	_wheat(img)
	img.save_png("res://icon_1024.png")
	# Godot project/editor icon (also fine as a source for Android launcher icons)
	var i256 := img.duplicate()
	i256.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	i256.save_png("res://icon.png")
	print("ICON DONE")
	quit()

func _lerp3(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clamp(t, 0.0, 1.0))

func _background(img: Image) -> void:
	var sky := Color("#9FD8EE")
	var mid := Color("#BFE6A6")
	var grass := Color("#74B84A")
	for y in range(N):
		var t := float(y) / float(N)
		var col: Color
		if t < 0.55:
			col = _lerp3(sky, mid, t / 0.55)
		else:
			col = _lerp3(mid, grass, (t - 0.55) / 0.45)
		for x in range(N):
			img.set_pixel(x, y, col)

func _blend(img: Image, x: int, y: int, col: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= N or y >= N or a <= 0.0:
		return
	var cur := img.get_pixel(x, y)
	img.set_pixel(x, y, cur.lerp(col, clamp(a, 0.0, 1.0)))

# anti-aliased filled disc
func _disc(img: Image, cx: float, cy: float, r: float, col: Color, alpha: float = 1.0) -> void:
	var x0 := int(floor(cx - r - 1)); var x1 := int(ceil(cx + r + 1))
	var y0 := int(floor(cy - r - 1)); var y1 := int(ceil(cy + r + 1))
	for y in range(y0, y1):
		for x in range(x0, x1):
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			var cov: float = clamp(r - d + 0.5, 0.0, 1.0)
			_blend(img, x, y, col, cov * alpha)

# anti-aliased filled ellipse, rotatable
func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, ang_deg: float, col: Color, alpha: float = 1.0) -> void:
	var ang := deg_to_rad(ang_deg)
	var ca := cos(ang); var sa := sin(ang)
	var rr: float = max(rx, ry) + 2.0
	for y in range(int(cy - rr), int(cy + rr)):
		for x in range(int(cx - rr), int(cx + rr)):
			var dx := x + 0.5 - cx; var dy := y + 0.5 - cy
			var u := dx * ca + dy * sa
			var v := -dx * sa + dy * ca
			var f := (u * u) / (rx * rx) + (v * v) / (ry * ry)
			# soft edge in normalized space
			var cov: float = clamp((1.0 - f) * min(rx, ry) * 0.5 + 0.5, 0.0, 1.0)
			_blend(img, x, y, col, cov * alpha)

func _sun(img: Image, cx: float, cy: float, r: float) -> void:
	_disc(img, cx, cy, r + 46, Color("#FFD23F"), 0.30)   # soft glow
	_disc(img, cx, cy, r, Color("#FFCE3A"))
	_disc(img, cx, cy, r * 0.74, Color("#FFE486"))

func _hill(img: Image) -> void:
	# a big rolling foreground hill across the bottom
	_ellipse(img, 512, 1230, 940, 560, 0.0, Color("#67AD40"))
	_ellipse(img, 210, 1180, 460, 320, 0.0, Color("#5C9C39"), 0.85)
	_ellipse(img, 850, 1200, 500, 340, 0.0, Color("#5C9C39"), 0.85)

func _wheat(img: Image) -> void:
	var stem := Color("#C79A47")
	var leaf := Color("#6DBE47")
	var leaf_dk := Color("#57A537")
	var grain := Color("#F0C24B")
	var grain_dk := Color("#D9A63A")
	# stem (rounded bar)
	var top := Vector2(512, 452)
	var bot := Vector2(512, 792)
	var steps := 60
	for i in range(steps + 1):
		var p := top.lerp(bot, float(i) / steps)
		_disc(img, p.x, p.y, 15, stem)
	# two leaves off the stem
	_ellipse(img, 430, 690, 120, 34, 34.0, leaf_dk)
	_ellipse(img, 433, 686, 112, 28, 34.0, leaf)
	_ellipse(img, 594, 690, 120, 34, -34.0, leaf_dk)
	_ellipse(img, 591, 686, 112, 28, -34.0, leaf)
	# wheat head: paired kernels climbing the top of the stem + a crown kernel
	var base_y := 470.0
	for i in range(6):
		var y := base_y - i * 40.0
		var sc := 1.0 - i * 0.05
		# left kernel
		_ellipse(img, 512 - 30, y, 34 * sc, 17 * sc, 32.0, grain_dk)
		_ellipse(img, 512 - 30, y, 28 * sc, 13 * sc, 32.0, grain)
		# right kernel
		_ellipse(img, 512 + 30, y, 34 * sc, 17 * sc, -32.0, grain_dk)
		_ellipse(img, 512 + 30, y, 28 * sc, 13 * sc, -32.0, grain)
	# crown kernel
	_ellipse(img, 512, base_y - 6 * 40.0 - 6, 30, 52, 0.0, grain_dk)
	_ellipse(img, 512, base_y - 6 * 40.0 - 6, 24, 46, 0.0, grain)
