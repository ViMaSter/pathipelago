extends "res://scn/ui/start_menus/bodypart_button.gd"

const Unlocks = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/unlocks.gd")

func is_unlocked():
	if Unlocks.governs() and bodypart_res != null:
		for option in loadout_category.options:
			if option.bodypart == bodypart_res:
				var override: Variant = Unlocks.resource_override(option.resource_path)
				if override != null:
					return override
	return super()
