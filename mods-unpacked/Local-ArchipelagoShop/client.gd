extends Node

const GAME := "Pathogenic Demo"
const FIRST_LOCATION := 402938001
const GRANT_ITEM := 402939001
const GRANT_COINS := 15
const ROOT := "user://archipelago_shop"
const LOG_FILE := ROOT + "/client.log"
const LOG_LIMIT := 512 * 1024
const LOG_LINES := 200
const SHOP_ROOM_SCRIPT := "res://scn/environ/rooms/special/shop.gd"
const OPTIONS_SCRIPT := "res://scn/ui/options_menu.gd"
const TAB_TITLE := "Archipelago"
const FONT_SIZE := 18
const SMALL_FONT_SIZE := 12
const PAGE_MIN_HEIGHT := 300.0
const PAGE_MAX_HEIGHT := 640.0
const BUTTON_COLOR := Color(0.12, 0.42, 0.68)
const State = preload("res://mods-unpacked/Local-ArchipelagoShop/state.gd")

var socket := WebSocketPeer.new()
var authenticated := false
var status := "Open Settings > Archipelago to connect. The AP pedestal in each shop needs a connection."
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
var slot_games: Dictionary = {}
var item_names: Dictionary = {}
var refresh_time := 0.0
var retry_time := 0.0
var connecting := false
var room_seen := false
var item_stream: Array = []
var item_stream_ready := false
var fatal := false
var log_lines: PackedStringArray = []
var log_revision := 0
var pages: Array = []
var toast: Label
var toast_time := 0.0
var _log: FileAccess

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Run after the game UI so the tooltip override wins each frame.
	process_priority = 1000
	if DirAccess.make_dir_recursive_absolute(ROOT) != OK:
		_fail("Cannot create AP campaign directory.")
	_open_log()
	_build_toast()
	get_tree().node_added.connect(_on_node_added)
	var config := ConfigFile.new()
	var err := config.load(ROOT + "/connection.cfg")
	if err == OK:
		server = str(config.get_value("connection", "server", server))
		slot_name = str(config.get_value("connection", "slot", ""))
	elif err != ERR_FILE_NOT_FOUND:
		_fail("Cannot read AP connection configuration: " + error_string(err))
	log_line("Client log: " + ProjectSettings.globalize_path(LOG_FILE))
	notify(status)
	if not slot_name.is_empty() and not fatal:
		connect_server()

func _open_log() -> void:
	if FileAccess.file_exists(LOG_FILE) and FileAccess.open(LOG_FILE, FileAccess.READ).get_length() > LOG_LIMIT:
		DirAccess.rename_absolute(LOG_FILE, LOG_FILE + ".1")
	if FileAccess.file_exists(LOG_FILE):
		_log = FileAccess.open(LOG_FILE, FileAccess.READ_WRITE)
		if _log != null:
			_log.seek_end()
	else:
		_log = FileAccess.open(LOG_FILE, FileAccess.WRITE)
	if _log == null:
		push_error("[ArchipelagoShop] Cannot open client log: " + error_string(FileAccess.get_open_error()))

func log_line(message: String) -> void:
	var line := "%s %s" % [Time.get_datetime_string_from_system(), message]
	log_lines.append(line)
	if log_lines.size() > LOG_LINES:
		log_lines = log_lines.slice(log_lines.size() - LOG_LINES)
	log_revision += 1
	print("[ArchipelagoShop] ", message)
	if _log != null:
		_log.store_line(line)
		_log.flush()

func notify(message: String) -> void:
	status = message
	log_line(message)

func _fail(message: String) -> void:
	fatal = true
	authenticated = false
	push_error("[ArchipelagoShop] " + message)
	notify(message + " Purchases are blocked; see the client log.")

func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	toast = Label.new()
	toast.visible = false
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.position = Vector2(24, 24)
	toast.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.add_theme_constant_override("outline_size", 6)
	layer.add_child(toast)

func show_toast(message: String) -> void:
	if is_instance_valid(toast):
		toast.text = "Archipelago: " + message
		toast.visible = true
		toast_time = 5.0

func connect_server() -> void:
	if fatal:
		notify("Restart after resolving the campaign/configuration error in the log.")
		return
	server = server.strip_edges()
	slot_name = slot_name.strip_edges()
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
	slot_games.clear()
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
		notify("Disconnected (code %d). AP pedestals are blocked; reconnect in Settings > Archipelago." % socket.get_close_code())
	if authenticated and not fatal:
		retry_time += delta
		if retry_time >= 5.0:
			retry_time = 0.0
			_send_checks()
	if toast_time > 0.0:
		toast_time -= delta
		if toast_time <= 0.0 and is_instance_valid(toast):
			toast.visible = false
	_override_tooltip()
	refresh_time += delta
	if refresh_time >= 0.5:
		refresh_time = 0.0
		_refresh_offers()
		_refresh_pages()

