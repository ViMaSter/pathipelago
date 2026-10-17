extends Node

const BASE := "res://scn/environ/pickups/shop_item.gd"
const MOD := "res://mods-unpacked/Local-ArchipelagoShop/"

var bootstrap_error := ""
var extension: Script

func _init() -> void:
	var archive := OS.get_executable_path().get_base_dir().path_join(
		"../Resources/Local-ArchipelagoShop.zip")
	if not ProjectSettings.load_resource_pack(archive):
		bootstrap_error = "Cannot mount the AP mod archive: " + archive
		return
	extension = load(MOD + "shop_item.gd")
	if extension == null or not extension.can_instantiate():
		bootstrap_error = "Cannot load the AP shop extension."
		return
	extension.take_over_path(BASE)

func _ready() -> void:
	if not bootstrap_error.is_empty():
		push_error(bootstrap_error)
		get_tree().quit(1)
		return
	_start.call_deferred()

func _start() -> void:
	var tree := get_tree()
	if tree.root.has_node("ArchipelagoShop"):
		push_error("AP client already exists; do not combine bootstrap and Mod Loader.")
		tree.quit(1)
		return
	var client_script: Script = load(MOD + "client.gd")
	if client_script == null or not client_script.can_instantiate():
		push_error("Cannot load the AP client.")
		tree.quit(1)
		return
	var client: Node = client_script.new()
	client.name = "ArchipelagoShop"
	tree.root.add_child(client)
	if "--ap-smoke-test" in OS.get_cmdline_user_args():
		var shop_script: Script = load(BASE)
		var probe: Node = shop_script.new()
		var extended := probe.has_method("_ap_client")
		probe.free()
		var shop_scene: PackedScene = load("res://scn/environ/pickups/shop_item.tscn")
		if shop_scene == null:
			push_error("Cannot load the game's packed shop scene.")
			tree.quit(1)
			return
		var scene_probe := shop_scene.instantiate()
		var scene_extended := scene_probe.has_method("_ap_client")
		scene_probe.free()
		print("AP_BOOTSTRAP_SMOKE user_dir=", OS.get_user_data_dir(),
			" extended=", extended, " scene_extended=", scene_extended,
			" client=", tree.root.has_node("ArchipelagoShop"))
		tree.quit(0 if extended and scene_extended else 1)
		return
