extends Object

const Isolation = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/isolation.gd")

func _deferred_init(chain) -> void:
	var achievement: Resource = chain.reference_object
	if not achievement.has_meta("multiworld_generation"):
		Isolation.achievements.append(weakref(achievement))
	achievement.set_meta("multiworld_generation", Isolation.generation)
	if Isolation.active:
		achievement.set("_achieved", false)
	else:
		await chain.execute_next_async()

func unlock(chain) -> void:
	var achievement: Resource = chain.reference_object
	if achievement.get_meta("multiworld_generation", -1) != Isolation.generation:
		achievement.set("_achieved", false)
		achievement.set_meta("multiworld_generation", Isolation.generation)
	if Isolation.active:
		achievement.set("_achieved", true)
	else:
		chain.execute_next()