func _send(message: Dictionary) -> bool:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var err := socket.send_text(JSON.stringify([message]))
	if err != OK:
		authenticated = false
		notify("Network send failed: " + error_string(err) + ". Reconnect in Settings > Archipelago.")
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
			notify("Server refused connection: " + str(message.get("errors", [])) \
				+ ". Use the slot name from the generated seed, not the server alias.")
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
				log_line("Server confirmed %d/%d checks." % [campaign.confirmed.size(), count])
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
			log_line("Scouted %d shop checks." % scouts.size())
		"DataPackage":
			var data: Variant = message.get("data", {})
			if not data is Dictionary or not data.get("games") is Dictionary:
				_fail("Malformed data package.")
				return
			for game_name in data.games:
				var game: Variant = data.games[game_name]
				if not game is Dictionary or not game.get("item_name_to_id") is Dictionary:
					_fail("Malformed item-name data package.")
					return
				var names := {}
				for item_name in game.item_name_to_id:
					if not State.integer(game.item_name_to_id[item_name]):
						_fail("Malformed data-package item ID.")
						return
					names[int(game.item_name_to_id[item_name])] = item_name
				item_names[str(game_name)] = names
		"ReceivedItems":
			_received(message)
		"PrintJSON":
			var parts: Variant = message.get("data", [])
			if parts is Array:
				var text := ""
				for part in parts:
					if part is Dictionary:
						text += _print_part(part)
				if not text.is_empty():
					log_line("Server: " + text)
		"InvalidPacket":
			_fail("Server rejected a protocol packet: " + str(message.get("text", message.get("type", ""))))

func _print_part(part: Dictionary) -> String:
	var text := str(part.get("text", ""))
	match str(part.get("type", "")):
		"player_id":
			return str(players.get(int(text), text)) if text.is_valid_int() else text
		"item_id":
			if text.is_valid_int():
				return _item_name(int(text), int(part.get("player", -1)))
		"location_id":
			if text.is_valid_int() and int(part.get("player", -1)) == slot:
				return location_name(int(text))
	return text

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
	var info: Variant = message.get("slot_info", {})
	if info is Dictionary:
		for key in info:
			if info[key] is Dictionary and str(key).is_valid_int():
				slot_games[int(key)] = str(info[key].get("game", ""))
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
	notify("Connected as %s (slot %d). %d/%d checks confirmed. Each shop has one AP pedestal." % [
		slot_name, slot, campaign.confirmed.size(), count])

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
	var before: int = campaign.bank
	if not campaign.accept_items(item_stream):
		_fail(campaign.error)
		return
	if campaign.bank > before:
		notify("Received %d Research Grant(s). Redeem them in Settings > Archipelago." % (campaign.bank - before))

func _send_checks() -> void:
	if campaign != null and not campaign.checks.is_empty():
		_send({"cmd": "LocationChecks", "locations": campaign.checks})

# --- Shop pedestals ---------------------------------------------------------

func shop_room(shop: Node) -> Node:
	var ancestor := shop.get_parent()
	while ancestor != null:
		var script: Script = ancestor.get_script()
		if script != null and script.resource_path == SHOP_ROOM_SCRIPT:
			return ancestor
		ancestor = ancestor.get_parent()
	return null

func _offers_bodypart(shop: Node) -> bool:
	if shop._rewards.is_empty():
		return false
	for reward in shop._rewards:
		if is_instance_valid(reward) and reward.choose_one:
			return false
	return true

# Exactly one pedestal per shop room is the AP pedestal: the first pedestal in
# name order that offers a bodypart, else the first currency pedestal. The
# choice is cached on the room instance so it stays put after the purchase.
func designated(room: Node) -> Node:
	if room.has_meta("archipelago_pedestal"):
		var cached: Variant = room.get_meta("archipelago_pedestal")
		return cached if is_instance_valid(cached) else null
	var candidates: Array = []
	for node in room.find_children("*", "", true, false):
		if node.has_method("finalize_purchase") and node.get("_rewards") != null \
				and not node.pay_with_blood and not node.is_queued_for_deletion() and shop_room(node) == room:
			candidates.append(node)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	var choice: Node = candidates[0]
	for node in candidates:
		if _offers_bodypart(node):
			choice = node
			break
	room.set_meta("archipelago_pedestal", choice)
	log_line("AP pedestal for shop room %s: %s" % [room.name, choice.name])
	return choice

