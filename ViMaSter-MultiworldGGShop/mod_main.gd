extends Node

const BASE := "res://mods-unpacked/ViMaSter-MultiworldGGShop/"
const Isolation = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/isolation.gd")
const Unlocks = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/unlocks.gd")
const HOOKS := {
	"scn/metaprogression/achievements/achievement.gd": "achievement.gd",
	"scn/metaprogression/unlocks/unlock_condition.gd": "unlock_condition.gd",
	"scn/metaprogression/plasmids/plasmid.gd": "plasmid.gd",
	"scn/metaprogression/plasmids/unlock_plasmid.gd": "unlock_plasmid.gd",
	"scn/utils.gd": "utils.gd",
}

func _init() -> void:
	Isolation.boot()
	ModLoaderMod.install_script_extension(BASE + "profile_manager.gd")
	ModLoaderMod.install_script_extension(BASE + "platform.gd")
	for target in HOOKS:
		ModLoaderMod.install_script_hooks("res://" + target, BASE + HOOKS[target])
	ModLoaderMod.install_script_extension(BASE + "bodypart_button.gd")
	ModLoaderMod.install_script_extension(BASE + "plasmid_manager.gd")
	ModLoaderMod.install_script_extension(BASE + "run_save_manager.gd")
	ModLoaderMod.install_script_extension(BASE + "player_selection_menu.gd")
	ModLoaderMod.install_script_extension(BASE + "shop_item.gd")

func _ready() -> void:
	Unlocks.hooks_ready = true
	for target in HOOKS:
		var prefix := "vanilla_%s_" % str(hash("res://" + target))
		var methods: Array = load("res://" + target).get_script_method_list()
		if not methods.any(func(method): return str(method.name).begins_with(prefix)):
			Unlocks.hooks_ready = false
	var client: Node = load(BASE + "client.gd").new()
	client.name = "MultiworldGGShop"
	get_tree().root.add_child.call_deferred(client)
