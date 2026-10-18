extends "res://scn/profile_manager.gd"

const Isolation = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/isolation.gd")

func persist() -> void:
	if Isolation.active:
		get_node("/root/SaveManager").flush()
	else:
		super()

func had_legacy_migration() -> bool:
	return false if Isolation.active else super()

func has_seen_profile_intro() -> bool:
	return true if Isolation.active else super()

func set_seen_profile_intro() -> void:
	if not Isolation.active:
		super()

func switch_to(idx: int) -> void:
	if Isolation.active:
		Isolation.report("Disable MultiworldGG in the main menu before switching normal profiles.")
	else:
		super(idx)

func create_profile(idx: int) -> void:
	if Isolation.active:
		Isolation.report("Normal profiles cannot be created while the isolated campaign is selected.")
	else:
		super(idx)

func clear_profile(idx: int) -> void:
	if Isolation.active:
		Isolation.report("Normal profiles cannot be cleared while the isolated campaign is selected.")
	else:
		super(idx)