func is_ap(shop: Node) -> bool:
	if not is_instance_valid(shop) or shop.pay_with_blood:
		return false
	if campaign != null and authenticated and campaign.next_location() < 0:
		return false
	var room := shop_room(shop)
	return room != null and designated(room) == shop

# Kept for callers/tests written against the earlier API.
func eligible(shop: Node) -> bool:
	return is_ap(shop)

# Returns true when the pick was consumed by the AP path; false lets the
# vanilla shop purchase run.
func handle_pick(shop: Node, theft := false) -> bool:
	var ap := is_ap(shop)
	var room := shop_room(shop)
	var globals := get_node_or_null("/root/G")
	var money: Variant = globals.player.money if globals != null and is_instance_valid(globals.player) else null
	log_line("Shop pick %s/%s cost=%s money=%s paid=%s blood=%s theft=%s -> %s" % [
		room.name if room != null else "-", shop.name, shop.cost, money, shop.paid,
		shop.pay_with_blood, theft, "ARCHIPELAGO" if ap else "vanilla local purchase"])
	if not ap:
		return false
	purchase(shop)
	return true

func _on_node_added(node: Node) -> void:
	var script: Script = node.get_script()
	if script == null:
		return
	if script.resource_path == OPTIONS_SCRIPT:
		_inject_tab.call_deferred(node)
	elif node.has_method("finalize_purchase") and node.get("_rewards") != null:
		_track_shop.call_deferred(node)

func _track_shop(shop: Node) -> void:
	if not is_instance_valid(shop) or shop.has_method("_ap_client"):
		return
	# The script takeover did not apply to this pedestal; route its picks here.
	var area := shop.get_node_or_null("PickupArea")
	if area == null or not area.has_signal("picked"):
		return
	if area.picked.is_connected(shop._on_picked):
		area.picked.disconnect(shop._on_picked)
	area.picked.connect(_fallback_pick.bind(shop))
	log_line("Takeover inactive on %s; picks rerouted through the client." % shop.name)

func _fallback_pick(shop: Node) -> void:
	if is_instance_valid(shop) and not handle_pick(shop):
		shop._on_picked()

func _error_sound() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.get("ui_error") != null:
		audio.ui_error.play()

func purchase(shop: Node) -> void:
	if shop.paid:
		return
	if fatal or not authenticated or campaign == null:
		_error_sound()
		show_toast("not connected - open Settings > Archipelago.")
		notify("AP pedestal blocked: not connected to an Archipelago slot.")
		return
	var location: int = campaign.next_location()
	if location < 0:
		notify("All AP checks purchased. Waiting for confirmation, or campaign complete.")
		return
	if not scouts.has(location):
		_error_sound()
		notify("AP pedestal blocked: waiting for scouting data from the server.")
		return
	var globals := get_node("/root/G")
	var player: Node = globals.player
	if not is_instance_valid(player) or int(player.money) < int(shop.cost):
		_error_sound()
		notify("Not enough money for this AP unlock.")
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
	for child in shop.get_children():
		if child.get("attract") != null:
			child.queue_free()
	shop.finalize_purchase()
	var label := shop.get_node_or_null("ArchipelagoOffer")
	if label != null:
		label.queue_free()
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.get("buy") != null:
		audio.buy.play()
	get_node("/root/RunSaveManager").save_run()
	_send_checks()
	show_toast("sent " + offer_text(location))
	notify("Sent %s: %s. Waiting for server confirmation." % [location_name(location), offer_text(location)])

func location_name(location: int) -> String:
	return "Shop Shipment %03d" % (location - FIRST_LOCATION + 1)

func _item_name(item: int, player: int) -> String:
	var game: String = slot_games.get(player, "")
	if item_names.has(game) and item_names[game].has(item):
		return str(item_names[game][item])
	for names in item_names.values():
		if names.has(item):
			return str(names[item])
	return "Item %d" % item

func offer_text(location: int) -> String:
	if not scouts.has(location):
		return "an external unlock for another multiworld player"
	var item: Dictionary = scouts[location]
	var player := int(item.player)
	var text := "%s for %s" % [_item_name(int(item.item), player), players.get(player, "Player %d" % player)]
	var game: String = slot_games.get(player, "")
	if not game.is_empty():
		text += " (" + game + ")"
	return text

# Backwards-compatible name used by older tests and docs.
func _offer_text(location: int) -> String:
	return offer_text(location)

