extends SceneTree

const Isolation = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/isolation.gd")
const Unlocks = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/unlocks.gd")
const State = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/state.gd")
const Client = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/client.gd")
const Condition = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/unlock_condition.gd")
var failures := 0
var assertions := 0

class ProtocolClient extends Client:
	var sent: Array = []
	func _send(message: Dictionary) -> bool:
		sent.append(message)
		return true

class OrganelleClient extends ProtocolClient:
	func _instantiate_organelle(id: int) -> Node:
		var part := PartDouble.new()
		part.id = id
		return part

class PartDouble extends Node2D:
	var id := 0
	var masked := true
	func has_tag(_tag: int) -> bool:
		return false
	func set_masked_visible(value: bool) -> void:
		masked = value

class EditorDouble extends Node:
	var state := 3
	var active := false
	var active_bodypart: Node = null
	var shown: Array = []
	var camera := Node2D.new()
	func get_following_camera() -> Node:
		return camera
	func show_editor(part: Node) -> void:
		# Like the game, a second hand-off would park the held part; the client must never do that.
		shown.append(part.id)
		active_bodypart = part
		active = true
		state = 2
	func place_and_close() -> void:
		if active_bodypart != null:
			active_bodypart.free()
		active_bodypart = null
		active = false
		state = 3

class PlayerDouble extends Node:
	var dead := false
	var listening := true
	func acts_on_input() -> bool:
		return listening and not dead
	func in_play() -> bool:
		return not dead

class Chain extends RefCounted:
	var reference_object: Object
	var original: Callable
	func _init(object: Object, method: String):
		reference_object = object
		original = Callable(object, method)
	func execute_next(args: Array = []) -> Variant:
		return original.callv(args)

