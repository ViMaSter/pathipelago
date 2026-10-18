extends Node

const PM = preload("res://scn/profile_manager.gd")
var save_data: Dictionary = {}
var SAVE_PATH := ""
var flushes := 0

func _ready() -> void:
	reload()

func reload() -> void:
	SAVE_PATH = PM.profile_path("save.json")
	save_data.clear()
	if FileAccess.file_exists(SAVE_PATH):
		save_data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))

func flush() -> void:
	flushes += 1
	DirAccess.make_dir_recursive_absolute(SAVE_PATH.get_base_dir())
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data))
	file.close()

func read_custom(section: String, key: String, default: Variant = null) -> Variant:
	return save_data.get(section, {}).get(key, default)

func save_custom(section: String, key: String, value: Variant) -> void:
	if not save_data.has(section):
		save_data[section] = {}
	save_data[section][key] = value
