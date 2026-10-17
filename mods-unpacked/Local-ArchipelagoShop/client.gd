extends Node

const GAME := "Pathogenic Demo"
const FIRST_LOCATION := 402938001
const GRANT_ITEM := 402939001
const GRANT_COINS := 15
const ROOT := "user://archipelago_shop"
const State = preload("res://mods-unpacked/Local-ArchipelagoShop/state.gd")

var socket := WebSocketPeer.new()
var authenticated := false
var status := "F8: configure Archipelago. AP shop purchases require a connection."
var server := "ws://localhost:38281"
var slot_name := ""
var password := ""
var team := -1
var slot := -1
var seed_name := ""
var count := 0
var campaign: RefCounted
var scouts: Dictionary = {}
var players: Dictionary = {}
var item_names: Dictionary = {}
var panel: PanelContainer
var status_label: Label
var address_field: LineEdit
var slot_field: LineEdit
var password_field: LineEdit
var bank_button: Button
var refresh_time := 0.0
var retry_time := 0.0
var connecting := false
var room_seen := false
var item_stream: Array = []
var item_stream_ready := false
var fatal := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DirAccess.make_dir_recursive_absolute(ROOT) != OK:
		_fail("Cannot create AP campaign directory.")
	_build_ui()
	var config := ConfigFile.new()
	var err := config.load(ROOT + "/connection.cfg")
	if err == OK:
		server = str(config.get_value("connection", "server", server))
		slot_name = str(config.get_value("connection", "slot", ""))
	elif err != ERR_FILE_NOT_FOUND:
		_fail("Cannot read AP connection configuration: " + error_string(err))
	address_field.text = server
	slot_field.text = slot_name
	notify(status)
	if not slot_name.is_empty() and not fatal:
		connect_server()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var box := VBoxContainer.new()
	panel = PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(640, 0)
	layer.add_child(panel)
	panel.add_child(box)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = 620
	box.add_child(status_label)
	address_field = _field(box, "Server URL: ws://host:port or wss://host:port")
	slot_field = _field(box, "Slot name (not the server's player alias)")
	password_field = _field(box, "Server password (not saved)")
	password_field.secret = true
	var connect_button := Button.new()
	connect_button.text = "Connect / reconnect"
	connect_button.pressed.connect(connect_server)
	box.add_child(connect_button)
	bank_button = Button.new()
	bank_button.text = "Redeem received Research Grants in this run"
	bank_button.pressed.connect(redeem_grants)
	box.add_child(bank_button)
	var hint := Label.new()
	hint.text = "F8 hides/shows this panel. Campaign survives new runs. No DeathLink."
	box.add_child(hint)

