extends Object

const Unlocks = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/unlocks.gd")

func unlocked(chain, item):
	if item is Resource:
		var override: Variant = Unlocks.resource_override(item.resource_path)
		if override != null:
			return override
	return chain.execute_next([item])
