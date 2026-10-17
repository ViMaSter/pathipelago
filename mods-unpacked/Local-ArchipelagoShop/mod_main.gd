extends Node

const BASE := "res://mods-unpacked/Local-ArchipelagoShop/"

func _init() -> void:
	ModLoaderMod.install_script_extension(BASE + "shop_item.gd")

func _ready() -> void:
	var client: Node = load(BASE + "client.gd").new()
	client.name = "ArchipelagoShop"
	get_tree().root.add_child.call_deferred(client)