class AudioDouble extends Node:
	var music := -1.0
	func apply_volume_settings() -> void:
		music = get_node("/root/SaveManager").read_custom("settings", "music_volume", 1.0)

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
	var original := "{\"stats0\":{\"shop_reroll\":999},\"plasmids0\":{\"Everything\":true},\"settings\":{\"music_volume\":0.25,\"language\":\"de\"}}"
	DirAccess.make_dir_recursive_absolute("user://profile_1")
	var file := FileAccess.open("user://profile_1/save.json", FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var original_local := "[settings]\n\nlighting_mode=2\n"
	file = FileAccess.open("user://profile_1/local_settings.cfg", FileAccess.WRITE)
	file.store_string(original_local)
	file.close()
	var audio := AudioDouble.new()
	audio.name = "AudioManager"
	root.add_child(audio)
	var save: Node = root.get_node("SaveManager")
	check(Isolation.enter("seedA/0/1"), "create isolated profile")
	Isolation.reload_stores(self)
	var first := Isolation.PM.active
	check(first > 3 and save.SAVE_PATH != "user://profile_1/save.json", "every native path selects reserved campaign profile")
	check(not save.save_data.has("stats0") and not save.save_data.has("plasmids0"), "normal progression not copied")
	check(save.read_custom("settings", "music_volume") == 0.25 and save.read_custom("settings", "language") == "de",
			"campaign inherits the normal profile's settings")
	check(audio.music == 0.25, "inherited music volume is applied to the live audio buses")
	var local := ConfigFile.new()
	check(local.load(Isolation.PM.profile_path("local_settings.cfg")) == OK
			and typeof(local.get_value("settings", "lighting_mode")) == TYPE_INT
			and local.get_value("settings", "lighting_mode") == 2, "device-local settings keep their type")
	save.save_custom("settings", "music_volume", 0.6)
	Isolation.capture_preferences(self)
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
	check(Isolation.PM.active != first and not save.save_data.has("stats0"), "server seeds never share progression")
	check(save.read_custom("settings", "music_volume") == 0.6 and audio.music == 0.6,
			"volume changed in one campaign survives switching campaigns")
	check(FileAccess.get_file_as_string("user://profile_1/save.json") == original
			and FileAccess.get_file_as_string("user://profile_1/local_settings.cfg") == original_local,
			"sharing settings never writes the normal profile")
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
	check(Unlocks.configure([], true), "configure full starting roster without remote character IDs")
	for id in Unlocks.entries:
		var entry: Dictionary = Unlocks.entries[id]
		if entry.kind == "character":
			check(Unlocks.condition_override(entry.condition) == true,
				"starting character condition is unlocked")
			check(Unlocks.resource_override(entry.resource) == true,
				"starting character resource is unlocked")
			check(not Unlocks.selected.has(id), "starting characters have no remote checks")
			Isolation.active = false
			check(Unlocks.condition_override(entry.condition) == null
					and Unlocks.resource_override(entry.resource) == null,
				"starting characters never affect vanilla profiles")
			Isolation.active = true
			check(not Unlocks.configure([id], true), "reject no-op remote starting-character item")
	Unlocks.reset()
	check(not Unlocks.start_with_all_characters, "reset clears starting roster entitlement")
	var ids := [gate_id, node_id]
	check(Unlocks.configure(ids), "accept selected server IDs")
	check(not Unlocks.start_with_all_characters, "older slots retain native character gates")
	var state := State.new()
	check(state.open("user://unlocks-journal.json", "seedA/0/1", 3,
			ids.map(func(id): return float(id))), "create mixed-item journal with JSON numeric IDs")
	check(state.accept_items([
		{"item": State.GRANT_ITEM}, {"item": State.DNA_ITEM},
		{"item": State.PLASMID_FRAGMENTS_ITEM}, {"item": Unlocks.ITEM_BASE + gate_id}]),
		"accept currency items and unlocks")
	check(state.bank == 1 and state.dna_bank == 1 and state.plasmid_fragment_bank == 1,
		"currency items create separate balances")
	check(state.accept_items([
		{"item": State.GRANT_ITEM}, {"item": State.DNA_ITEM},
		{"item": State.PLASMID_FRAGMENTS_ITEM}, {"item": Unlocks.ITEM_BASE + gate_id}])
			and state.bank == 1 and state.dna_bank == 1 and state.plasmid_fragment_bank == 1,
		"unlock replay neither duplicates currency balances nor grants")
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
	check(plasmid_hooks._id(plasmid) == node_id, "detached Plasmid resolves its catalogue ID through the main tree")
	plasmid_hooks.restore(Chain.new(plasmid, "restore"))
	check(not plasmid.active, "detached Plasmid restore works before entering the tree")
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
	var client := ProtocolClient.new()
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
	client._update_toast(5.1)
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
	check(not is_instance_valid(global.main) and client.toast.visible
			and client.toast.text.contains(str(Unlocks.entries[gate_id].name)),
			"permanent unlock toast is visible in the main menu without a living run")
	client.toast.visible = false
	client._reconcile_unlocks()
	check(not client.toast.visible, "unchanged unlock reconciliation does not replay the toast")
	_victories(client, global)
	_loadout_buttons(client, global)
	_plasmid_slots(client, global)
	client.authenticated = false
	client._select_profile()
	check(Isolation.identity == "seedA/0/1", "disconnect retains campaign instead of normal profile")
	client.enabled = false
	client._select_profile()
	check(not Isolation.active and Isolation.PM.active == 1, "explicit disable restores normal profile")
	check(FileAccess.get_file_as_string("user://profile_1/save.json") == original, "normal save still byte-identical after round trip")
	check(hooks.is_unlocked(Chain.new(condition, "is_unlocked")) == condition.natural, "vanilla condition semantics restored")
	client.free()
	_slot_inventory()
	_organelle_deliveries(global)
	await _connection_ui(global)
	var empty_client := ProtocolClient.new()
	root.add_child(empty_client)
	empty_client.set_process(false)
	empty_client.seed_name = "zero-check-campaign"
	empty_client._connected({
		"team": 0, "slot": 1, "players": [], "missing_locations": [], "checked_locations": [],
		"slot_data": {"schema": 3, "catalog_schema": 1, "unlock_ids": [], "extra_checks": 0,
			"sources": {"shops": true, "item_rooms": true, "boss_rewards": true, "level_ups": true},
			"death_link": false},
	})
	check(not empty_client.fatal and empty_client.authenticated and empty_client.count == 0,
		"client accepts a zero-shipment slot")
	check(empty_client.campaign.next_location() == -1
			and empty_client.sent.any(func(message): return message.get("cmd") == "StatusUpdate" and message.get("status") == 30),
		"zero-shipment slot has no pending rewards and reports its completed goal")
	empty_client.free()
	var fixture := {
		"team": 0, "slot": 1, "players": [], "missing_locations": [], "checked_locations": [],
		"slot_data": {"schema": 3, "catalog_schema": 1, "unlock_ids": [], "extra_checks": 0,
			"sources": {"shops": true, "item_rooms": true, "boss_rewards": true, "level_ups": true},
			"death_link": false, "required_victories": 50},
	}
	var gated_client := ProtocolClient.new()
	root.add_child(gated_client)
	gated_client.set_process(false)
	gated_client.seed_name = "victory-gated-empty-slot"
	gated_client._connected(fixture)
	check(not gated_client.fatal and gated_client.required_victories == 50
			and not gated_client.sent.any(func(message): return message.get("cmd") == "StatusUpdate"),
		"zero shipments with positive required victories waits for wins")
	gated_client.free()
	for value in [-1, 51, 1.5, "1", null, true]:
		var invalid_client := ProtocolClient.new()
		root.add_child(invalid_client)
		invalid_client.set_process(false)
		fixture.slot_data.required_victories = value
		invalid_client._connected(fixture)
		check(invalid_client.fatal and not invalid_client.authenticated,
			"malformed required victories rejected")
		invalid_client.free()
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

func _loadout_buttons(client: Node, global: Node) -> void:
	var ids: Array = Unlocks.entries.keys().filter(func(id): return Unlocks.entries[id].kind == "loadout")
	check(ids.size() == 68 and Unlocks.configure(ids), "configure every character's loadout unlocks")
	for id in ids:
		var entry: Dictionary = Unlocks.entries[id]
		global.selected_parasite = int(entry.parasite)
		var button: Button = load("res://mods-unpacked/ViMaSter-MultiworldGGShop/bodypart_button.gd").new()
		var bodypart := Resource.new()
		bodypart.take_over_path(str(entry.bodypart))
		button.bodypart_res = bodypart
		root.add_child(button)
		Unlocks.reconcile([], [])
		client._refresh_unlock_menus(button)
		check(not button.is_unlocked() and button.disabled and button.get_node("Lock").visible,
				"unreceived copied loadout stays locked: " + entry.name)
		Unlocks.reconcile([Unlocks.ITEM_BASE + id], [])
		client._refresh_unlock_menus(button)
		check(button.is_unlocked() and not button.disabled and not button.get_node("Lock").visible
				and button.modulate == Color.WHITE, "received loadout is selectable and visibly unlocked: " + entry.name)
		for other_id in ids:
			var other: Dictionary = Unlocks.entries[other_id]
			if other.parasite != entry.parasite and other.bodypart == entry.bodypart:
				global.selected_parasite = int(other.parasite)
				check(not button.is_unlocked(), "same bodypart receipt cannot unlock another character's loadout")
				break
		button.free()
	Unlocks.reset()
	var vanilla: Button = load("res://mods-unpacked/ViMaSter-MultiworldGGShop/bodypart_button.gd").new()
	check(vanilla.is_unlocked(), "disabled remote loadouts preserve native availability")
	vanilla.free()

func _connection_ui(global: Node) -> void:
	var scene := Control.new()
	root.add_child(scene)
	current_scene = scene
	var settings: Node = load("res://scn/ui/options_menu.gd").new()
	scene.add_child(settings)
	var starts: Node = load("res://mods-unpacked/ViMaSter-MultiworldGGShop/player_selection_menu.gd").new()
	scene.add_child(starts)
	var loadout: Node = starts.get_node("%LoadoutMenu")
	var preview := Node.new()
	loadout.add_child(preview)
	loadout.player = preview
	var profile_changes := [0]
	var on_profile_changed := func(): profile_changes[0] += 1
	root.get_node("SignalBus").profile_changed.connect(on_profile_changed)
	var client := ProtocolClient.new()
	scene.add_child(client)
	client.set_process(false)
	var store: Node = root.get_node("RunSaveManager")
	var reloads: int = store.reloads
	client.server = ""
	client.slot_name = ""
	client.set_enabled(true)
	await process_frame
	await process_frame
	check(current_scene == scene and is_instance_valid(settings),
		"enabling changes profile without replacing the scene or Settings")
	check(profile_changes[0] > 0 and starts.profile_updates > 0
			and store.reloads > reloads
			and root.get_node("SaveManager").SAVE_PATH == Isolation.PM.profile_path("save.json")
			and starts.refreshed_profile == Isolation.PM.active
			and loadout.player_setups > 0 and loadout.bodypart_setups > 0
			and loadout.refreshed_profile == Isolation.PM.active,
		"profile change refreshes native stores, start menu, and loadout preview")
	settings._on_tab_changed(2)
	var page: Control = settings.tab_content.get_child(2)
	var widgets: Dictionary = client.pages.filter(func(entry): return entry.page == page)[0]
	var extra_page := client._build_page()
	scene.add_child(extra_page)
	check(widgets.connection.text == "Connect", "idle button says Connect")
	client.connecting = true
	client._candidates = PackedStringArray(["ws://fallback.invalid:38281"])
	client._refresh_pages()
	check(widgets.connection.text == "Cancel" and client.pages[-1].connection.text == "Cancel",
		"all Settings pages show Cancel during connection")
	var session: WebSocketPeer = client.socket
	widgets.server.text = "edited.invalid:1234"
	widgets.slot.text = "Edited Slot"
	widgets.connection.pressed.emit()
	check(client.socket != session and not client.connecting and client._candidates.is_empty()
			and widgets.connection.text == "Connect" and client.status == "Connection cancelled.",
		"Cancel discards the old session and all fallback attempts immediately")
	check(client.server.is_empty() and widgets.server.text == "edited.invalid:1234"
			and client.slot_name.is_empty() and widgets.slot.text == "Edited Slot",
		"Cancel preserves field edits without changing connection identity")
	client.seed_name = "connection-ui"
	client.server = "127.0.0.1:38281"
	client.slot_name = "UI Slot"
	client._connected({
		"team": 0, "slot": 1, "players": [], "missing_locations": [], "checked_locations": [],
		"slot_data": {"schema": 3, "catalog_schema": 1, "unlock_ids": [], "extra_checks": 0,
			"sources": {"shops": true, "item_rooms": true, "boss_rewards": true, "level_ups": true}},
	})
	check(client.authenticated and not client.synchronized and widgets.connection.text == "Cancel"
			and not client.toast.text.contains("Successfully connected"),
		"authentication remains cancellable and does not announce sync success early")
	var key: String = client.sync_key
	var journal: RefCounted = client.campaign
	client.show_toast("Unlocked fixture")
	client._handle({"cmd": "Retrieved", "keys": {key: null}})
	await process_frame
	check(current_scene == scene and settings.current_tab == 2 and page.is_inside_tree(),
		"campaign synchronization keeps the Settings instance and selected tab")
	check(Isolation.identity == client.campaign_identity and starts.refreshed_profile == Isolation.PM.active
			and loadout.refreshed_profile == Isolation.PM.active and client.campaign_ready(),
		"synchronization refreshes preview against the server-bound profile")
	check(widgets.connection.text == "Disconnect" and client.toast.visible
			and client.toast.text == "MultiworldGG: Successfully connected to 127.0.0.1:38281 (Slot: UI Slot)! Start the game to join the MultiWorld!",
		"sync success uses unlock toast with the requested server/slot wording")
	client.show_toast("Unlocked after sync")
	check(client.toast.text.contains("Successfully connected"), "unlock delivery cannot overwrite connection notice")
	client._update_toast(5.1)
	check(client.toast.text == "MultiworldGG: Unlocked fixture", "startup unlock notice is preserved after success")
	client._update_toast(5.1)
	check(client.toast.text == "MultiworldGG: Unlocked after sync", "later unlock notices remain queued")
	client.death_link = true
	client.pending_death = {"test": true}
	var identity: String = Isolation.identity
	widgets.connection.pressed.emit()
	check(not client.authenticated and not client.synchronized and not client.death_link
			and client.pending_death.is_empty() and not client.campaign_ready()
			and widgets.connection.text == "Connect",
		"Disconnect immediately clears network, sync, DeathLink, and ready state")
	client._select_profile()
	check(client.campaign == journal and Isolation.identity == identity and Isolation.active,
		"Disconnect retains the campaign journal and isolated profile")
	client.connecting = true
	client._handle({"cmd": "ConnectionRefused", "errors": ["InvalidSlot"]})
	check(not client.connecting and widgets.connection.text == "Connect"
			and client.status.contains("InvalidSlot"), "refusal resets the button and preserves its specific error")
	client.authenticated = true
	client.synchronized = false
	client.sync_key = "cancel-sync"
	widgets.connection.pressed.emit()
	client._handle({"cmd": "Retrieved", "keys": {"cancel-sync": null}})
	check(not client.synchronized and not client.toast.visible, "cancelled sync cannot announce success")
	client.authenticated = true
	client.sync_key = "bad-sync"
	client.item_stream_ready = true
	var directory := "user://profile_%d" % (16 + "blocked-ui".sha256_text().left(14).hex_to_int())
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("save.json"), FileAccess.WRITE)
	file.store_string("{\"unidentified\":true}")
	file.close()
	client.campaign_identity = "blocked-ui"
	client._handle({"cmd": "Retrieved", "keys": {"bad-sync": null}})
	check(client.fatal and not client.authenticated and not client.toast.visible
			and widgets.connection.text == "Connect",
		"failed profile selection never shows success and resets the button")
	Isolation.error = ""
	client.fatal = false
	client.campaign_identity = identity
	check(Isolation.enter(identity), "restore fixture campaign after expected failure")
	var main := Node.new()
	scene.add_child(main)
	global.main = main
	client._connection_succeeded()
	check(not client.toast.text.contains("Start the game"), "active-run reconnect omits the start instruction")
	client.run_multiworld = false
	client.connect_server()
	check(not client.connecting and client.status.contains("This run is vanilla"),
		"a vanilla run cannot switch to the campaign while staying in its scene")
	client.run_multiworld = true
	client.server = "different.invalid:38281"
	client.connect_server()
	check(not client.connecting and client.status.contains("different server or slot"),
		"active campaign still rejects a different server or slot")
	global.main = null
	root.get_node("SignalBus").profile_changed.disconnect(on_profile_changed)
	current_scene = null
	scene.free()
	Isolation.leave()