func tooltip_title() -> String:
	if campaign == null or count <= 0:
		return "Remote Unlock"
	return "Remote Unlock %d/%d" % [mini(campaign.next_location() - FIRST_LOCATION + 1, count), count]

static func _bb(text: String) -> String:
	return "[color=#66e6ff]%s[/color]" % text.replace("[", "[lb]")

func tooltip_body() -> String:
	if fatal or not authenticated or campaign == null:
		return "[color=orange]Not connected: open Settings > Archipelago.[/color]"
	var location: int = campaign.next_location()
	if not scouts.has(location):
		return "An external unlock for another multiworld player."
	var item: Dictionary = scouts[location]
	var player := int(item.player)
	var body := "\"%s\" for %s" % [_bb(_item_name(int(item.item), player)), _bb(str(players.get(player, "Player %d" % player)))]
	var game: String = slot_games.get(player, "")
	if not game.is_empty():
		body += " (%s)" % _bb(game)
	return body

func tooltip_card() -> Dictionary:
	return {"name": tooltip_title(), "hint": tooltip_body(), "archipelago": true}

func _shop_wrapper(node: Node) -> Node:
	while node != null:
		if node.has_method("finalize_purchase") and node.get("_rewards") != null:
			return node
		node = node.get_parent()
	return null

func _override_tooltip() -> void:
	var globals := get_node_or_null("/root/G")
	if globals == null:
		return
	var ui: Variant = globals.get("ui")
	if not is_instance_valid(ui) or not is_instance_valid(ui.get("tooltip")):
		return
	var tooltip: Control = ui.tooltip
	var anchor: Variant = ui.get("tooltip_pos_node")
	if not tooltip.visible or not is_instance_valid(anchor):
		return
	var shop := _shop_wrapper(anchor)
	if shop == null or shop.paid or not is_ap(shop):
		return
	var card := tooltip_card()
	var current: Variant = tooltip.item
	if typeof(current) != TYPE_DICTIONARY or current != card:
		tooltip.item = card
		ui.set("_last_tooltip_item", card)
	var name_label := tooltip.get_node_or_null("%Name")
	if name_label != null and name_label.text != card.name:
		name_label.text = card.name
	var type_label := tooltip.get_node_or_null("%Type")
	if type_label != null and type_label.text != "ARCHIPELAGO":
		type_label.text = "ARCHIPELAGO"
		var panel := tooltip.get_node_or_null("%TypePanel")
		if panel != null:
			panel.self_modulate = Color(0.1, 0.35, 0.55, 1.0)

func _refresh_offers() -> void:
	for shop in get_tree().get_nodes_in_group("shop_item"):
		if not is_instance_valid(shop):
			continue
		var label := shop.get_node_or_null("ArchipelagoOffer") as Label
		if shop.paid or not is_ap(shop):
			if label != null:
				label.queue_free()
				_rename_rewards(shop, "")
			continue
		_rename_rewards(shop, tooltip_title())
		if label == null:
			label = Label.new()
			label.name = "ArchipelagoOffer"
			label.position = Vector2(-160, -190)
			label.custom_minimum_size = Vector2(320, 0)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 6)
			shop.add_child(label)
		label.text = "ARCHIPELAGO" if authenticated else "ARCHIPELAGO (offline)"

# Replaces the floating bodypart name under the AP pedestal; "" restores it.
func _rename_rewards(shop: Node, title: String) -> void:
	for reward in shop.get("_rewards"):
		if not is_instance_valid(reward):
			continue
		var name_label := reward.get_node_or_null("%Label") as Label
		if name_label == null:
			continue
		if title.is_empty():
			if name_label.has_meta("archipelago_original"):
				name_label.text = name_label.get_meta("archipelago_original")
				name_label.remove_meta("archipelago_original")
		elif name_label.text != title:
			name_label.set_meta("archipelago_original", name_label.text)
			name_label.text = title

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

# --- Settings > Archipelago tab --------------------------------------------

