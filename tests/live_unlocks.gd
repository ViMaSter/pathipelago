extends SceneTree

const Client = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/client.gd")
const Unlocks = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/unlocks.gd")
const Isolation = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/isolation.gd")

class GoalClient extends Client:
	var goal_updates := 0
	func _send(message: Dictionary) -> bool:
		if message.get("cmd") == "StatusUpdate" and message.get("status") == 30:
			goal_updates += 1
		return super(message)

func _init() -> void:
	run.call_deferred()

func wait_for(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while not predicate.call():
		if Time.get_ticks_msec() >= deadline:
			return false
		await process_frame
	return true

func run() -> void:
	var passed: bool = await live()
	print("GODOT_TEST_RESULT live_unlocks=true failures=", 0 if passed else 1)
	quit(0 if passed else 1)

func live() -> bool:
	var args := OS.get_cmdline_user_args()
	if OS.get_user_data_dir() != args[0]:
		return false
	Unlocks.hooks_ready = true
	var client := GoalClient.new()
	client.name = "MultiworldGGShop"
	root.add_child(client)
	client.set_enabled(true)
	client.server = args[1]
	client.slot_name = "Pathogenic2"
	client.connect_server()
	if not await wait_for(func(): return client.campaign_ready() and not Unlocks.owned.is_empty()):
		push_error("TEST FAILED: real remote unlock did not synchronize")
		return false
	var identity := Isolation.identity
	var received := Unlocks.owned.keys()
	if client.campaign.bank != 0 or received.size() != 1:
		push_error("TEST FAILED: remote unlock was converted into currency or duplicated")
		return false
	var natural := -1
	for id in Unlocks.selected:
		if not id in received:
			natural = id
			break
	client.earn_unlock(natural)
	if not await wait_for(func(): return Unlocks.received(natural) and client.campaign.confirmed_unlocks.size() == 1):
		push_error("TEST FAILED: native acquisition was not confirmed by the real server")
		return false
	if not client.campaign.confirmed.is_empty() or client.campaign.bank != 0:
		push_error("TEST FAILED: optional native feat advanced shipments or minted a grant")
		return false
	client.connect_server()
	if not await wait_for(func(): return client.campaign_ready() and Unlocks.received(natural)):
		push_error("TEST FAILED: unlock reconnect did not restore server entitlements")
		return false
	if not Unlocks.received(received[0]) or client.campaign.bank != 0 or Isolation.identity != identity:
		push_error("TEST FAILED: replay changed unlock ownership, currency, or profile")
		return false
	if client.required_victories != 1:
		push_error("TEST FAILED: live fixture needs one required victory")
		return false
	while client.campaign.next_location() >= 0:
		if not client.campaign.purchase(client.campaign.next_location()):
			push_error("TEST FAILED: could not persist live shipment: " + client.campaign.error)
			return false
	client._send_checks()
	if not await wait_for(func(): return client.campaign.confirmed.size() == client.count):
		push_error("TEST FAILED: live shipments were not confirmed")
		return false
	if client.goal_updates != 0:
		push_error("TEST FAILED: server goal was sent before required victory")
		return false
	var globals: Node = root.get_node("G")
	var main := Node.new()
	var player: Node = load("res://tests/stubs/player.gd").new()
	root.add_child(main)
	root.add_child(player)
	globals.main = main
	globals.player = player
	client.begin_run()
	var hook: Node = load("res://mods-unpacked/ViMaSter-MultiworldGGShop/run_save_manager.gd").new()
	root.add_child(hook)
	hook.record_run(true)
	hook.record_run(true)
	if not await wait_for(func(): return "\n".join(client.log_lines).contains("completed their goal")):
		push_error("TEST FAILED: real server did not announce the victory-gated goal")
		return false
	client._accept_checks(client.campaign.confirmed.duplicate())
	if client.campaign.victories.size() != 1 or client.goal_updates != 1:
		push_error("TEST FAILED: live victory callback counted or sent twice")
		return false
	hook.free()
	client.socket.close()
	print("LIVE_MWGG_UNLOCK remote_delivery=true native_confirmation=true replay=true isolated_profile=true victory_goal=true")
	return true
