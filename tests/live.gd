extends SceneTree

const Client = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/client.gd")

func _init() -> void:
	_run.call_deferred()

func _wait_for(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while not predicate.call():
		if Time.get_ticks_msec() > deadline:
			push_error("TEST FAILED: live server condition timed out")
			return false
		await process_frame
	return true

func _run() -> void:
	var passed: bool = await _live()
	print("GODOT_TEST_RESULT live_multiworldgg=true failures=", 0 if passed else 1)
	quit(0 if passed else 1)

func _live() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or OS.get_user_data_dir() != args[0]:
		push_error("TEST FAILED: live test requires isolated saves and explicit server")
		return false
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
	root.add_child(room)
	var sender := Client.new()
	sender.name = "MultiworldGGShop"
	var receiver := Client.new()
	receiver.name = "Receiver"
	root.add_child(sender)
	root.add_child(receiver)
	await process_frame
	for pair in [[sender, "Pathogenic1"], [receiver, "Pathogenic2"]]:
		pair[0].set_enabled(true)
		pair[0].begin_run()
		pair[0].server = args[1]
		pair[0].slot_name = pair[1]
		pair[0].connect_server()
	if not await _wait_for(func(): return sender.authenticated and receiver.authenticated \
			and sender.scouts.has(402938002) and sender.item_names.get("Pathogenic", {}).has(402939001)):
		return false
	if sender.campaign.checks.size() != 0 or receiver.campaign.bank != 0 \
			or int(sender.scouts[402938002].player) != receiver.slot:
		push_error("TEST FAILED: need fresh seed with shipment 2 addressed to Pathogenic2")
		return false
	var received_before: int = receiver.campaign.received.size()
	var start_money: int = player.money
	for index in 2:
		var shop_room: Node = load("res://scn/environ/rooms/special/shop.gd").new()
		root.add_child(shop_room)
		var shop: Node = load("res://mods-unpacked/ViMaSter-MultiworldGGShop/shop_item.gd").new()
		shop_room.add_child(shop)
		shop.add_to_group("shop_item")
		var reward: Node = load("res://tests/stubs/reward.gd").new()
		shop.add_child(reward)
		shop._rewards.append(reward)
		var money_before: int = player.money
		shop._on_picked()
		if player.money != money_before - 10 or not shop.finalized \
				or not reward.deleted or shop.vanilla_purchases != 0:
			push_error("TEST FAILED: live purchase debit or local reward suppression")
			return false
		var expected: int = index + 1
		if not await _wait_for(func(): return sender.campaign.confirmed.size() == expected):
			return false
		await create_timer(0.1).timeout
	receiver.player_seen = player.get_instance_id()
	receiver.settled_player = player.get_instance_id()
	if not await _wait_for(func(): return receiver.campaign.received.size() > received_before \
			and receiver.campaign.bank == 0):
		return false
	var granted: int = receiver.campaign.received.size() - received_before
	print("LIVE_MWGG_CROSS_PLAYER sender=", sender.slot, " check=402938002 recipient=",
		receiver.slot, " auto_redeemed=", granted)
	if player.money != start_money - 20 + 15 * granted:
		push_error("TEST FAILED: received grants did not auto-redeem")
		return false
	receiver.connect_server()
	if not await _wait_for(func(): return receiver.authenticated and receiver.item_stream_ready):
		return false
	if receiver.campaign.bank != 0:
		push_error("TEST FAILED: server replay duplicated redeemed items")
		return false
	print("LIVE_MWGG_RECONNECT replay_preserved=true")
	sender.socket.close()
	receiver.socket.close()
	return true
