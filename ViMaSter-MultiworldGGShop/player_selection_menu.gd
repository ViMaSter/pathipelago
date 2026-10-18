extends "res://scn/ui/start_menus/player_selection_menu.gd"

const Isolation = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/isolation.gd")

func _on_button_select_pressed() -> void:
	if Isolation.active and loadout_active:
		if int(get_node("/root/G").daily_run) != 0:
			Isolation.report("Daily runs are not supported in MultiworldGG. Select a normal campaign run or disable MultiworldGG in the menu.")
			return
		var client := get_node_or_null("/root/MultiworldGGShop")
		if client == null or not client.campaign_ready():
			Isolation.report("Connect and synchronize the campaign before starting its run.")
			return
	super()
