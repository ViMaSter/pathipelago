extends SceneTree

const Isolation = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/isolation.gd")
const Unlocks = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/unlocks.gd")
const State = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/state.gd")
const Client = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/client.gd")
const Condition = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/unlock_condition.gd")
var failures := 0
var assertions := 0

class Chain extends RefCounted:
	var reference_object: Object
	var original: Callable
	func _init(object: Object, method: String):
		reference_object = object
		original = Callable(object, method)
	func execute_next(args: Array = []) -> Variant:
		return original.callv(args)

class MapDouble extends Node:
	var refund_points := 0
	func can_deactivate(_node: Node) -> bool:
		return true
	func reset_availability() -> void:
		pass
	func show_tooltip(_node: Node) -> void:
		pass

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("TEST FAILED: " + message)

func _run() -> void:
	check(OS.get_user_data_dir() == OS.get_cmdline_user_args()[0], "isolated test user directory")
	var original := "{\"stats0\":{\"shop_reroll\":999},\"plasmids0\":{\"Everything\":true}}"
	DirAccess.make_dir_recursive_absolute("user://profile_1")
	var file := FileAccess.open("user://profile_1/save.json", FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var save: Node = root.get_node("SaveManager")
	check(Isolation.enter("seedA/0/1"), "create isolated profile")
	Isolation.reload_stores(self)
	var first := Isolation.PM.active
	check(first > 3 and save.SAVE_PATH != "user://profile_1/save.json", "every native path selects reserved campaign profile")
	check(save.save_data.is_empty(), "normal progression not copied")
	save.save_custom("stats0", "attempts", 3)
	save.flush()
	var manager: Node = load("res://mods-unpacked/ViMaSter-MultiworldGGShop/profile_manager.gd").new()
	manager.name = "ProfileManager"
	root.add_child(manager)
	manager.persist()
	manager.switch_to(2)
	manager.create_profile(3)
	manager.clear_profile(1)
	manager.set_seen_profile_intro()
	check(Isolation.PM.active == first and manager.local_writes == 0, "profile buttons and pointer writes blocked while isolated")
	check(FileAccess.get_file_as_string("user://profile_1/save.json") == original, "normal profile byte-identical")
	check(Isolation.enter("seedB/0/1"), "select different server seed")
	Isolation.reload_stores(self)
	check(Isolation.PM.active != first and save.save_data.is_empty(), "server seeds never share progression")
	check(Isolation.enter("seedA/0/1"), "return to original campaign")
	Isolation.reload_stores(self)
	check(save.read_custom("stats0", "attempts") == 3, "campaign attempts survive switches")
	check(Unlocks.load_catalog(), "production unlock catalogue loads: " + Unlocks.error)
	if not Unlocks.error.is_empty():
		quit(1)
		return
	var gate_id := -1
	var node_id := -1
	for id in Unlocks.entries:
		var entry: Dictionary = Unlocks.entries[id]
		if gate_id < 0 and not str(entry.get("condition", "")).is_empty():
			gate_id = id
		if node_id < 0 and entry.kind == "plasmid":
			node_id = id
	check(gate_id >= 0 and node_id >= 0, "catalogue has gated content and Plasmid nodes")
	var ids := [gate_id, node_id]
	check(Unlocks.configure(ids), "accept selected server IDs")
	var state := State.new()
	check(state.open("user://unlocks-journal.json", "seedA/0/1", 3,
			ids.map(func(id): return float(id))), "create mixed-item journal with JSON numeric IDs")
	check(state.accept_items([{"item": State.GRANT_ITEM}, {"item": Unlocks.ITEM_BASE + gate_id}]), "accept grants and unlocks")
	check(state.bank == 1, "only grants create coin balance")
	check(state.accept_items([{"item": State.GRANT_ITEM}, {"item": Unlocks.ITEM_BASE + gate_id}]) and state.bank == 1,
		"unlock replay neither duplicates coins nor grants")
	check(not state.accept_items([{"item": State.GRANT_ITEM}, {"item": 999}]), "reject unknown server unlock")
	check(state.earn(node_id) and state.earn(node_id) and state.earned.size() == 1, "natural earn queued exactly once")
	check(state.accept_checks([Unlocks.LOCATION_BASE + node_id]), "accept natural self-reward confirmation")
	check(state.confirmed.is_empty() and state.confirmed_unlocks.size() == 1, "natural feats do not advance randomized goal")
	var reloaded := State.new()
	check(reloaded.open("user://unlocks-journal.json", "seedA/0/1", 3, ids)
			and reloaded.confirmed_unlocks == state.confirmed_unlocks, "natural confirmations persist: " + reloaded.error)
	Unlocks.reconcile(state.received, state.confirmed_unlocks)
	check(Unlocks.received(gate_id) and Unlocks.received(node_id), "both server acquisition routes confer ownership")
	Unlocks.reconcile([], [])
	check(not Unlocks.received(gate_id) and not Unlocks.received(node_id), "journal cache alone never confers ownership")
	var hooks := Condition.new()
	var condition: Resource = load("res://scn/metaprogression/unlocks/unlock_condition.gd").new()
	condition.take_over_path(str(Unlocks.entries[gate_id].condition))
	condition.natural = true
	check(Unlocks.natural_condition(condition), "natural requirement can be evaluated separately")
	check(not hooks.is_unlocked(Chain.new(condition, "is_unlocked")), "unconfirmed native result is not server ownership")
	Unlocks.reconcile([Unlocks.ITEM_BASE + gate_id], [])
	condition.natural = false
	check(hooks.is_unlocked(Chain.new(condition, "is_unlocked"))
			and hooks.is_unlocked_for(Chain.new(condition, "is_unlocked_for"), 0),
			"remote receipt satisfies native unlock gate")
	check(not condition.natural, "remote delivery never fabricates achievement stats")
	var global: Node = root.get_node("G")
	global.set("selected_parasite", int(Unlocks.entries[node_id].parasite))
	var plasmid_hooks = load("res://mods-unpacked/ViMaSter-MultiworldGGShop/plasmid.gd").new()
	var plasmid: Node = load("res://scn/metaprogression/plasmids/plasmid.gd").new()
	plasmid.name = str(Unlocks.entries[node_id].node)
	var map := MapDouble.new()
	root.add_child(map)
	map.add_child(plasmid)
	plasmid.map = map
	plasmid.active = true
	plasmid_hooks.restore(Chain.new(plasmid, "restore"))
	check(not plasmid.active, "local assignment cannot bypass missing server ownership")
	Unlocks.reconcile([Unlocks.ITEM_BASE + node_id], [])
	Unlocks.synchronized = true
	plasmid_hooks._on_pressed(Chain.new(plasmid, "_on_pressed"))
	check(plasmid.active and plasmid.native_purchases == 0, "remote node activates without paying native cost")
	plasmid_hooks._on_pressed(Chain.new(plasmid, "_on_pressed"))
	plasmid_hooks._on_pressed(Chain.new(plasmid, "_on_pressed"))
	check(plasmid.active and map.refund_points == 0 and plasmid.native_purchases == 0,
		"repeated remote assignment cannot mint respec points")
	plasmid.active = false
	plasmid.available = false
	plasmid_hooks._on_pressed(Chain.new(plasmid, "_on_pressed"))
	check(not plasmid.active, "remote ownership preserves map connectivity requirements")
	Unlocks.synchronized = false
	plasmid.available = true
	plasmid_hooks._on_pressed(Chain.new(plasmid, "_on_pressed"))
	check(not plasmid.active, "disconnected campaign cannot change assignments")
	var plasmid_manager: Node = load("res://mods-unpacked/ViMaSter-MultiworldGGShop/plasmid_manager.gd").new()
	root.add_child(plasmid_manager)
	Unlocks.reconcile([], [])
	plasmid_manager.apply_saved([str(plasmid.name), {"name": str(plasmid.name), "state": {"test": 1}}])
	check(plasmid_manager.applied.is_empty(), "Continue cannot reactivate unowned Plasmids from saved names or dictionaries")
	Unlocks.reconcile([Unlocks.ITEM_BASE + node_id], [])
	plasmid_manager.apply_saved([{"name": str(plasmid.name), "state": {"test": 1}}])
	check(plasmid_manager.applied.size() == 1, "Continue preserves state for server-owned Plasmids")
	plasmid_manager.free()
	var client := Client.new()
	client.name = "MultiworldGGShop"
	root.add_child(client)
	client.set_process(false)
	client.enabled = true
	Unlocks.hooks_ready = true
	client.authenticated = true
	client.campaign_identity = "seedA/0/1"
	client.campaign = State.new()
	check(client.campaign.open("user://empty-history.json", "seedA/0/1", 1), "empty-history fixture")
	client.slot_schema = 2
	client.sync_key = "sync-barrier"
	client._handle({"cmd": "Retrieved", "keys": {"sync-barrier": null}})
	check(client.synchronized and client.item_stream_ready and client.campaign_ready(),
		"ordered server barrier synchronizes an empty item history")
	var starts: Control = load("res://mods-unpacked/ViMaSter-MultiworldGGShop/player_selection_menu.gd").new()
	root.add_child(starts)
	starts.loadout_active = true
	client.synchronized = false
	starts._on_button_select_pressed()
	check(starts.starts == 0, "native start handler refuses unsynchronized campaigns")
	var continues: Node = load("res://mods-unpacked/ViMaSter-MultiworldGGShop/run_save_manager.gd").new()
	root.add_child(continues)
	check(not continues.has_run_save() and continues.load_run().is_empty(), "Continue never loads a run before server sync")
	starts.free()
	continues.free()
	client.synchronized = true
	client.slot_schema = 3
	client.campaign = State.new()
	check(client.campaign.open("user://natural-scan.json", "seedA/0/1", 1, [gate_id]), "natural scan fixture")
	check(Unlocks.configure([gate_id]), "configure native scan gate")
	client.native_conditions[str(Unlocks.entries[gate_id].condition)] = condition
	condition.natural = true
	global.selected_parasite = 99
	global.daily_run = 1
	client._scan_natural_unlocks()
	check(client.campaign.earned.is_empty(), "daily bypass never earns natural unlocks")
	global.daily_run = 0
	client._scan_natural_unlocks()
	check(client.campaign.earned.size() == 1 and not Unlocks.received(gate_id),
		"native character feat earned from another character waits for server confirmation")
	client.campaign.confirmed_unlocks = [Unlocks.LOCATION_BASE + gate_id]
	client._reconcile_unlocks()
	check(not Unlocks.received(gate_id), "a cached confirmation absent from the current server cannot confer ownership")
	client._accept_checks([Unlocks.LOCATION_BASE + gate_id])
	check(Unlocks.received(gate_id), "server acknowledgment applies native unlock entitlement")
	client.authenticated = false
	client._select_profile()
	check(Isolation.identity == "seedA/0/1", "disconnect retains campaign instead of normal profile")
	client.enabled = false
	client._select_profile()
	check(not Isolation.active and Isolation.PM.active == 1, "explicit disable restores normal profile")
	check(FileAccess.get_file_as_string("user://profile_1/save.json") == original, "normal save still byte-identical after round trip")
	check(hooks.is_unlocked(Chain.new(condition, "is_unlocked")) == condition.natural, "vanilla condition semantics restored")
	var collision := "blocked-seed"
	var index := 16 + collision.sha256_text().left(14).hex_to_int()
	var directory := "user://profile_%d" % index
	DirAccess.make_dir_recursive_absolute(directory)
	file = FileAccess.open(directory.path_join("save.json"), FileAccess.WRITE)
	file.store_string("{\"unknown\":true}")
	file.close()
	check(not Isolation.enter(collision) and Isolation.active and Isolation.PM.active == 4,
		"unidentified campaign files fail closed into isolation, never the normal profile")
	check(FileAccess.get_file_as_string("user://profile_1/save.json") == original,
		"profile-error path preserves normal bytes")
	Isolation.leave()
	hooks.free()
	plasmid_hooks.free()
	print("GODOT_UNLOCK_TEST_RESULT assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures else 0)
