extends Node

const BASE := "res://mods-unpacked/ViMaSter-MultiworldGGShop/"

func _init() -> void:
	ModLoaderMod.install_script_extension(BASE + "shop_item.gd")

func _ready() -> void:
	var client: Node = load(BASE + "client.gd").new()
	client.name = "MultiworldGGShop"
	get_tree().root.add_child.call_deferred(client)
