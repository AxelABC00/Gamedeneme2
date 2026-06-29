# PROTOTYPE - NOT FOR PRODUCTION
# Question: does a proper settings/audio-bus layer make the build feel like a real game?
# Date: 2026-06-29
#
# Player audio settings + the Music/SFX audio buses they control. Created once at startup
# (before music.gd / sfx.gd are added) so those players can route to "Music" / "SFX".
# Persisted to user://settings.json so choices survive between sessions.
extends Node
class_name GameSettings

const PATH := "user://settings.json"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

var music_on: bool = true
var sfx_on: bool = true
var music_vol: float = 0.8           # 0..1 linear
var sfx_vol: float = 0.9

func _ready() -> void:
	_ensure_buses()
	load_settings()
	apply()

# Create the Music and SFX buses (routed to Master) if they don't exist yet.
func _ensure_buses() -> void:
	if AudioServer.get_bus_index(BUS_MUSIC) == -1:
		AudioServer.add_bus()
		var mi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(mi, BUS_MUSIC)
		AudioServer.set_bus_send(mi, "Master")
	if AudioServer.get_bus_index(BUS_SFX) == -1:
		AudioServer.add_bus()
		var si := AudioServer.bus_count - 1
		AudioServer.set_bus_name(si, BUS_SFX)
		AudioServer.set_bus_send(si, "Master")

# Push current values onto the audio buses (mute + volume).
func apply() -> void:
	var mi := AudioServer.get_bus_index(BUS_MUSIC)
	if mi != -1:
		AudioServer.set_bus_mute(mi, not music_on)
		AudioServer.set_bus_volume_db(mi, linear_to_db(clamp(music_vol, 0.001, 1.0)))
	var si := AudioServer.get_bus_index(BUS_SFX)
	if si != -1:
		AudioServer.set_bus_mute(si, not sfx_on)
		AudioServer.set_bus_volume_db(si, linear_to_db(clamp(sfx_vol, 0.001, 1.0)))

func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text()
	f.close()
	var d: Variant = JSON.parse_string(raw)
	if typeof(d) != TYPE_DICTIONARY:
		return
	music_on = bool(d.get("music_on", true))
	sfx_on = bool(d.get("sfx_on", true))
	music_vol = float(d.get("music_vol", 0.8))
	sfx_vol = float(d.get("sfx_vol", 0.9))

func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"music_on": music_on,
		"sfx_on": sfx_on,
		"music_vol": music_vol,
		"sfx_vol": sfx_vol,
	}))
	f.close()
