extends SceneTree

const State = preload("res://mods-unpacked/Local-ArchipelagoShop/state.gd")
const Client = preload("res://mods-unpacked/Local-ArchipelagoShop/client.gd")
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
	var client := Client.new()
	client.name = "ArchipelagoShop"
	root.add_child(client)
	await process_frame
	check(client.is_ap(shop), "first bodypart pedestal is the AP pedestal")
	check(not client.is_ap(second) and not client.is_ap(pickups), "exactly one AP pedestal per shop")
	second._on_picked()
	check(second.vanilla_purchases == 1, "other pedestals stay vanilla local purchases")
	shop._on_picked()
	check(player.money == 50 and shop.vanilla_purchases == 0, "offline AP buy neither charges nor grants vanilla")
	shop.pay_with_blood = true
	shop._on_picked()
	check(shop.vanilla_purchases == 1, "blood purchase stays vanilla")
	shop.pay_with_blood = false
	var challenge_room: Node = load("res://scn/environ/rooms/special/shop.gd").new()
	root.add_child(challenge_room)
	var choose: Node = _pedestal(challenge_room, "Item1", true)
	choose._rewards[0].choose_one = true
	var fallback: Node = _pedestal(challenge_room, "Item2", true)
	check(not client.is_ap(choose) and client.is_ap(fallback), "choose-one pedestal skipped for designation")
	var orphan: Node = load("res://mods-unpacked/Local-ArchipelagoShop/shop_item.gd").new()
	root.add_child(orphan)
	check(not client.is_ap(orphan), "pedestals outside shop rooms stay vanilla")
	var log_text := FileAccess.get_file_as_string("user://archipelago_shop/client.log")
	check(log_text.contains("Shop pick ShopRoom/Item2") and log_text.contains("vanilla local purchase") \
			and log_text.contains("-> ARCHIPELAGO"), "every pick is written to the flushed client log")
	var menu: Node = load("res://scn/ui/options_menu.gd").new()
	root.add_child(menu)
	await process_frame
	await process_frame
	check(menu.tab_buttons.size() == 3 and menu.tab_buttons[2].text == "Archipelago", "settings tab injected")
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
	check(connect_message.get("game") == "Pathogenic Demo", "real AP handshake game")
	check(connect_message.get("items_handling") == 7, "request local, remote, starting items")
	_send(peer, [{
		"cmd": "Connected", "team": 0, "slot": 1,
		"players": [{"team": 0, "slot": 2, "alias": "Remote Friend"}],
		"slot_info": {"1": {"name": "Tester", "game": "Pathogenic Demo"}, "2": {"name": "Friend", "game": "Example"}},
		"missing_locations": range(402938001, 402938006),
		"checked_locations": [], "slot_data": {"schema": 1, "shop_checks": 5}
	}, {
		"cmd": "DataPackage",
		"data": {"games": {"Example": {"item_name_to_id": {"Remote Sword": 9001}},
			"Other": {"item_name_to_id": {"Wrong Game Item": 9001}}}}
	}, {
		"cmd": "LocationInfo", "locations": [
			{"location": 402938001, "item": 9001, "player": 2, "flags": 1},
			{"location": 402938002, "item": 9001, "player": 2, "flags": 1}
		]
	}, {"cmd": "ReceivedItems", "index": 0, "items": []}])
	messages = await _collect(peer, 15)
	check(client.authenticated, "authenticate slot")
	check(not _find(messages, "LocationScouts").is_empty(), "scout finite location pool")
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
	var grants := [{"item": 402939001, "location": 100, "player": 2, "flags": 0}]
	_send(peer, [{"cmd": "ReceivedItems", "index": 0, "items": grants}])
	await _collect(peer, 10)
	client.redeem_grants()
	check(player.money == 55 and client.campaign.bank == 0, "grant delivers 15 coins")
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
	var pedestal: Node = load("res://mods-unpacked/Local-ArchipelagoShop/shop_item.gd").new()
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
