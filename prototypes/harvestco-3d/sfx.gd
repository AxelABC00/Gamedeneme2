# PROTOTYPE - NOT FOR PRODUCTION
# Question: do small action sounds (till / plant / water / harvest) make the farming
# feel more tactile and satisfying?
# Date: 2026-06-29
#
# Self-contained sound effects: no audio assets, no import step. Each sound is a tiny
# PCM waveform synthesized once at startup into an AudioStreamWAV, then played from a
# small pool of players so several can overlap. The SAME sounds fire whether the player
# farms by hand or a robot does the work — both just change a tile's state.
extends Node

const SR := 22050.0
const MIN_GAP := 0.06                # min seconds between two plays of the SAME sound

var _players: Array = []             # AudioStreamPlayer pool for polyphony
var _next: int = 0
var _streams: Dictionary = {}        # name -> AudioStreamWAV
var _cooldown: Dictionary = {}       # name -> seconds remaining before it can replay

func _ready() -> void:
	# routed to the "SFX" bus (created by settings.gd) so the player can mute/adjust it
	var bus_name := "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.bus = bus_name
		add_child(p)
		_players.append(p)
	_streams["till"] = _wav(_synth_till())
	_streams["plant"] = _wav(_synth_plant())
	_streams["water"] = _wav(_synth_water())
	_streams["harvest"] = _wav(_synth_harvest())
	_streams["clean"] = _wav(_synth_clean())

func _process(delta: float) -> void:
	for k in _cooldown.keys():
		_cooldown[k] = max(0.0, _cooldown[k] - delta)

# Play a named sound. Ignored if the same sound fired within MIN_GAP — so a mass event
# (e.g. rain watering every tile in one frame) makes ONE sound, not a machine-gun burst.
func play(snd: String, vol_db: float = -5.0) -> void:
	if not _streams.has(snd):
		return
	if _cooldown.get(snd, 0.0) > 0.0:
		return
	_cooldown[snd] = MIN_GAP
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[snd]
	p.volume_db = vol_db
	p.pitch_scale = randf_range(0.94, 1.06)   # slight detune so repeats don't feel robotic
	p.play()

# --- PCM helpers --------------------------------------------------------------

# Pack a float buffer (-1..1) into a mono 16-bit AudioStreamWAV.
func _wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(SR)
	w.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in range(buf.size()):
		var v: float = clamp(buf[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 32767.0))
	w.data = bytes
	return w

# attack/decay envelope + a short fade-out at the very end to kill click artifacts.
func _env(i: int, n: int, atk: float, dec: float) -> float:
	var t: float = float(i) / SR
	var a: float = clamp(t / atk, 0.0, 1.0)
	var d: float = exp(-t / dec)
	var fade: float = clamp(float(n - i) / (0.008 * SR), 0.0, 1.0)
	return a * d * fade

# A soft "boop" rising in pitch — dropping a seed into the soil.
func _synth_plant() -> PackedFloat32Array:
	var n := int(0.12 * SR)
	var buf := PackedFloat32Array(); buf.resize(n)
	var ph := 0.0
	for i in range(n):
		var f: float = lerp(470.0, 660.0, float(i) / float(n))
		ph += f / SR
		buf[i] = sin(TAU * ph) * _env(i, n, 0.005, 0.05) * 0.5
	return buf

# A low scrape + thump — turning the soil with a hoe.
func _synth_till() -> PackedFloat32Array:
	var n := int(0.16 * SR)
	var buf := PackedFloat32Array(); buf.resize(n)
	var ph := 0.0
	var prev := 0.0
	for i in range(n):
		ph += 90.0 / SR
		var thump: float = sin(TAU * ph) * 0.6
		var nz: float = randf() * 2.0 - 1.0
		prev = lerp(prev, nz, 0.35)            # crude low-pass: softer, earthy noise
		buf[i] = (thump + prev * 0.5) * _env(i, n, 0.003, 0.05) * 0.55
	return buf

# A bright descending "plip" — a splash of water on the crop.
func _synth_water() -> PackedFloat32Array:
	var n := int(0.14 * SR)
	var buf := PackedFloat32Array(); buf.resize(n)
	var ph := 0.0
	for i in range(n):
		var f: float = lerp(1000.0, 520.0, float(i) / float(n))
		ph += f / SR
		var nz: float = (randf() * 2.0 - 1.0) * 0.10
		buf[i] = (sin(TAU * ph) + nz) * _env(i, n, 0.004, 0.045) * 0.45
	return buf

# A satisfying two-note chime + snip — pulling a ripe crop.
func _synth_harvest() -> PackedFloat32Array:
	var n := int(0.20 * SR)
	var buf := PackedFloat32Array(); buf.resize(n)
	var p1 := 0.0
	var p2 := 0.0
	for i in range(n):
		p1 += 660.0 / SR
		p2 += 990.0 / SR
		var snip: float = (randf() * 2.0 - 1.0) * exp(-float(i) / SR / 0.012) * 0.3
		buf[i] = (sin(TAU * p1) * 0.6 + sin(TAU * p2) * 0.4 + snip) * _env(i, n, 0.004, 0.08) * 0.5
	return buf

# A gritty crunch + thump — clearing a rock off the plot.
func _synth_clean() -> PackedFloat32Array:
	var n := int(0.20 * SR)
	var buf := PackedFloat32Array(); buf.resize(n)
	var ph := 0.0
	var prev := 0.0
	for i in range(n):
		ph += 70.0 / SR
		var thump: float = sin(TAU * ph) * 0.5
		var nz: float = randf() * 2.0 - 1.0
		prev = lerp(prev, nz, 0.5)
		buf[i] = (thump + prev * 0.7) * _env(i, n, 0.002, 0.06) * 0.55
	return buf
