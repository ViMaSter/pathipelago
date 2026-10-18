extends "res://scn/run_save_manager.gd"

const Isolation = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/isolation.gd")

func _multiworld_ready() -> bool:
	if not Isolation.active:
		return true
	var client := get_node_or_null("/root/MultiworldGGShop")
	return client != null and client.campaign_ready()

func has_run_save() -> bool:
	return _multiworld_ready() and super()

func load_run() -> Dictionary:
	if not _multiworld_ready():
		Isolation.report("Connect and synchronize the campaign before continuing its run.")
		return {}
	return super()
