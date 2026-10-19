extends "res://scn/ui/start_menus/bodypart_button.gd"

const Unlocks = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/unlocks.gd")

func _multiworld_loadout_override() -> Variant:
	if Unlocks.governs() and bodypart_res != null:
		# The editor deep-copies options, clearing their resource paths, but keeps
		# the external bodypart resource and character identity intact.
		var tree := Engine.get_main_loop() as SceneTree
		var parasite: int = tree.root.get_node("G").selected_parasite
		return Unlocks.loadout_override(bodypart_res.resource_path, parasite)
	return null

func is_unlocked():
	var override: Variant = _multiworld_loadout_override()
	return super() if override == null else override
