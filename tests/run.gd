extends SceneTree

const State = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/state.gd")
const Client = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/client.gd")
var failures := 0
var assertions := 0

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("TEST FAILED: " + message)

func _run() -> void:
	print("TEST_USER_DIR ", OS.get_user_data_dir())
	check(OS.get_user_data_dir() == OS.get_cmdline_user_args()[0], "isolated user data")
	var state := State.new()
	var path := "user://state-test.json"
	check(state.open(path, "seed/team/slot", 5), "create journal")
	check(state.next_location() == 402938001, "first location")
	check(state.purchase(402938001), "record first purchase")
	check(not state.purchase(402938001), "reject duplicate purchase")
	var restored := State.new()
	check(restored.open(path, "seed/team/slot", 5), "restore journal")
	check(restored.next_location() == 402938002, "purchase survives restart")
	check(restored.accept_checks([402938001, 402938003]), "server reconciliation")
	check(restored.confirmed.size() == 2, "count acknowledgements")
	check(restored.accept_checks([402938001]), "ack replay")
	check(restored.confirmed.size() == 2, "ack replay idempotent")
	var before := restored.checks.duplicate()
	check(not restored.accept_checks([402938005, "bad"]), "reject mixed malformed acknowledgements")
	check(restored.checks == before, "malformed acknowledgement is atomic")
	var items := [{"item": 402939001}, {"item": 402939001}]
	check(restored.accept_items(items), "receive grants")
	check(restored.bank == 2, "two grants banked")
	check(restored.accept_items(items) and restored.bank == 2, "item replay idempotent")
	check(restored.redeem() and restored.bank == 0, "redeem bank")
	check(restored.accept_items(items) and restored.bank == 0, "redeemed items not replayed")
	check(not restored.accept_items([]), "reject truncated history")
	var wrong := State.new()
	check(not wrong.open(path, "different-seed", 5), "reject mismatched campaign")
	var invalid := State.new()
	check(not invalid.open("user://missing-directory/state.json", "x", 5), "write failure fails closed")
	var corrupted := FileAccess.open("user://broken.json", FileAccess.WRITE)
	corrupted.store_string("{broken")
	corrupted.close()
	check(not wrong.open("user://broken.json", "seed", 5), "corrupt journal fails closed")
	await _network_and_purchase()
	print("GODOT_TEST_RESULT assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures else 0)

func _network_and_purchase() -> void:
	var globals: Node = load("res://tests/stubs/globals.gd").new()
	globals.name = "G"
	var player: Node = load("res://tests/stubs/player.gd").new()
	root.add_child(player)
	globals.player = player
	root.add_child(globals)
	var saves: Node = load("res://tests/stubs/run_save.gd").new()
	saves.name = "RunSaveManager"
	root.add_child(saves)
	var room: Node = load("res://scn/environ/rooms/special/shop.gd").new()
	room.name = "ShopRoom"
	root.add_child(room)
	var shop: Node = _pedestal(room, "Item1", true)
	var reward: Node = shop._rewards[0]
	var second: Node = _pedestal(room, "Item2", true)
	var pickups: Node = _pedestal(room, "Item4", false)
	var early_menu: Node = load("res://scn/ui/options_menu.gd").new()
	root.add_child(early_menu)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://multiworldgg_shop/connection.cfg"))
	var client := Client.new()
	client.name = "MultiworldGGShop"
	root.add_child(client)
	await process_frame
	await process_frame
	check(client.server.is_empty(), "fresh configuration has no guessed room endpoint")
	client.connect_server()
	check(not client.connecting and client.status.contains("room page"),
			"empty endpoint gives an explicit room-address instruction")
	check(early_menu.tab_buttons.size() == 3 and early_menu.tab_buttons[2].text == "MultiworldGG",
			"menu created before the mod (main menu) also gets the tab")
	early_menu.queue_free()
	check(not client.enabled and not client.is_multiworld(shop), "MultiworldGG is off by default")
	var main := Node.new()
	root.add_child(main)
	globals.main = main
	client.begin_run()
	check(not client.run_multiworld, "run started while off is vanilla")
	client.set_enabled(true)
	check(client.enabled and not client.run_multiworld and not client.is_multiworld(shop), "enabling mid-run keeps the run vanilla")
	saves.is_loading_run = true
	client.begin_run()
	check(not client.run_multiworld, "continuing a vanilla run stays vanilla")
	saves.is_loading_run = false
	globals.rng_seed = "SEEDBBBB"
	client.begin_run()
	check(client.run_multiworld and client.is_multiworld(shop), "new run while on uses MultiworldGG")
	client.set_enabled(false)
	check(client.run_multiworld and client.is_multiworld(shop), "disabling mid-run keeps the MultiworldGG run")
	saves.is_loading_run = true
	client.begin_run()
	check(client.run_multiworld, "continuing a MultiworldGG run restores its mode")
	globals.rng_seed = "SEEDCCCC"
	client.begin_run()
	check(not client.run_multiworld, "continue with an unknown seed stays vanilla")
	saves.is_loading_run = false
	globals.rng_seed = "SEEDBBBB"
	client.set_enabled(true)
	client.begin_run()
	check(client.is_multiworld(shop), "first bodypart pedestal is the MultiworldGG pedestal")
	var start_menu: Control = load("res://scn/ui/start_menus/player_selection_menu.gd").new()
	root.add_child(start_menu)
	await process_frame
	await process_frame
	var start: Button = start_menu.get_node("ButtonSelect")
	var start_tip: Control = start.get_node_or_null("MultiworldGGStartTooltip")
	check(start_tip != null and start.has_meta("multiworldgg_start"), "start button gets the MultiworldGG warning")
	start.pressed.emit()
	check(start_menu.starts == 1, "tube selection press is not confirmed")
	start_menu.loadout_active = true
	start_menu.full = false
	start.pressed.emit()
	check(start.text == "Really Start" and start_menu.starts == 1, "vanilla organelle confirmation comes first")
	start.pressed.emit()
	await process_frame
	check(start.text == "Start MultiworldGG" and start_menu.starts == 1 and start_tip.visible,
			"MultiworldGG confirmation stacks after the vanilla one")
	start.pressed.emit()
	check(start_menu.starts == 2 and start_menu.clicks == 2 and start.text == "Start", "third press starts the run")
	start_menu.full = true
	start.pressed.emit()
	check(start.text == "Start MultiworldGG" and start_menu.starts == 2, "full loadout asks only the MultiworldGG confirmation")
	start.mouse_exited.emit()
	start.pressed.emit()
	check(start.text == "Start MultiworldGG" and start_menu.starts == 2, "leaving the button restarts the stack")
	start.pressed.emit()
	check(start_menu.starts == 3, "confirmed MultiworldGG start runs")
	var hint := Client.start_hint()
	check(hint.contains("[color=#ff9a2e]MultiworldGG enabled![/color]") and hint.contains("[color=#66e6ff]for other players[/color]")
			and hint.contains("[b]still spawn but can't be redeemed[/b]") and hint.contains("[b]start a new run[/b]"),
			"hint has orange headline, blue recipients and bold key phrases")
	client.enabled = false
	start_menu._start_button_hovered = true
	await process_frame
	check(not start_tip.visible, "MultiworldGG warning hidden while disabled")
	start.pressed.emit()
	check(start_menu.starts == 4, "disabled with full loadout starts immediately")
	start_menu.full = false
	start.pressed.emit()
	start.pressed.emit()
	check(start_menu.starts == 5, "disabled keeps the vanilla single confirmation")
	client.enabled = true
	start_menu.queue_free()
	check(not client.is_multiworld(second) and not client.is_multiworld(pickups), "exactly one MultiworldGG pedestal per shop")
	second._on_picked()
	check(second.vanilla_purchases == 1, "other pedestals stay vanilla local purchases")
	shop._on_picked()
	check(player.money == 50 and shop.vanilla_purchases == 0, "offline MultiworldGG buy neither charges nor grants vanilla")
	shop.pay_with_blood = true
	shop._on_picked()
	check(shop.vanilla_purchases == 1, "blood purchase stays vanilla")
	shop.pay_with_blood = false
	var challenge_room: Node = load("res://scn/environ/rooms/special/shop.gd").new()
	root.add_child(challenge_room)
	var choose: Node = _pedestal(challenge_room, "Item1", true)
	choose._rewards[0].choose_one = true
	var fallback: Node = _pedestal(challenge_room, "Item2", true)
	check(not client.is_multiworld(choose) and client.is_multiworld(fallback), "choose-one pedestal skipped for designation")
	var orphan: Node = load("res://mods-unpacked/ViMaSter-MultiworldGGShop/shop_item.gd").new()
	root.add_child(orphan)
	check(not client.is_multiworld(orphan), "pedestals outside shop rooms stay vanilla")
	var log_text := FileAccess.get_file_as_string("user://multiworldgg_shop/client.log")
	check(log_text.contains("Shop pick ShopRoom/Item2") and log_text.contains("vanilla local purchase") \
			and log_text.contains("-> MULTIWORLDGG"), "every pick is written to the flushed client log")
	var menu: Node = load("res://scn/ui/options_menu.gd").new()
	root.add_child(menu)
	await process_frame
	await process_frame
	check(menu.tab_buttons.size() == 3 and menu.tab_buttons[2].text == "MultiworldGG", "settings tab injected")
	check(menu.tab_content.get_child_count() == 3, "settings page injected")
	menu.tab_buttons[2].pressed.emit()
	check(menu.current_tab == 2 and menu.tab_content.get_child(2).visible, "settings tab selectable")
	var page: Control = menu.tab_content.get_child(2)
	check(page is ScrollContainer and page.custom_minimum_size.y <= client.PAGE_MAX_HEIGHT, "settings page height capped")
	var tcp := TCPServer.new()
	check(tcp.listen(0, "127.0.0.1") == OK, "listen local websocket fixture")
	client.server = "ws://127.0.0.1:%d" % tcp.get_local_port()
	client.slot_name = "Tester"
	client.connect_server()
	for i in 120:
		if tcp.is_connection_available():
			break
		await process_frame
	check(tcp.is_connection_available(), "client connects")
	if not tcp.is_connection_available():
		return
	var peer := WebSocketPeer.new()
	check(peer.accept_stream(tcp.take_connection()) == OK, "accept websocket")
	for i in 120:
		peer.poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			break
		await process_frame
	check(peer.get_ready_state() == WebSocketPeer.STATE_OPEN, "websocket open")
	_send(peer, [{"cmd": "RoomInfo", "seed_name": "fixture-campaign"}])
	var messages := await _collect(peer, 15)
	var connect_message := _find(messages, "Connect")
	check(connect_message.get("game") == "Pathogenic", "real MultiworldGG handshake game")
	check(connect_message.get("items_handling") == 7, "request local, remote, starting items")
	check(connect_message.get("tags") == ["AP"], "preserve protocol-defined AP tag")
	_send(peer, [{
		"cmd": "Connected", "team": 0, "slot": 1,
		"players": [{"team": 0, "slot": 2, "alias": "Remote Friend"}],
		"slot_info": {"1": {"name": "Tester", "game": "Pathogenic"}, "2": {"name": "Friend", "game": "Example"}},
		"missing_locations": range(402938001, 402938006),
		"checked_locations": [], "slot_data": {"schema": 1, "shop_checks": 5}
	}, {
		"cmd": "DataPackage",
		"data": {"games": {"Example": {"item_name_to_id": {"Remote Sword": 9001}},
			"Other": {"item_name_to_id": {"Wrong Game Item": 9001}}}}
	}, {
		"cmd": "LocationInfo", "locations": [
			{"location": 402938001, "item": 9001, "player": 2, "flags": 1},
			{"location": 402938002, "item": 9001, "player": 2, "flags": 1},
			{"location": 402938003, "item": 9001, "player": 2, "flags": 1},
			{"location": 402938004, "item": 9001, "player": 2, "flags": 1}
		]
	}, {"cmd": "ReceivedItems", "index": 0, "items": []}])
	messages = await _collect(peer, 15)
	check(client.authenticated, "authenticate slot")
	check(not _find(messages, "LocationScouts").is_empty(), "scout finite location pool")
	var package_request := _find(messages, "GetDataPackage")
	check(package_request.get("games") is Array and "Example" in package_request.games \
		and "Pathogenic" in package_request.games, "request data package for every slot game")
	check(client.socket.inbound_buffer_size >= 1024 * 1024, "accept large data packages")
	var big_names := {}
	for i in 4000:
		big_names["Large Package Item %04d" % i] = 700000 + i
	peer.outbound_buffer_size = 4 * 1024 * 1024
	_send(peer, [{"cmd": "DataPackage", "data": {"games": {"Large": {"item_name_to_id": big_names}}}}])
	await _collect(peer, 15)
	check(client.authenticated and client.item_names.get("Large", {}).size() == 4000, "parse data package over 64 KiB")
	check(client.offer_text(402938001) == "Remote Sword for Remote Friend (Example)", "show item, recipient and game")
	var card: Dictionary = client.tooltip_card()
	check(card.get("name") == "Remote Unlock 1/5", "tooltip title shows shipment progress")
	check(card.get("hint") == "\"[color=#66e6ff]Remote Sword[/color]\" for [color=#66e6ff]Remote Friend[/color] ([color=#66e6ff]Example[/color])",
			"tooltip highlights only item, player and game")
	var name_label := Label.new()
	name_label.name = "Label"
	reward.add_child(name_label)
	name_label.owner = reward
	name_label.unique_name_in_owner = true
	name_label.text = "Recuperative Mitochondrion"
	client._refresh_offers()
	check(name_label.text == "Remote Unlock 1/5", "floating pedestal name replaced")
	var icon := Sprite2D.new()
	icon.name = "MutationIcon"
	icon.visible = false
	reward.add_child(icon)
	icon.owner = reward
	icon.unique_name_in_owner = true
	reward.bodypart = Node2D.new()
	reward.add_child(reward.bodypart)
	client.remote_icon = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	client._refresh_offers()
	client._mask_rewards()
	check(icon.visible and icon.texture == client.remote_icon and icon.scale == client.REMOTE_ICON_SCALE \
			and not reward.bodypart.visible, "MultiworldGG pedestal shows the Enhancer icon instead of the rolled upgrade")
	check(client.REMOTE_ICON == "res://gfx/player/bodyparts/internal/upgrade.png", "remote icon is Enhancer's texture")
	player.money = 2
	shop._on_picked()
	check(client.campaign.checks.is_empty() and player.money == 2, "insufficient funds unchanged")
	player.money = 50
	shop.make_free()
	check(not shop.paid, "theft cannot create a free check or local upgrade")
	shop._on_picked()
	check(player.money == 40 and shop.paid, "paid shipment charges exactly once")
	check(shop.finalized and reward.deleted, "vanilla reward suppressed and offer finalized")
	check(shop.vanilla_purchases == 1, "no vanilla bodypart handoff")
	shop._on_picked()
	check(player.money == 40 and client.campaign.checks.size() == 1, "repeat signal idempotent")
	messages = await _collect(peer, 10)
	var sent: Array = _find(messages, "LocationChecks").get("locations", [])
	check(sent.size() == 1 and int(sent[0]) == 402938001, "send actual LocationChecks")
	_send(peer, [{"cmd": "RoomUpdate", "checked_locations": [402938001]}])
	await _collect(peer, 10)
	check(client.campaign.confirmed == [402938001], "server acknowledgement saved")
	var item_room: Node2D = load("res://scn/environ/rooms/special/item_room.gd").new()
	item_room.name = "ItemRoom"
	root.add_child(item_room)
	var choice := Node2D.new()
	choice.name = "BodypartReward3Choice"
	item_room.add_child(choice)
	var free: Array = []
	for slot_name in ["Reward", "Reward2"]:
		var holder := Node2D.new()
		holder.name = slot_name
		choice.add_child(holder)
		var free_reward: Node2D = load("res://scn/environ/pickups/bodypart_reward.gd").new()
		free_reward.choose_one = true
		free_reward.picked_up.connect(item_room._on_reward_picked_up)
		free.append(free_reward)
	for free_reward in free:
		free_reward.unique_from = free
	for i in free.size():
		choice.get_child(i).add_child(free[i])
	await process_frame
	check(free[0].has_meta("multiworldgg_free") and not free[1].has_meta("multiworldgg_free"),
			"blue item room gets exactly one remote unlock")
	client._refresh_offers()
	client._mask_rewards()
	check(free[0].get_node("%Label").text == "Remote Unlock 2/5" and free[1].get_node("%Label").text == "Pressurized Spicule",
			"item-room remote unlock renamed, other choice untouched")
	check(free[0].get_node("%MutationIcon").texture == client.remote_icon and not free[0].bodypart.visible,
			"item-room remote unlock shows the Enhancer icon")
	var coins: int = player.money
	free[0].pickup_area.picked.emit()
	check(free[0].vanilla_picks == 0 and free[0].deleted and free[1].consumed and item_room.looted,
			"item-room pick grants nothing locally and consumes the choice")
	check(player.money == coins and client.campaign.checks.size() == 2, "item-room remote unlock is free and sends the next check")
	messages = await _collect(peer, 10)
	sent = _find(messages, "LocationChecks").get("locations", [])
	check(402938002 in sent.map(func(l): return int(l)), "item-room check sent to the server")
	var boss_free: Array = []
	for room_type in [1, 0]:
		var boss_room: Node2D = load("res://tests/stubs/room.gd").new()
		boss_room.name = "BossRoom" if room_type == 1 else "NormalRoom"
		boss_room.res.type = room_type
		root.add_child(boss_room)
		var group := Node2D.new()
		group.name = "BodypartReward3Choice"
		boss_room.add_child(group)
		var rewards: Array = []
		for slot_name in ["Reward", "Reward2", "Reward3"]:
			var holder := Node2D.new()
			holder.name = slot_name
			group.add_child(holder)
			var boss_reward: Node2D = load("res://scn/environ/pickups/bodypart_reward.gd").new()
			boss_reward.choose_one = true
			rewards.append(boss_reward)
		for boss_reward_ref in rewards:
			boss_reward_ref.unique_from = rewards
		for i in rewards.size():
			group.get_child(i).add_child(rewards[i])
		boss_free.append(rewards)
	await process_frame
	var boss: Array = boss_free[0]
	check(boss[0].has_meta("multiworldgg_free") and not boss[1].has_meta("multiworldgg_free")
			and not boss[2].has_meta("multiworldgg_free"), "boss reward choice gets exactly one remote unlock")
	check(boss_free[1].all(func(r): return not r.has_meta("multiworldgg_free")), "non-boss rooms stay vanilla")
	client._refresh_offers()
	client._mask_rewards()
	check(boss[0].get_node("%Label").text == "Remote Unlock 3/5" and boss[0].get_node("%MutationIcon").texture == client.remote_icon,
			"boss remote unlock renamed with the Enhancer icon")
	boss[0].pickup_area.picked.emit()
	check(boss[0].vanilla_picks == 0 and boss[0].deleted and boss[1].consumed and boss[2].consumed,
			"boss pick grants nothing locally and consumes the other choices")
	check(player.money == coins and client.campaign.checks.size() == 3, "boss remote unlock is free and sends the next check")
	messages = await _collect(peer, 10)
	sent = _find(messages, "LocationChecks").get("locations", [])
	check(402938003 in sent.map(func(l): return int(l)), "boss check sent to the server")
	var editor: Control = load("res://tests/stubs/editor.gd").new()
	root.get_node("G").editor = editor
	root.add_child(editor)
	editor.draft(["A", "C", "G", "T"])
	var vanilla_last: Resource = editor.mutations[3]
	await process_frame
	await process_frame
	var level_button: TextureButton = editor.mutation_buttons[3]
	check(editor.mutations[3] != vanilla_last and editor.mutations[3] == client.level_card
			and level_button.texture_normal == client._remote_card_texture(), "level-up draft's last card becomes a remote unlock")
	check(editor.mutations.slice(0, 3).map(func(m): return m.resource_name) == ["A", "C", "G"], "other level-up cards stay vanilla")
	var level_tooltip: Control = editor.get_node("%MutationTooltip")
	level_tooltip.visible = true
	level_tooltip.item = editor.mutations[3]
	await process_frame
	check(level_tooltip.item is Dictionary and level_tooltip.item.name == "Remote Unlock 4/5", "level-up remote unlock tooltip")
	editor.mutation_buttons[0].pressed.emit()
	check(editor.vanilla_presses == [0] and editor.committed.is_empty(), "other level-up cards still use the game's handler")
	level_button.pressed.emit()
	await process_frame
	await process_frame
	check(editor.vanilla_presses == [0] and editor.committed.size() == 1 and editor.committed[0] != client.level_card
			and client.campaign.checks.size() == 4, "level-up remote unlock commits the skip gene and sends the next check")
	messages = await _collect(peer, 10)
	sent = _find(messages, "LocationChecks").get("locations", [])
	check(402938004 in sent.map(func(l): return int(l)), "level-up check sent to the server")
	editor.draft(["A2", "C2", "G2", "T2"])
	await process_frame
	check(editor.mutations[3] == client.level_card and editor.mutations[3].resource_name != "T2", "reroll/next level gets a fresh remote unlock")
	check(Client.parse_sources({"schema": 1}).values().all(func(v): return v), "schema 1 slots enable every source")
	check(Client.parse_sources({"schema": 2, "sources": {"shops": false, "item_rooms": true,
			"boss_rewards": false, "level_ups": false}}).item_rooms == true, "schema 2 sources parsed")
	check(Client.parse_sources({"schema": 2, "sources": {"shops": false, "item_rooms": false,
			"boss_rewards": false, "level_ups": false}}) == null, "slot with no sources rejected")
	check(Client.parse_sources({"schema": 2, "sources": {"shops": 1}}) == null, "malformed sources rejected")
	client.sources = {"shops": false, "item_rooms": true, "boss_rewards": false, "level_ups": false}
	editor.draft(["A3", "C3", "G3", "T3"])
	await process_frame
	check(editor.mutations[3].resource_name == "T3" and client.level_card == null, "level_ups=false keeps the draft vanilla")
	var gated_shop_room: Node = load("res://scn/environ/rooms/special/shop.gd").new()
	root.add_child(gated_shop_room)
	var gated_shop: Node = _pedestal(gated_shop_room, "Item1", true)
	var gated_rooms: Array = []
	for script_path in ["res://scn/environ/rooms/special/item_room.gd", "res://tests/stubs/room.gd"]:
		var gated_room: Node2D = load(script_path).new()
		if script_path.ends_with("room.gd") and not script_path.ends_with("item_room.gd"):
			gated_room.res.type = 1
		root.add_child(gated_room)
		var gated_reward: Node2D = load("res://scn/environ/pickups/bodypart_reward.gd").new()
		gated_reward.unique_from = [gated_reward]
		gated_room.add_child(gated_reward)
		gated_rooms.append(gated_reward)
	await process_frame
	check(not client.is_multiworld(gated_shop), "shop_unlocks=false keeps shops vanilla")
	check(client.is_free_multiworld(gated_rooms[0]), "item_room_unlocks=true keeps item-room remote unlocks")
	check(not client.is_free_multiworld(gated_rooms[1]), "boss_reward_unlocks=false keeps boss rewards vanilla")
	gated_rooms[1].pickup_area.picked.emit()
	check(gated_rooms[1].vanilla_picks == 1 and client.campaign.checks.size() == 4, "disabled boss reward picks normally")
	client.sources = {"shops": true, "item_rooms": true, "boss_rewards": true, "level_ups": true}
	gated_shop_room.queue_free()
	editor.mutations[3] = null
	editor.queue_free()
	var grants := [{"item": 402939001, "location": 100, "player": 2, "flags": 0}]
	client.player_seen = player.get_instance_id()
	client.settled_player = 0
	client.player_age = 0.0
	_send(peer, [{"cmd": "ReceivedItems", "index": 0, "items": grants}])
	await _collect(peer, 10)
	check(player.money == 40 and client.campaign.bank == 1, "grant waits until the run's player has settled")
	client.player_age = 1.99
	await create_timer(0.7).timeout
	check(player.money == 55 and client.campaign.bank == 0, "grant auto-redeems 15 coins without a button")
	check(client.toast.visible and client.toast.text == "MultiworldGG: received 1 Research Grant: +15 coins",
			"auto-redeemed grant shown in the blue toast")
	_send(peer, [{"cmd": "ReceivedItems", "index": 0, "items": grants}])
	await _collect(peer, 10)
	check(client.campaign.bank == 0, "network replay does not duplicate grant")
	_send(peer, [{"cmd": "RoomUpdate", "checked_locations": range(402938001, 402938006)}])
	messages = await _collect(peer, 10)
	check(_find(messages, "StatusUpdate").get("status") == 30, "goal only after every server-confirmed check")
	peer.close()
	for i in 15:
		peer.poll()
		await process_frame
	check(not client.authenticated, "disconnect blocks transactions")
	tcp.stop()

func _pedestal(room: Node, pedestal_name: String, with_reward: bool) -> Node:
	var pedestal: Node = load("res://mods-unpacked/ViMaSter-MultiworldGGShop/shop_item.gd").new()
	pedestal.name = pedestal_name
	room.add_child(pedestal)
	pedestal.add_to_group("shop_item")
	if with_reward:
		var item: Node = load("res://tests/stubs/reward.gd").new()
		pedestal.add_child(item)
		pedestal._rewards.append(item)
	return pedestal

func _send(peer: WebSocketPeer, messages: Array) -> void:
	check(peer.send_text(JSON.stringify(messages)) == OK, "fixture sends packet")

func _collect(peer: WebSocketPeer, frames: int) -> Array:
	var messages: Array = []
	for i in frames:
		peer.poll()
		while peer.get_available_packet_count() > 0:
			messages.append_array(JSON.parse_string(peer.get_packet().get_string_from_utf8()))
		await process_frame
	return messages

func _find(messages: Array, command: String) -> Dictionary:
	for message in messages:
		if message.get("cmd") == command:
			return message
	return {}