func _slot_inventory() -> void:
	check(Unlocks.load_catalog(), "catalogue for slot inventory")
	var bacterium := _slot_plasmid(3, 0)
	var slot_location: int = Unlocks.LOCATION_BASE + Unlocks.SLOT_BASE + 3
	for inventory in [[], [slot_location]]:
		var slot_client := ProtocolClient.new()
		root.add_child(slot_client)
		slot_client.set_process(false)
		slot_client.seed_name = "plasmid-slot-inventory"
		slot_client._connected({
			"team": 0, "slot": 1, "players": [], "missing_locations": inventory, "checked_locations": [],
			"slot_data": {"schema": 5, "catalog_schema": 1, "unlock_ids": [float(bacterium)], "checks": 0,
				"coin_amount": 15, "dna_amount": 1, "plasmid_fragment_amount": 1,
				"sources": {"shops": true, "item_rooms": true, "boss_rewards": true, "level_ups": true},
				"death_link": false, "required_victories": 0},
		})
		if inventory.is_empty():
			check(slot_client.fatal, "schema 5 requires the slot's Earn Plasmid Slot check")
		else:
			check(not slot_client.fatal and slot_client.authenticated and Unlocks.slot_mode
					and Unlocks.remote.keys() == [Unlocks.SLOT_BASE + 3]
					and slot_client.campaign.natural_ids == [bacterium],
				"schema 5 connects with shared plasmid slots")
		slot_client.free()
	Unlocks.reset()

