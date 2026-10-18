extends "res://scn/platforms/platform.gd"

const Isolation = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/isolation.gd")

func is_achievement_unlocked(ach_id: String) -> bool:
	if Isolation.active:
		return false
	return await super(ach_id)

func unlock_achievement(ach_id: String) -> void:
	if not Isolation.active:
		await super(ach_id)

func upload_player_score(new_player_score: int, level_reached: int, run_time: float) -> void:
	if not Isolation.active:
		super(new_player_score, level_reached, run_time)
