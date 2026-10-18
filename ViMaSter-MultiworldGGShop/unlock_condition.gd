extends Object

const Unlocks = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/unlocks.gd")

func is_unlocked(chain):
	if Unlocks.evaluating_native:
		return chain.execute_next()
	var override: Variant = Unlocks.condition_override(chain.reference_object.resource_path)
	return chain.execute_next() if override == null else override

func is_unlocked_for(chain, parasite):
	if Unlocks.evaluating_native:
		return chain.execute_next([parasite])
	var override: Variant = Unlocks.condition_override(chain.reference_object.resource_path)
	return chain.execute_next([parasite]) if override == null else override