func _slot_plasmid(slot: int, parasite: int) -> int:
	for id in Unlocks.slot_plasmids.get(Unlocks.SLOT_BASE + slot, []):
		if int(Unlocks.entries[id].parasite) == parasite:
			return id
	return -1

func _plasmid_slots(client: Node, global: Node) -> void:
	var ids: Array = Unlocks.entries.keys().filter(func(id): return Unlocks.entries[id].kind == "plasmid")
	check(Unlocks.configure(ids, false, true), "configure shared plasmid slots: " + Unlocks.error)
	check(Unlocks.remote.size() == 36 and Unlocks.remote.keys().all(func(id): return Unlocks.is_slot(id)),
		"plasmids map to 36 shared slot items/checks")
	check(Unlocks.slot_plasmids[Unlocks.SLOT_BASE + 5].size() == 7
			and Unlocks.slot_plasmids[Unlocks.SLOT_BASE + 31].size() == 1,
		"slot 5 covers every character; slot 31 only the Bacterium")
	Unlocks.reconcile([Unlocks.ITEM_BASE + Unlocks.SLOT_BASE + 5], [])
	check(Unlocks.owned.size() == 7 and Unlocks.slot_plasmids[Unlocks.SLOT_BASE + 5].all(
			func(id): return Unlocks.received(id)), "one slot item unlocks that slot for every character")
	check(not Unlocks.received(_slot_plasmid(6, 0)), "a slot item does not unlock other slots")
	Unlocks.reconcile([Unlocks.ITEM_BASE + _slot_plasmid(5, 0)],
		[Unlocks.LOCATION_BASE + Unlocks.SLOT_BASE + 5])
	check(Unlocks.owned.is_empty(), "per-plasmid items and slot checks confer no ownership in slot mode")
	check(Unlocks.configure(ids) and Unlocks.remote.size() == ids.size(),
		"schema 4 slots keep per-character plasmid items")
	check(Unlocks.configure(ids, false, true), "reconfigure shared slots")
	var bacterium := _slot_plasmid(3, 0)
	var helminth := _slot_plasmid(3, 2)
	var slot_location: int = Unlocks.LOCATION_BASE + Unlocks.SLOT_BASE + 3
	var plasmids: Array = Unlocks.selected.keys()
	client.slot_schema = 5
	client.campaign = State.new()
	check(client.campaign.open("user://plasmid-slots.json", "seedA/0/1", 1, Unlocks.remote.keys(), plasmids),
		"slot campaign fixture")
	check(not client.campaign.accept_items([{"item": Unlocks.ITEM_BASE + bacterium}]),
		"slot campaigns reject per-character plasmid items")
	check(client.campaign.accept_items([{"item": Unlocks.ITEM_BASE + Unlocks.SLOT_BASE + 36}]),
		"slot campaigns accept slot items")
	client.item_stream.clear()
	client.sent.clear()
	global.daily_run = 0
	client.earn_unlock(bacterium)
	check(Unlocks.received(bacterium) and not Unlocks.received(helminth),
		"natural purchase unlocks only that character's plasmid")
	check(client.campaign.earned == [slot_location] and client.sent.any(func(message):
			return message.get("cmd") == "LocationChecks" and slot_location in message.locations),
		"natural purchase sends the slot check")
	check(client.toast.text.contains(str(Unlocks.entries[bacterium].name)), "natural toast names the plasmid")
	client.earn_unlock(helminth)
	check(Unlocks.received(helminth) and client.campaign.earned == [slot_location],
		"later characters unlock locally without a second slot check")
	client._accept_checks([slot_location])
	check(not Unlocks.received(_slot_plasmid(3, 1)), "confirmed slot check does not unlock other characters")
	var reloaded := State.new()
	check(reloaded.open("user://plasmid-slots.json", "seedA/0/1", 1, Unlocks.remote.keys(), plasmids)
			and reloaded.natural == [bacterium, helminth], "natural plasmids persist: " + reloaded.error)
	check(not State.new().open("user://plasmid-slots.json", "seedA/0/1", 1, Unlocks.remote.keys(), []),
		"natural plasmids outside the slot are rejected")
	client.item_stream = [{"item": Unlocks.ITEM_BASE + Unlocks.SLOT_BASE + 7}]
	client._reconcile_unlocks()
	check(Unlocks.received(_slot_plasmid(7, 4)) and client.toast.text.contains("Plasmid Slot 07")
			and not client.toast.text.contains("Plasmid:"), "slot receipt toast names the slot once")
	client.item_stream.clear()
	client.slot_schema = 3
	Unlocks.reset()

