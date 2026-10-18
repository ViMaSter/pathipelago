extends Node

var saves := 0
var is_loading_run := false
var reloads := 0

func save_run() -> void:
	saves += 1

func reload() -> void:
	reloads += 1

func has_run_save() -> bool:
	return true

func load_run() -> Dictionary:
	return {"seed": "stub"}
