# PROTOTYPE - NOT FOR PRODUCTION
# Question: does a cozy generative soundtrack make the farm feel more alive?
# Date: 2026-06-29
#
# Self-contained background music: no audio assets, no import step. We synthesize a
# gentle, slowly-wandering pentatonic melody over a soft two-note pad straight into an
# AudioStreamGenerator buffer. Cozy farming vibe — calm, never busy.
extends AudioStreamPlayer
class_name CozyMusic

const SR := 22050.0                  # mix rate (low is fine for soft pads)
const STEP_DUR := 0.46               # seconds per melody note
# C-major pentatonic over two octaves — every note sounds consonant over every chord
const SCALE := [261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33, 659.25]
# a gentle vi–IV–I–V style root cycle (A, F, C, G in a low octave) for slow movement
const CHORD_ROOTS := [110.0, 87.31, 130.81, 98.0]
const STEPS_PER_CHORD := 8

var _pb: AudioStreamGeneratorPlayback
var _mel_phase := 0.0
var _pad_a := 0.0
var _pad_b := 0.0
var _lfo := 0.0                      # slow tremolo on the pad
var _note_t := STEP_DUR
var _note_age := 100.0
var _step := 0
var _idx := 2                        # current scale index (random-walks)
var _cur_freq := SCALE[2]
var _resting := false
var _chord_root := CHORD_ROOTS[2]

func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SR
	gen.buffer_length = 0.25
	stream = gen
	volume_db = -8.0
	bus = "Master"
	play()
	_pb = get_stream_playback()
	_fill()

func _process(_delta: float) -> void:
	_fill()

func _fill() -> void:
	if _pb == null:
		return
	var n: int = _pb.get_frames_available()
	var dt := 1.0 / SR
	for i in range(n):
		_note_t += dt
		_note_age += dt
		if _note_t >= STEP_DUR:
			_note_t -= STEP_DUR
			_advance_note()
		# melody: soft triangle wave with a quick attack / slow decay envelope
		_mel_phase = fmod(_mel_phase + _cur_freq * dt, 1.0)
		var env: float = 0.0 if _resting else exp(-_note_age * 2.6)
		var melody := _tri(_mel_phase) * env * 0.55
		# pad: root + its fifth, slow tremolo, kept quiet so it sits under the melody
		_pad_a = fmod(_pad_a + _chord_root * dt, 1.0)
		_pad_b = fmod(_pad_b + _chord_root * 1.5 * dt, 1.0)
		_lfo = fmod(_lfo + 0.08 * dt, 1.0)
		var trem := 0.82 + 0.18 * sin(TAU * _lfo)
		var pad := (sin(TAU * _pad_a) + sin(TAU * _pad_b)) * 0.11 * trem
		var s: float = clamp((melody + pad) * 0.6, -1.0, 1.0)
		_pb.push_frame(Vector2(s, s))

func _advance_note() -> void:
	_step += 1
	if _step % STEPS_PER_CHORD == 0:
		_chord_root = CHORD_ROOTS[(_step / STEPS_PER_CHORD) % CHORD_ROOTS.size()]
	# every few notes take a breath (rest) so it never feels frantic
	if randf() < 0.18:
		_resting = true
		return
	_resting = false
	# gentle random walk along the pentatonic scale, staying in range
	var moves := [-2, -1, -1, 1, 1, 2]
	_idx = clampi(_idx + moves[randi() % moves.size()], 0, SCALE.size() - 1)
	_cur_freq = SCALE[_idx]
	_note_age = 0.0

# triangle wave from a 0..1 phase — softer/rounder than a saw, warmer than a sine
func _tri(p: float) -> float:
	return 4.0 * abs(p - 0.5) - 1.0