func _victories(client: Node, globals: Node) -> void:
	client.campaign = State.new()
	check(client.campaign.open("user://client-victories.json", "seedA/0/1", 1), "victory client fixture")
	client.count = 1
	client.required_victories = 2
	client.sent.clear()
	client._accept_checks([State.FIRST_LOCATION])
	check(not client.sent.any(func(message): return message.get("cmd") == "StatusUpdate"),
		"all confirmed shipments do not bypass victory requirement")
	var main := Node.new()
	var player: Node = load("res://tests/stubs/player.gd").new()
	root.add_child(main)
	root.add_child(player)
	globals.main = main
	globals.player = player
	var saves: Node = root.get_node("RunSaveManager")
	var hook: Node = load("res://mods-unpacked/ViMaSter-MultiworldGGShop/run_save_manager.gd").new()
	root.add_child(hook)
	saves.is_loading_run = false
	client.begin_run()
	var first_run: String = client.run_id
	hook.record_run(false)
	check(client.campaign.victories.is_empty(), "native death does not count as victory")
	client.run_multiworld = false
	hook.record_run(true)
	check(client.campaign.victories.is_empty(), "vanilla victory does not count")
	client.run_multiworld = true
	globals.daily_run = 1
	hook.record_run(true)
	check(client.campaign.victories.is_empty(), "daily victory does not count")
	globals.daily_run = 0
	hook.record_run(true)
	hook.record_run(true)
	check(client.campaign.victories.size() == 1 and hook.recorded_runs.size() == 5,
		"native bookkeeping preserved and repeat callbacks count once")
	saves.is_loading_run = true
	client.begin_run()
	hook.record_run(true)
	check(client.run_id == first_run and client.campaign.victories.size() == 1,
		"continued winning run cannot count twice")
	saves.is_loading_run = false
	client.begin_run()
	check(client.run_id != first_run, "new runs with the same seed have distinct identities")
	client.authenticated = false
	hook.record_run(true)
	check(client.campaign.goal_reached(2)
			and not client.sent.any(func(message): return message.get("cmd") == "StatusUpdate"),
		"offline victory persists without sending goal while disconnected")
	var loaded := State.new()
	check(loaded.open("user://client-victories.json", "seedA/0/1", 1) and loaded.victories.size() == 2,
		"offline victories survive reload")
	client.campaign = loaded
	client.authenticated = true
	client._accept_checks([])
	check(client.sent.any(func(message): return message.get("cmd") == "StatusUpdate" and message.get("status") == 30),
		"reconnection sends goal once both requirements are satisfied")
	client._accept_checks([State.FIRST_LOCATION])
	client._accept_checks([])
	client._send_goal()
	check(client.sent.filter(func(message): return message.get("cmd") == "StatusUpdate").size() == 1,
		"post-goal check replay and release updates cannot send completion twice")
	client.goal_sent = false
	client._accept_checks([])
	check(client.sent.filter(func(message): return message.get("cmd") == "StatusUpdate").size() == 2,
		"new connection can report its already completed goal")
	main.free()
	player.free()
	globals.main = null
	globals.player = null
	hook.free()