func _field(box: VBoxContainer, hint: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = hint
	box.add_child(field)
	return field

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()

func notify(message: String) -> void:
	status = message
	if is_instance_valid(status_label):
		status_label.text = "Archipelago Shop: " + message
	print("[ArchipelagoShop] ", message)

func _fail(message: String) -> void:
	fatal = true
	authenticated = false
	push_error("[ArchipelagoShop] " + message)
	notify(message + " Purchases are blocked; see the game log.")

func connect_server() -> void:
	if fatal:
		notify("Restart after resolving the campaign/configuration error in the log.")
		return
	server = address_field.text.strip_edges()
	slot_name = slot_field.text.strip_edges()
	password = password_field.text
	if not (server.begins_with("ws://") or server.begins_with("wss://")) or slot_name.is_empty():
		notify("Enter a ws:// or wss:// server URL and a nonempty slot name.")
		return
	var config := ConfigFile.new()
	config.set_value("connection", "server", server)
	config.set_value("connection", "slot", slot_name)
	var err := config.save(ROOT + "/connection.cfg")
	if err != OK:
		_fail("Could not save connection configuration: " + error_string(err))
		return
	socket.close()
	socket = WebSocketPeer.new()
	authenticated = false
	room_seen = false
	item_stream_ready = false
	item_stream.clear()
	scouts.clear()
	players.clear()
	item_names.clear()
	campaign = null
	err = socket.connect_to_url(server)
	if err != OK:
		notify("Connection failed: " + error_string(err))
		return
	connecting = true
	retry_time = 0.0
	notify("Connecting to " + server + " as " + slot_name)

func _process(delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while socket.get_available_packet_count() > 0:
			var parser := JSON.new()
			var err := parser.parse(socket.get_packet().get_string_from_utf8())
			if err != OK or not parser.data is Array:
				_fail("Malformed Archipelago packet.")
				socket.close()
				return
			for message in parser.data:
				if not message is Dictionary or not message.get("cmd") is String:
					_fail("Malformed Archipelago command.")
					socket.close()
					return
				_handle(message)
	elif state == WebSocketPeer.STATE_CLOSED and (connecting or authenticated):
		connecting = false
		authenticated = false
		item_stream_ready = false
		notify("Disconnected. Purchases blocked. Use F8 to reconnect; checks will be resent.")
	if authenticated and not fatal:
		retry_time += delta
		if retry_time >= 5.0:
			retry_time = 0.0
			_send_checks()
	refresh_time += delta
	if refresh_time >= 0.5:
		refresh_time = 0.0
		_refresh_offers()

func _send(message: Dictionary) -> bool:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var err := socket.send_text(JSON.stringify([message]))
	if err != OK:
		authenticated = false
		notify("Network send failed: " + error_string(err) + ". Reconnect with F8.")
		return false
	return true

func _handle(message: Dictionary) -> void:
	match message.cmd:
		"RoomInfo":
			if room_seen:
				return
			room_seen = true
			if not message.get("seed_name") is String:
				_fail("Server did not provide a seed name.")
				return
			seed_name = message.seed_name
			_send({
				"cmd": "Connect", "game": GAME, "name": slot_name,
				"password": null if password.is_empty() else password,
				"uuid": (OS.get_unique_id() + slot_name).sha256_text(),
				"version": {"major": 0, "minor": 6, "build": 0, "class": "Version"},
				"items_handling": 7, "tags": ["AP"], "slot_data": true
			})
		"ConnectionRefused":
			notify("Server refused connection: " + str(message.get("errors", [])))
			socket.close()
		"Connected":
			_connected(message)
		"RoomUpdate":
			if not authenticated:
				return
			_update_players(message.get("players", []))
			if fatal:
				return
			if message.has("checked_locations"):
				_accept_checks(message.checked_locations)
		"LocationInfo":
			if not authenticated:
				return
			if not message.get("locations") is Array:
				_fail("Malformed scout response.")
				return
			for item in message.locations:
				if not item is Dictionary or not State.integer(item.get("location")) \
						or not State.integer(item.get("item")) or not State.integer(item.get("player")):
					_fail("Malformed scout item.")
					return
				scouts[int(item.location)] = item
		"DataPackage":
			var data: Variant = message.get("data", {})
			if not data is Dictionary or not data.get("games") is Dictionary:
				_fail("Malformed data package.")
				return
			for game in data.games.values():
				if not game is Dictionary or not game.get("item_name_to_id") is Dictionary:
					_fail("Malformed item-name data package.")
					return
				for item_name in game.item_name_to_id:
					if not State.integer(game.item_name_to_id[item_name]):
						_fail("Malformed data-package item ID.")
						return
					item_names[int(game.item_name_to_id[item_name])] = item_name
		"ReceivedItems":
			_received(message)
		"InvalidPacket":
			_fail("Server rejected a protocol packet: " + str(message.get("text", message.get("type", ""))))

func _connected(message: Dictionary) -> void:
	var data: Variant = message.get("slot_data")
	if not State.integer(message.get("team")) or not State.integer(message.get("slot")) \
			or not data is Dictionary or not State.integer(data.get("shop_checks")) \
			or not State.integer(data.get("schema")) or int(data.schema) != 1 or int(data.shop_checks) < 1 \
			or int(data.shop_checks) > 100:
		_fail("Incompatible slot data. Generate with the bundled Pathogenic Demo APWorld.")
		socket.close()
		return
	team = int(message.team)
	slot = int(message.slot)
	count = int(data.shop_checks)
	var identity := JSON.stringify([seed_name, team, slot])
	campaign = State.new()
	if not campaign.open(ROOT + "/" + identity.sha256_text() + ".json", identity, count):
		_fail(campaign.error)
		return
	var missing: Variant = message.get("missing_locations")
	var checked: Variant = message.get("checked_locations")
	if not missing is Array or not checked is Array:
		_fail("Missing server location inventory.")
		return
	var inventory := {}
	for location in missing + checked:
		if not State.integer(location):
			_fail("Malformed server location inventory.")
			return
		inventory[int(location)] = true
	for i in count:
		if not inventory.has(FIRST_LOCATION + i):
			_fail("Server location inventory does not match this APWorld.")
			return
	_update_players(message.get("players", []))
	if fatal:
		return
	authenticated = true
	connecting = false
	_accept_checks(checked)
	if fatal:
		return
	_send({"cmd": "GetDataPackage"})
	_send({"cmd": "LocationScouts", "locations": range(FIRST_LOCATION, FIRST_LOCATION + count), "create_as_hint": 0})
	_send({"cmd": "Sync"})
	_send_checks()
	notify("Connected. %d/%d checks confirmed. Shop shipments replace local upgrades." % [campaign.confirmed.size(), count])

func _update_players(list: Variant) -> void:
	if not list is Array:
		_fail("Malformed server player list.")
		return
	for player in list:
		if not player is Dictionary or not State.integer(player.get("team")) \
				or not State.integer(player.get("slot")):
			_fail("Malformed server player record.")
			return
		if int(player.team) == team:
			players[int(player.slot)] = str(player.get("alias", player.get("name", player.slot)))

func _accept_checks(list: Variant) -> void:
	if not list is Array:
		_fail("Malformed checked-location list.")
		return
	if not campaign.accept_checks(list):
		_fail(campaign.error)
		return
	if campaign.confirmed.size() == count:
		_send({"cmd": "StatusUpdate", "status": 30})

func _received(message: Dictionary) -> void:
	if not authenticated:
		return
	if not State.integer(message.get("index")) or int(message.index) < 0 \
			or not message.get("items") is Array:
		_fail("Malformed received-item stream.")
		return
	var index := int(message.index)
	if index == 0:
		item_stream.clear()
		item_stream_ready = true
	if not item_stream_ready or index > item_stream.size():
		item_stream_ready = false
		_send({"cmd": "Sync"})
		return
	for offset in message.items.size():
		var item: Variant = message.items[offset]
		if not item is Dictionary or not State.integer(item.get("item")):
			_fail("Malformed received item.")
			return
		var position: int = index + offset
		if position < item_stream.size():
			if item_stream[position] != item:
				_fail("Received-item history changed for this campaign.")
				return
		else:
			item_stream.append(item)
	if not campaign.accept_items(item_stream):
		_fail(campaign.error)

func _send_checks() -> void:
	if campaign != null and not campaign.checks.is_empty():
		_send({"cmd": "LocationChecks", "locations": campaign.checks})

func eligible(shop: Node) -> bool:
	if shop.pay_with_blood or shop._rewards.is_empty():
		return false
	for reward in shop._rewards:
		if is_instance_valid(reward) and reward.choose_one:
			return false
	for child in shop.get_children():
		if child.get("attract") != null:
			return false
	var ancestor := shop.get_parent()
	while ancestor != null:
		var script: Script = ancestor.get_script()
		if script != null and script.resource_path == "res://scn/environ/rooms/special/shop.gd":
			return true
		ancestor = ancestor.get_parent()
	return false

func purchase(shop: Node) -> void:
	if shop.paid:
		return
	if fatal or not authenticated or campaign == null:
		notify("Purchase blocked: connect to your AP slot with F8 first.")
		return
	var location: int = campaign.next_location()
	if location < 0:
		notify("All AP checks purchased. Waiting for confirmation, or campaign complete.")
		return
	if not scouts.has(location) or not item_names.has(int(scouts[location].item)):
		notify("Purchase blocked: waiting for item and recipient scouting data.")
		return
	var globals := get_node("/root/G")
	var player: Node = globals.player
	if not is_instance_valid(player) or int(player.money) < int(shop.cost):
		notify("Not enough money for this AP shipment.")
		return
	# Persist the location before charging. A crash between the two saves can
	# forgive payment, but cannot lose or duplicate an Archipelago check.
	if not campaign.purchase(location):
		_fail(campaign.error)
		return
	player.money -= shop.cost
	shop.pending_refund = 0
	shop.paid = true
	for reward in shop._rewards:
		if is_instance_valid(reward):
			reward.consumed = true
			reward.deleted = true
			reward.queue_free()
	shop.finalize_purchase()
	var label := shop.get_node_or_null("ArchipelagoOffer")
	if label != null:
		label.queue_free()
	get_node("/root/RunSaveManager").save_run()
	_send_checks()
	notify("Shipment queued: " + _offer_text(location) + ". Waiting for server confirmation.")

func _offer_text(location: int) -> String:
	if not scouts.has(location):
		return "Check %d (waiting for scout)" % (location - FIRST_LOCATION + 1)
	var item: Dictionary = scouts[location]
	return "#%d: %s -> %s" % [
		location - FIRST_LOCATION + 1,
		str(item_names.get(int(item.item), "Item " + str(item.item))),
		str(players.get(int(item.player), "Player " + str(item.player)))
	]

func _refresh_offers() -> void:
	for shop in get_tree().get_nodes_in_group("shop_item"):
		if not is_instance_valid(shop) or not eligible(shop) or shop.paid:
			continue
		var label := shop.get_node_or_null("ArchipelagoOffer") as Label
		if label == null:
			label = Label.new()
			label.name = "ArchipelagoOffer"
			label.position = Vector2(-230, -190)
			label.custom_minimum_size = Vector2(460, 0)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
			shop.add_child(label)
		if authenticated and campaign != null:
			var location: int = campaign.next_location()
			label.text = "AP " + _offer_text(location) if location >= 0 else "AP campaign: no checks remaining"
		else:
			label.text = "AP shipment (connect with F8)"
	if campaign != null and is_instance_valid(bank_button):
		bank_button.text = "Redeem %d Research Grants (+%d coins) in this run" % [campaign.bank, campaign.bank * GRANT_COINS]

func redeem_grants() -> void:
	if fatal or not authenticated or not item_stream_ready or campaign == null or campaign.bank == 0:
		notify("No synchronized Research Grants available.")
		return
	var globals := get_node("/root/G")
	var player: Node = globals.player
	if not is_instance_valid(player) or player.dead:
		notify("Start a living run before redeeming grants.")
		return
	var amount: int = campaign.bank
	if not campaign.redeem():
		_fail(campaign.error)
		return
	player.money += amount * GRANT_COINS
	get_node("/root/RunSaveManager").save_run()
	notify("Redeemed %d Research Grants. +%d coins." % [amount, amount * GRANT_COINS])