func _inject_tab(menu: Node) -> void:
	if not is_instance_valid(menu) or menu.has_meta("archipelago_tab"):
		return
	var buttons: Variant = menu.get("tab_buttons")
	var content: Variant = menu.get("tab_content")
	if not buttons is Array or buttons.is_empty() or not content is Control \
			or content.get_child_count() != buttons.size():
		log_line("Options menu layout changed; Archipelago tab not added.")
		return
	menu.set_meta("archipelago_tab", true)
	var template: Button = buttons[buttons.size() - 1]
	var button := Button.new()
	button.set_script(template.get_script())
	button.name = "TabArchipelago"
	button.text = TAB_TITLE
	button.theme_type_variation = template.theme_type_variation
	button.toggle_mode = true
	button.button_group = template.button_group
	button.size_flags_horizontal = template.size_flags_horizontal
	button.focus_mode = Control.FOCUS_CLICK
	template.add_sibling(button)
	var index: int = buttons.size()
	buttons.append(button)
	button.pressed.connect(menu._on_tab_changed.bind(index))
	var page := _build_page()
	page.visible = false
	content.add_child(page)
	var height := 0.0
	for sibling in content.get_children():
		if sibling != page and sibling is Control:
			height = maxf(height, sibling.get_combined_minimum_size().y)
	page.custom_minimum_size.y = clampf(height, PAGE_MIN_HEIGHT, PAGE_MAX_HEIGHT)
	_refresh_pages()

func _build_page() -> Control:
	# A scroll page capped to the height of the vanilla tabs keeps the tab row on screen.
	var page := ScrollContainer.new()
	page.name = "button_archipelago"
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.custom_minimum_size = Vector2(0, PAGE_MIN_HEIGHT)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	page.add_child(box)
	var widgets := {"page": page}
	widgets.status = _label(box, FONT_SIZE)
	widgets.progress = _label(box, FONT_SIZE)
	var fields := GridContainer.new()
	fields.columns = 2
	fields.add_theme_constant_override("h_separation", 8)
	fields.add_theme_constant_override("v_separation", 4)
	box.add_child(fields)
	widgets.server = _line(fields, "Server", server, "ws://host:port or wss://host:port")
	widgets.slot = _line(fields, "Slot", slot_name, "Slot name from the seed")
	widgets.password = _line(fields, "Password", password, "Optional, not saved")
	widgets.password.secret = true
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var connect_button := _button(row, "Connect")
	connect_button.pressed.connect(func():
		server = widgets.server.text.strip_edges()
		slot_name = widgets.slot.text.strip_edges()
		password = widgets.password.text
		connect_server())
	widgets.grants = _button(row, "Redeem grants")
	widgets.grants.pressed.connect(redeem_grants)
	_button(row, "Open log folder").pressed.connect(func():
		OS.shell_open(ProjectSettings.globalize_path(ROOT)))
	var paths := _label(box, SMALL_FONT_SIZE)
	paths.modulate = Color(1, 1, 1, 0.7)
	paths.text = "Client log: %s\nGame log: %s" % [
		ProjectSettings.globalize_path(LOG_FILE), ProjectSettings.globalize_path("user://logs/godot.log")]
	widgets.log = RichTextLabel.new()
	widgets.log.custom_minimum_size = Vector2(0, 120)
	widgets.log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	widgets.log.scroll_following = true
	widgets.log.selection_enabled = true
	widgets.log.add_theme_font_size_override("normal_font_size", SMALL_FONT_SIZE)
	box.add_child(widgets.log)
	widgets.revision = -1
	pages.append(widgets)
	return page

func _label(parent: Control, font_size: int) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _line(grid: Control, caption: String, text: String, hint: String) -> LineEdit:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	grid.add_child(label)
	var field := LineEdit.new()
	field.text = text
	field.placeholder_text = hint
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_font_size_override("font_size", FONT_SIZE)
	grid.add_child(field)
	return field

func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style

func _button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.add_theme_stylebox_override("normal", _button_style(BUTTON_COLOR))
	button.add_theme_stylebox_override("hover", _button_style(BUTTON_COLOR.lightened(0.25)))
	button.add_theme_stylebox_override("pressed", _button_style(BUTTON_COLOR.darkened(0.3)))
	button.add_theme_stylebox_override("focus", _button_style(BUTTON_COLOR.lightened(0.25)))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	parent.add_child(button)
	return button

func _refresh_pages() -> void:
	var live: Array = []
	for widgets in pages:
		if not is_instance_valid(widgets.page):
			continue
		live.append(widgets)
		if not widgets.page.is_visible_in_tree():
			continue
		widgets.status.text = status
		if campaign != null:
			widgets.progress.text = "Checks: %d sent, %d/%d confirmed. Next: %s." % [
				campaign.checks.size(), campaign.confirmed.size(), count, tooltip_title()]
			widgets.grants.text = "Redeem %d grants (+%d coins)" % [campaign.bank, campaign.bank * GRANT_COINS]
		else:
			widgets.progress.text = "No campaign loaded yet."
			widgets.grants.text = "Redeem Research Grants"
		if widgets.revision != log_revision:
			widgets.revision = log_revision
			widgets.log.text = "\n".join(log_lines)
	pages = live