func _organelle_deliveries(global: Node) -> void:
	const Organelles = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/organelles.gd")
	check(Organelles.load_pool() and Organelles.entries.size() == 89, "organelle pool loads: " + Organelles.error)
	var isolation := [Isolation.active, Isolation.identity]
	Isolation.active = true
	Isolation.identity = "organelle-campaign"
	var retired: Array = Unlocks.entries.keys().filter(func(id): return Unlocks.entries[id].kind in ["organelle", "environment"])
	check(retired.size() == 20 and not Unlocks.configure([retired[0]], false, true, true)
			and Unlocks.configure([retired[0]], false, true, false),
		"schema 6 rejects retired organelle/environment unlocks; older schemas keep them")
	Unlocks.reset()
	check(Unlocks.configure([]), "configure an organelle-only campaign")
	var gated := "res://scn/player/bodyparts/internal/upgrader.tres"
	check(Unlocks.resource_override(gated) == true
			and Unlocks.condition_override(gated + "::Resource_unlock") == true,
		"every organelle drop gate is open in multiworld campaigns")
	Isolation.active = false
	check(Unlocks.resource_override(gated) == null and Unlocks.condition_override(gated + "::Resource_unlock") == null,
		"organelle gates stay native outside multiworld campaigns")
	Isolation.active = true
	var fixture := {
		"team": 0, "slot": 1, "players": [], "missing_locations": [], "checked_locations": [],
		"slot_data": {"schema": 6, "catalog_schema": 1, "unlock_ids": [], "checks": 0,
			"organelle_pool_schema": 1, "organelle_ids": [1.0, 2.0, 3.0],
			"coin_amount": 15, "dna_amount": 1, "plasmid_fragment_amount": 1,
			"sources": {"shops": true, "item_rooms": true, "boss_rewards": true, "level_ups": true},
			"death_link": false, "required_victories": 0},
	}
	for invalid in [{"organelle_ids": [999]}, {"organelle_ids": [1, 1]}, {"organelle_pool_schema": 2},
			{"organelle_ids": null}, {"unlock_ids": [retired[0]]}]:
		var bad := ProtocolClient.new()
		root.add_child(bad)
		bad.set_process(false)
		bad.seed_name = "organelle-invalid"
		var data: Dictionary = fixture.duplicate(true)
		data.slot_data.merge(invalid, true)
		bad._connected(data)
		check(bad.fatal, "malformed organelle slot data rejected: " + JSON.stringify(invalid))
		bad.free()
	var client := OrganelleClient.new()
	root.add_child(client)
	client.set_process(false)
	client.seed_name = "organelle-queue"
	client._connected(fixture)
	check(not client.fatal and client.authenticated and Organelles.selected.size() == 3,
		"schema 6 connects with organelle deliveries")
	Isolation.active = true
	Isolation.identity = "organelle-campaign"
	client.campaign_identity = Isolation.identity
	client.synchronized = true
	client.run_multiworld = true
	var main := Node.new()
	var editor := EditorDouble.new()
	var player := PlayerDouble.new()
	var world := Node.new()
	for node in [main, editor, player, world]:
		root.add_child(node)
	global.main = main
	global.editor = editor
	global.player = player
	global.world = world
	global.current_room = null
	global.daily_run = 0
	var item := func(id: int) -> Dictionary: return {"item": Organelles.ITEM_BASE + id}
	client.item_stream = [item.call(2)]
	client.item_stream_ready = true
	client._received({"cmd": "ReceivedItems", "index": 1, "items": []})
	check(client.campaign.pending_organelles() == [2], "received organelle is queued")
	player.listening = false
	client.organelle_ready_since = Time.get_ticks_msec() - 60000
	client._deliver_organelles()
	check(editor.shown.is_empty(), "no delivery while the player has no control (menu/pause/cutscene)")
	player.listening = true
	global.current_room = Node.new()
	client._deliver_organelles()
	check(editor.shown.is_empty(), "no delivery during a fight")
	global.current_room.free()
	global.current_room = null
	client._deliver_organelles()
	check(editor.shown.is_empty() and client.organelle_ready_since != -1, "control starts the two-second wait")
	client.organelle_ready_since -= 2000
	client._deliver_organelles()
	check(editor.shown == [2] and client.organelle_open == 2, "first organelle opens the editor holding it")
	client._received({"cmd": "ReceivedItems", "index": 1, "items": [item.call(1)]})
	client.organelle_ready_since = Time.get_ticks_msec() - 60000
	client._deliver_organelles()
	client._deliver_organelles()
	check(editor.shown == [2] and editor.active_bodypart.id == 2 and client.campaign.pending_organelles() == [2, 1],
		"a second receipt waits while the first is still held")
	editor.place_and_close()
	client._deliver_organelles()
	check(client.campaign.organelles_delivered == 1 and client.campaign.pending_organelles() == [1],
		"closing the editor completes the delivery")
	client._deliver_organelles()
	check(editor.shown == [2], "the next organelle waits at least two seconds after closing")
	client.organelle_ready_since -= 2000
	client._deliver_organelles()
	check(editor.shown == [2, 1], "queued organelles are delivered oldest first")
	var reloaded := State.new()
	check(reloaded.open(client.campaign.path, client.campaign.identity, 0, [], [], [1, 2, 3])
			and reloaded.organelles_delivered == 1 and reloaded.pending_organelles() == [1],
		"an open, unplaced delivery stays pending across restarts")
	global.player = null
	player.free()
	client._deliver_organelles()
	check(client.organelle_open == -1 and client.campaign.pending_organelles() == [1],
		"a run ending with the editor open keeps the organelle queued")
	var invalid := State.new()
	var text := FileAccess.get_file_as_string(client.campaign.path).replace(
		"\"organelles_delivered\":1", "\"organelles_delivered\":3")
	var journal := FileAccess.open("user://organelle-invalid.json", FileAccess.WRITE)
	journal.store_string(text)
	journal.close()
	check(not invalid.open("user://organelle-invalid.json", client.campaign.identity, 0, [], [], [1, 2, 3]),
		"delivered count cannot exceed received organelles")
	if editor.active_bodypart != null:
		editor.active_bodypart.free()
	for node in [main, editor, world]:
		node.free()
	global.main = null
	global.editor = null
	global.world = null
	client.free()
	Organelles.reset()
	Unlocks.reset()
	Isolation.active = isolation[0]
	Isolation.identity = isolation[1]
