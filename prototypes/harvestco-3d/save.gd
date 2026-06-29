# PROTOTYPE - NOT FOR PRODUCTION
# Question: does persistent save/load make this feel like a real, returnable game?
# Date: 2026-06-29
#
# Tiny save layer. The SimState owns serialization (to_dict/from_dict); this just does
# the file IO to user://save.json. Loaded by path (no class_name reference) so it works
# in console/headless runs that never ran an editor import.
extends RefCounted

const PATH := "user://save.json"

func has_save() -> bool:
	return FileAccess.file_exists(PATH)

func save_sim(sim) -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(sim.to_dict()))
	f.close()
	return true

func load_into(sim) -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return false
	var raw := f.get_as_text()
	f.close()
	var d: Variant = JSON.parse_string(raw)
	if typeof(d) != TYPE_DICTIONARY:
		return false
	sim.from_dict(d)
	return true

func clear() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("save.json"):
		dir.remove("save.json")
