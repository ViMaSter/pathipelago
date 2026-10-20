extends Node

const GAME := "Pathogenic"
const FIRST_LOCATION := 402938001
const COINS_ITEM := 402939001
const DNA_ITEM := 402939002
const PLASMID_FRAGMENTS_ITEM := 402939003
const GRANT_ITEM := COINS_ITEM
# Must match the APWorld's full table: 309 unlocks and 10,000 checks per currency.
const MAX_CHECKS := 30309
# Godot's 64 KiB default closes the socket (1009) on large data packages such as Stardew's.
const INBOUND_BUFFER := 16 * 1024 * 1024
const GRANT_COINS := 15
# The standard MultiworldGG/Archipelago server port, used when an address omits one.
const DEFAULT_PORT := 38281
# A secure attempt that neither opens nor fails within this time falls back to ws://.
const CONNECT_TIMEOUT := 10.0
const ROOT := "user://multiworldgg_shop"
const LOG_FILE := ROOT + "/client.log"
const LOG_LIMIT := 512 * 1024
const LOG_LINES := 200
const SHOP_ROOM_SCRIPT := "res://scn/environ/rooms/special/shop.gd"
const OPTIONS_SCRIPT := "res://scn/ui/options_menu.gd"
const MAIN_SCRIPT := "res://scn/main.gd"
const START_MENU_SCRIPT := "res://scn/ui/start_menus/player_selection_menu.gd"
const START_TEXT := "Start MultiworldGG"
const ORANGE := "#ff9a2e"
const BLUE := "#66e6ff"
const RUN_FILE := ROOT + "/run.cfg"
# Blue "item rooms" offer 1-3 free choose-one BodypartRewards.
const ITEM_ROOM_SCRIPT := "res://scn/environ/rooms/special/item_room.gd"
const REWARD_SCRIPT := "res://scn/environ/pickups/bodypart_reward.gd"
const TAB_TITLE := "MultiworldGG"
const FONT_SIZE := 18
const SMALL_FONT_SIZE := 12
const PAGE_MIN_HEIGHT := 300.0
const PAGE_MAX_HEIGHT := 640.0
const BUTTON_COLOR := Color(0.12, 0.42, 0.68)
# Enhancer's icon; every MultiworldGG pedestal shows it instead of the rolled upgrade.
const REMOTE_ICON := "res://gfx/player/bodyparts/internal/upgrade.png"
const MUTATION_SKIP := "res://scn/player/evolutions/skip_evolution.tres"
const MUTATION_PLACEHOLDER := "res://gfx/player/mutations/mutation_placeholder.png"
# The level-up draft's last card (MutationT): a plain mutation, or the skip card
# on evolution levels.
const LEVEL_CARD := 3
const REMOTE_ICON_SCALE := Vector2(3.0, 3.0)
const State = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/state.gd")
const Isolation = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/isolation.gd")
const Unlocks = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/unlocks.gd")

var socket := WebSocketPeer.new()
var authenticated := false
var status := "MultiworldGG is off. Enable it in Settings > MultiworldGG before starting a run."
var server := ""
var slot_name := ""
var password := ""
var team := -1
var slot := -1
var seed_name := ""
var count := 0
# Where remote unlocks appear; set by the slot's YAML and remembered for offline play.
const SOURCES := ["shops", "item_rooms", "boss_rewards", "level_ups"]
const SOURCE_LABELS := {"shops": "shops", "item_rooms": "blue item rooms",
	"boss_rewards": "boss rewards", "level_ups": "level-up drafts"}
var sources := {"shops": true, "item_rooms": true, "boss_rewards": true, "level_ups": true}
# The setting decides new runs; run_multiworld is locked when a run starts (or is
# continued) so toggling mid-run never changes that run's rewards.
var enabled := false
var run_multiworld := false
var run_seed := ""
var run_id := ""
var required_victories := 0
var goal_sent := false
var death_link := false
var run_generation := 0
var pending_death: Dictionary = {}
var death_events: Dictionary = {}
var death_reported := false
var applying_death := false
var last_death_time := 0.0
var campaign: RefCounted
var scouts: Dictionary = {}
var players: Dictionary = {}
var slot_games: Dictionary = {}
var item_names: Dictionary = {}
var refresh_time := 0.0
var retry_time := 0.0
var connecting := false
var _candidates := PackedStringArray()
var _tried := PackedStringArray()
var _dialing := ""
var _opened := false
var _connect_time := 0.0
var room_seen := false
var item_stream: Array = []
var item_stream_ready := false
var synchronized := false
var sync_key := ""
var slot_schema := 2
var coin_amount := GRANT_COINS
var dna_amount := 0
var plasmid_fragment_amount := 0
var campaign_identity := ""
var _connected_server := ""
var _connected_slot := ""
var native_conditions: Dictionary = {}
var server_unlock_checks: Array = []
var _profile_refresh_pending := false
var fatal := false
var log_lines: PackedStringArray = []
var log_revision := 0
var pages: Array = []
var toast: Label
var toast_time := 0.0
var remote_rewards: Array = []
var free_rewards: Array = []
var remote_icon: Texture2D
var remote_card: Texture2D
var level_gen := -1
var level_card: Resource
var level_original: Variant
var level_texture: Texture2D
var level_button: BaseButton
var start_buttons: Array = []
# A new run's player must exist this long before grants are paid to it, so
# run setup or save restore cannot overwrite the added coins.
var settled_player := 0
var player_seen := 0
var player_age := 0.0
var _log: FileAccess

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Run after the game UI so the tooltip override wins each frame.
	process_priority = 1000
	if DirAccess.make_dir_recursive_absolute(ROOT) != OK:
		_fail("Cannot create MultiworldGG campaign directory.")
	_open_log()
	_build_toast()
	if not Isolation.error.is_empty():
		_fail(Isolation.error)
	get_tree().node_added.connect(_on_node_added)
	var config := ConfigFile.new()
	var err := config.load(ROOT + "/connection.cfg")
	if err == OK:
		server = str(config.get_value("connection", "server", server))
		slot_name = str(config.get_value("connection", "slot", ""))
		enabled = config.get_value("mod", "enabled", false) == true
		for key in SOURCES:
			sources[key] = config.get_value("sources", key, true) == true
	elif err != ERR_FILE_NOT_FOUND:
		_fail("Cannot read MultiworldGG connection configuration: " + error_string(err))
	log_line("Client log: " + ProjectSettings.globalize_path(LOG_FILE))
	_select_profile()
	if not fatal:
		notify(status if not enabled else "MultiworldGG is on for new runs.")
	if enabled and not fatal and not Unlocks.hooks_ready:
		notify("Restart Pathogenic once to activate the new progression hooks. Campaign starts are blocked until then.")
	# The main menu (and its options panel) exists before this node joins the tree.
	_scan_existing.call_deferred(get_tree().root)
	if enabled and not slot_name.is_empty() and not fatal:
		connect_server()

func _scan_existing(node: Node) -> void:
	for child in node.get_children():
		if child != self:
			_on_node_added(child)
			_scan_existing(child)

func set_enabled(value: bool) -> void:
	if value == enabled:
		return
	enabled = value
	var err := _save_config()
	if err != OK:
		_fail("Could not save MultiworldGG setting: " + error_string(err))
		return
	var current := " This run stays %s." % ("MultiworldGG" if run_multiworld else "vanilla") if _run_active() else ""
	notify("MultiworldGG %s for new runs.%s" % ["enabled" if enabled else "disabled", current])
	_select_profile()
	if enabled and not authenticated and not connecting and not slot_name.is_empty() and not fatal:
		connect_server()

func _run_active() -> bool:
	var globals := get_node_or_null("/root/G")
	return globals != null and is_instance_valid(globals.get("main")) and globals.main.is_inside_tree()

func campaign_ready() -> bool:
	return (enabled or (run_multiworld and _run_active())) and not fatal \
			and authenticated and synchronized and Unlocks.hooks_ready and campaign != null \
			and Isolation.active and Isolation.identity == campaign_identity and not campaign_identity.is_empty()

func _select_profile() -> void:
	if _run_active() or fatal:
		return
	var previous_generation := Isolation.generation
	if enabled:
		var target := campaign_identity if authenticated and synchronized else ""
		# A disconnect must retain the campaign, not load staging or local data.
		if Isolation.active and not Isolation.identity.is_empty() and target.is_empty():
			return
		if not Isolation.enter(target):
			_fail(Isolation.error)
			return
	else:
		if Isolation.active:
			_candidates.clear()
			connecting = false
			socket.close()
			authenticated = false
			synchronized = false
			Unlocks.reset()
			_reset_deathlink()
		Isolation.leave()
	if previous_generation == Isolation.generation:
		return
	Isolation.reload_stores(get_tree())
	native_conditions.clear()
	# Rebuild cached menu/loadout previews after their backing profile changes.
	if get_tree().current_scene != null and not _profile_refresh_pending:
		_profile_refresh_pending = true
		_reload_profile_menu.call_deferred()

func _reload_profile_menu() -> void:
	_profile_refresh_pending = false
	if _run_active():
		return
	var result := get_tree().reload_current_scene()
	if result != OK:
		_fail("Could not rebuild the campaign menu: " + error_string(result))

func _run_file() -> String:
	return Isolation.PM.profile_path("multiworldgg-run.cfg") if Isolation.active else RUN_FILE

# Called when main.tscn enters the tree: after apply_run_save restored the seed
# on Continue, before any room or reward spawns.
func begin_run() -> void:
	run_generation += 1
	pending_death.clear()
	death_reported = false
	var globals := get_node_or_null("/root/G")
	var saves := get_node_or_null("/root/RunSaveManager")
	run_seed = str(globals.get("rng_seed")) if globals != null else ""
	var continuing: bool = saves != null and saves.get("is_loading_run") == true
	var config := ConfigFile.new()
	if continuing:
		var loaded := config.load(_run_file()) == OK
		run_multiworld = loaded and str(config.get_value("run", "seed", "")) == run_seed \
				and config.get_value("run", "multiworldgg", false) == true
		run_id = str(config.get_value("run", "id", run_seed)) if run_multiworld else ""
	else:
		run_multiworld = enabled
		run_id = Crypto.new().generate_random_bytes(16).hex_encode()
		config.set_value("run", "seed", run_seed)
		config.set_value("run", "multiworldgg", run_multiworld)
		config.set_value("run", "id", run_id)
		var err := config.save(_run_file())
		if err != OK:
			_fail("Cannot save run mode and identity: " + error_string(err))
			return
	remote_rewards.clear()
	free_rewards.clear()
	notify("%s run %s: %s." % ["Continued" if continuing else "New", run_seed,
		"MultiworldGG remote unlocks active" if run_multiworld else "vanilla (MultiworldGG off for this run)"])

func record_victory() -> void:
	var globals := get_node_or_null("/root/G")
	if fatal or not run_multiworld or not _run_active() or campaign == null \
			or not Isolation.active or Isolation.identity != campaign_identity \
			or globals == null or int(globals.get("daily_run")) != 0 \
			or not is_instance_valid(globals.get("player")):
		return
	if run_id in campaign.victories:
		return
	if not campaign.record_victory(run_id):
		_fail(campaign.error)
		return
	notify("Victory %d/%d recorded." % [campaign.victories.size(), required_victories])
	_send_goal()

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
		push_error("[MultiworldGGShop] Cannot open client log: " + error_string(FileAccess.get_open_error()))

func log_line(message: String) -> void:
	var line := "%s %s" % [Time.get_datetime_string_from_system(), message]
	log_lines.append(line)
	if log_lines.size() > LOG_LINES:
		log_lines = log_lines.slice(log_lines.size() - LOG_LINES)
	log_revision += 1
	print("[MultiworldGGShop] ", message)
	if _log != null:
		_log.store_line(line)
		_log.flush()

func notify(message: String) -> void:
	status = message
	log_line(message)

func _fail(message: String) -> void:
	fatal = true
	authenticated = false
	synchronized = false
	Unlocks.synchronized = false
	push_error("[MultiworldGGShop] " + message)
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
		toast.text = "MultiworldGG: " + message
		toast.visible = true
		toast_time = 5.0

func connect_server() -> void:
	if server.strip_edges().is_empty():
		notify("Enter the WebSocket address from your multiworld.gg room page before connecting.")
		return
	if not enabled and not (run_multiworld and _run_active()):
		notify("Enable MultiworldGG in the main menu before connecting its isolated campaign.")
		return
	if _run_active() and not run_multiworld:
		notify("This run is vanilla. Return to the main menu before connecting a MultiworldGG campaign.")
		return
	if fatal:
		notify("Restart after resolving the campaign/configuration error in the log.")
		return
	if _run_active() and run_multiworld and not _connected_server.is_empty() \
			and (server.strip_edges() != _connected_server or slot_name.strip_edges() != _connected_slot):
		notify("Return to the main menu before connecting this run to a different server or slot.")
		return
	server = server.strip_edges()
	slot_name = slot_name.strip_edges()
	var urls := server_urls(server)
	if urls.is_empty() or slot_name.is_empty():
		notify("Enter a server address (host, host:port, ws:// or wss:// URL; port %d if omitted) and a nonempty slot name." % DEFAULT_PORT)
		return
	var err := _save_config()
	if err != OK:
		_fail("Could not save connection configuration: " + error_string(err))
		return
	socket.close()
	_reset_deathlink()
	authenticated = false
	room_seen = false
	item_stream_ready = false
	synchronized = false
	Unlocks.synchronized = false
	item_stream.clear()
	server_unlock_checks.clear()
	scouts.clear()
	players.clear()
	slot_games.clear()
	item_names.clear()
	campaign = null
	retry_time = 0.0
	_candidates = urls
	_tried.clear()
	_dial()

# Addresses without a scheme try wss:// first, then ws://, like MultiworldGG's own
# clients; a missing port means DEFAULT_PORT. Returns [] for unusable input.
static func server_urls(address: String) -> PackedStringArray:
	address = address.strip_edges()
	var schemes := ["wss://", "ws://"]
	for scheme in ["ws://", "wss://"]:
		if address.to_lower().begins_with(scheme):
			schemes = [scheme]
			address = address.substr(scheme.length())
	if address.contains("://") or address.contains(" ") or address.contains("@"):
		return PackedStringArray()
	var slash := address.find("/")
	var authority := address if slash < 0 else address.left(slash)
	var path := "" if slash < 0 else address.substr(slash)
	var host := authority
	var port := ""
	if authority.begins_with("["):
		var close := authority.find("]")
		if close < 0:
			return PackedStringArray()
		host = authority.left(close + 1)
		var tail := authority.substr(close + 1)
		if not tail.is_empty():
			if not tail.begins_with(":"):
				return PackedStringArray()
			port = tail.substr(1)
	elif authority.count(":") == 1:
		host = authority.get_slice(":", 0)
		port = authority.get_slice(":", 1)
	elif authority.count(":") > 1:
		# IPv6 literals need brackets to separate the port.
		return PackedStringArray()
	if host.is_empty() or host == "[]":
		return PackedStringArray()
	if port.is_empty():
		port = str(DEFAULT_PORT)
	elif not port.is_valid_int() or int(port) < 1 or int(port) > 65535:
		return PackedStringArray()
	var urls := PackedStringArray()
	for scheme in schemes:
		urls.append("%s%s:%s%s" % [scheme, host, port, path])
	return urls

func _dial() -> void:
	_dialing = _candidates[0]
	_candidates.remove_at(0)
	socket.close()
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = INBOUND_BUFFER
	_opened = false
	_connect_time = 0.0
	var err := socket.connect_to_url(_dialing)
	if err != OK:
		_dial_failed(error_string(err))
		return
	connecting = true
	notify("Connecting to " + _dialing + " as " + slot_name)

func _dial_failed(reason: String) -> void:
	_tried.append(_dialing)
	socket.close()
	if not _candidates.is_empty():
		log_line("Could not reach %s (%s); trying %s." % [_dialing, reason, _candidates[0]])
		_dial()
		return
	connecting = false
	notify("Could not reach the server (%s; tried %s). Check the address and port and that the room is running." \
		% [reason, ", ".join(_tried)])

func _process(delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if connecting and not _opened and state != WebSocketPeer.STATE_OPEN:
		_connect_time += delta
		if state == WebSocketPeer.STATE_CLOSED:
			_dial_failed("closed with code %d" % socket.get_close_code())
		elif _connect_time >= CONNECT_TIMEOUT:
			_dial_failed("timed out")
		state = socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		_opened = true
		while socket.get_available_packet_count() > 0:
			var parser := JSON.new()
			var err := parser.parse(socket.get_packet().get_string_from_utf8())
			if err != OK or not parser.data is Array:
				_fail("Malformed MultiworldGG packet.")
				socket.close()
				return
			for message in parser.data:
				if not message is Dictionary or not message.get("cmd") is String:
					_fail("Malformed MultiworldGG command.")
					socket.close()
					return
				_handle(message)
	elif state == WebSocketPeer.STATE_CLOSED and (connecting or authenticated):
		_reset_deathlink()
		connecting = false
		authenticated = false
		item_stream_ready = false
		synchronized = false
		Unlocks.synchronized = false
		notify("Disconnected (code %d). MultiworldGG pedestals are blocked; reconnect in Settings > MultiworldGG." % socket.get_close_code())
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
	_mask_rewards()
	_watch_level_up()
	_update_start_tip()
	_track_player(delta)
	_apply_pending_death()
	refresh_time += delta
	if refresh_time >= 0.5:
		refresh_time = 0.0
		_refresh_offers()
		_mask_rewards()
		if campaign != null and (campaign.bank > 0 or campaign.dna_bank > 0 \
				or campaign.plasmid_fragment_bank > 0):
			redeem_rewards(true)
		_refresh_pages()
		_select_profile()
		_scan_natural_unlocks()

func _send(message: Dictionary) -> bool:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var err := socket.send_text(JSON.stringify([message]))
	if err != OK:
		authenticated = false
		notify("Network send failed: " + error_string(err) + ". Reconnect in Settings > MultiworldGG.")
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
		"Bounced":
			_receive_death(message)
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
		"Retrieved":
			if authenticated and not synchronized and message.get("keys") is Dictionary and message["keys"].has(sync_key):
				if not item_stream_ready:
					if not campaign.accept_items([]):
						_fail("Server item history is empty but the campaign journal is not. " + campaign.error)
						return
					item_stream_ready = true
				synchronized = true
				Unlocks.synchronized = true
				_reconcile_unlocks()
				_select_profile()
				_refresh_unlock_menus(get_tree().root)
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

func _save_config() -> Error:
	var config := ConfigFile.new()
	config.set_value("connection", "server", server)
	config.set_value("connection", "slot", slot_name)
	config.set_value("mod", "enabled", enabled)
	for key in SOURCES:
		config.set_value("sources", key, sources[key])
	return config.save(ROOT + "/connection.cfg")

# Schema 1 slots predate the source options and enable every source.
static func parse_sources(data: Dictionary) -> Variant:
	var parsed := {}
	if int(data.schema) == 1:
		for key in SOURCES:
			parsed[key] = true
		return parsed
	var raw: Variant = data.get("sources")
	if not raw is Dictionary:
		return null
	for key in SOURCES:
		if not raw.get(key) is bool:
			return null
		parsed[key] = raw[key]
	return parsed if parsed.values().has(true) else null

func sources_text() -> String:
	var enabled: Array = SOURCES.filter(func(key): return sources[key]).map(func(key): return SOURCE_LABELS[key])
	return ", ".join(enabled) if not enabled.is_empty() else "nowhere"

func _connected(message: Dictionary) -> void:
	_reset_deathlink()
	goal_sent = false
	var data: Variant = message.get("slot_data")
	var schema_value: Variant = data.get("schema") if data is Dictionary else null
	var count_value: Variant = data.get("checks") if schema_value == 4 \
			else data.get("extra_checks") if data is Dictionary else null
	var victories_value: Variant = data.get("required_victories", 0) if data is Dictionary else null
	var valid_amounts := true
	if schema_value == 4:
		for key in ["coin_amount", "dna_amount", "plasmid_fragment_amount"]:
			var amount: Variant = data.get(key)
			if not State.integer(amount) or int(amount) < 1 or int(amount) > 10000:
				valid_amounts = false
	if not State.integer(message.get("team")) or not State.integer(message.get("slot")) \
			or not data is Dictionary or not State.integer(count_value) \
			or not State.integer(schema_value) or not int(schema_value) in [1, 2, 3, 4] or not valid_amounts \
			or not State.integer(victories_value) or int(victories_value) < 0 or int(victories_value) > 50 \
			or int(count_value) < 0 or int(count_value) > MAX_CHECKS or parse_sources(data) == null \
			or not data.get("start_with_all_characters", false) is bool \
			or parse_death_link(data) == null:
		_fail("Incompatible slot data. Generate with the bundled Pathogenic APWorld.")
		socket.close()
		return
	team = int(message.team)
	slot = int(message.slot)
	slot_schema = int(schema_value)
	required_victories = int(victories_value)
	coin_amount = GRANT_COINS
	dna_amount = 0
	plasmid_fragment_amount = 0
	if slot_schema >= 4:
		coin_amount = int(data.coin_amount)
		dna_amount = int(data.dna_amount)
		plasmid_fragment_amount = int(data.plasmid_fragment_amount)
	var ids: Array = []
	if slot_schema >= 3:
		if data.get("catalog_schema") != 1 or not data.get("unlock_ids") is Array:
			_fail("Missing or incompatible server unlock catalogue.")
			return
		ids = data.unlock_ids
		if not Unlocks.configure(ids, data.get("start_with_all_characters", false)):
			_fail(Unlocks.error)
			return
	else:
		Unlocks.reset()
	count = int(count_value)
	sources = parse_sources(data)
	if _save_config() != OK:
		log_line("Could not remember this slot's remote unlock sources.")
	var identity := JSON.stringify([seed_name, team, slot])
	if _run_active() and run_multiworld and Isolation.active and Isolation.identity != identity:
		_fail("This run belongs to a different campaign. Return to the main menu before switching.")
		return
	campaign_identity = identity
	server_unlock_checks.clear()
	campaign = State.new()
	if not campaign.open(ROOT + "/" + identity.sha256_text() + ".json", identity, count, ids):
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
	for id in ids:
		if not inventory.has(Unlocks.LOCATION_BASE + int(id)):
			_fail("Server natural-unlock inventory does not match this APWorld.")
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
	_connected_server = server.strip_edges()
	_connected_slot = slot_name.strip_edges()
	connecting = false
	death_link = parse_death_link(data)
	if death_link:
		var bus := get_node_or_null("/root/SignalBus")
		if bus == null or not bus.has_signal("player_died"):
			_disable_deathlink("The game's player-death signal is unavailable.")
		elif not bus.is_connected("player_died", _on_player_died):
			bus.connect("player_died", _on_player_died)
	if not _send({"cmd": "ConnectUpdate", "tags": ["AP", "DeathLink"] if death_link else ["AP"]}):
		authenticated = false
		_reset_deathlink()
		notify("Could not update DeathLink subscription. Reconnect in Settings > MultiworldGG.")
		return
	_accept_checks(checked)
	if fatal:
		return
	# Request every slot's game so cross-game item names are available.
	var games: Array = []
	for game_name in slot_games.values():
		if not game_name in games:
			games.append(game_name)
	_send({"cmd": "GetDataPackage", "games": games})
	_send({"cmd": "LocationScouts", "locations": range(FIRST_LOCATION, FIRST_LOCATION + count), "create_as_hint": 0})
	_send({"cmd": "Sync"})
	sync_key = "multiworldgg_pathogenic_sync_%d_%d_%d" % [team, slot, Time.get_ticks_usec()]
	# WebSocket command ordering makes Retrieved a barrier after Sync, including
	# the protocol's valid empty-inventory case (which sends no ReceivedItems).
	_send({"cmd": "Get", "keys": [sync_key]})
	_send_checks()
	notify("Connected as %s (slot %d). %d/%d checks confirmed. Remote unlocks in: %s. DeathLink %s." % [
		slot_name, slot, campaign.confirmed.size(), count, sources_text(), "on" if death_link else "off"])

static func parse_death_link(data: Dictionary) -> Variant:
	var value: Variant = data.get("death_link", false)
	if value is bool:
		return value
	if State.integer(value) and int(value) in [0, 1]:
		return int(value) == 1
	return null

func _reset_deathlink() -> void:
	death_link = false
	pending_death.clear()
	death_events.clear()

func _disable_deathlink(reason: String) -> void:
	death_link = false
	pending_death.clear()
	notify("DeathLink disabled: " + reason)
	if authenticated:
		_send({"cmd": "ConnectUpdate", "tags": ["AP"]})

func _deathlink_player() -> Node:
	if fatal or not authenticated or not death_link or not run_multiworld or not _run_active():
		return null
	var globals := get_node("/root/G")
	var player: Node = globals.get("player")
	return player if is_instance_valid(player) and player.is_inside_tree() else null

func _remember_death(source: String, timestamp: float) -> bool:
	var key := JSON.stringify([source, timestamp])
	if death_events.has(key):
		return false
	death_events[key] = true
	# Bounces are transient; keep a bounded replay window, not a death cooldown.
	if death_events.size() > 256:
		death_events.erase(death_events.keys()[0])
	return true

func _receive_death(message: Dictionary) -> void:
	if not authenticated or not death_link:
		return
	var tags: Variant = message.get("tags")
	if not tags is Array or not "DeathLink" in tags:
		return
	var data: Variant = message.get("data")
	if not data is Dictionary:
		log_line("Ignored malformed DeathLink event: %s" % JSON.stringify(message))
		return
	# Other games' clients vary: cause may be null/absent, time may be a string.
	var source: String = str(data.source) if data.get("source") is String else ""
	var raw_time: Variant = data.get("time")
	var timestamp := 0.0
	if raw_time is int or raw_time is float:
		timestamp = float(raw_time)
	elif raw_time is String and str(raw_time).is_valid_float():
		timestamp = str(raw_time).to_float()
	if not is_finite(timestamp) or timestamp <= 0.0:
		log_line("Ignored malformed DeathLink event: %s" % JSON.stringify(data))
		return
	if not source.is_empty() and source == slot_name:
		return
	if not _remember_death(source, timestamp):
		return
	if source.is_empty():
		source = "another player"
	var player := _deathlink_player()
	if player == null or player.get("dead") == true:
		log_line("Ignored DeathLink from %s: no living MultiworldGG run." % source)
		return
	if not pending_death.is_empty():
		return
	pending_death = {
		"generation": run_generation, "player": player.get_instance_id(),
		"main": get_node("/root/G").main.get_instance_id(),
	}
	var raw_cause: Variant = data.get("cause")
	var cause: String = str(raw_cause) if raw_cause is String and not str(raw_cause).is_empty() \
			else "%s died." % source
	notify("DeathLink from %s: %s" % [source, cause])
	show_toast("DeathLink from %s" % source)

func _apply_pending_death() -> void:
	if pending_death.is_empty():
		return
	var player := _deathlink_player()
	if player == null or player.get("dead") == true \
			or pending_death.generation != run_generation \
			or pending_death.player != player.get_instance_id() \
			or pending_death.main != get_node("/root/G").main.get_instance_id():
		pending_death.clear()
		log_line("Discarded DeathLink: its living run is no longer active.")
		return
	var editor: Node = get_node("/root/G").get("editor")
	if get_tree().paused or not player.is_node_ready() or not player.can_process() or (is_instance_valid(editor) \
			and (editor.get("active") == true or editor.get("state") != _enum_value("EditorState", "HIDDEN"))):
		return
	var body: Variant = player.get("center_body")
	if not player.has_method("hit_no_signal") or not is_instance_valid(body) or not body is Node2D:
		_disable_deathlink("The game's player damage API is unavailable.")
		return
	var defenses := {}
	for property in ["armor", "invulnerability", "player_damage_mult", "hp"]:
		var value: Variant = player.get(property)
		if not (value is int or value is float) or not is_finite(float(value)):
			_disable_deathlink("Invalid player damage property: " + property)
			return
		if property != "hp":
			defenses[property] = value
	if not player.get("damage_blocked") is bool:
		_disable_deathlink("The game's damage-blocking API is unavailable.")
		return
	defenses["damage_blocked"] = player.get("damage_blocked")
	pending_death.clear()
	applying_death = true
	player.set("armor", 0)
	player.set("invulnerability", 0.0)
	player.set("player_damage_mult", 1)
	player.set("damage_blocked", false)
	# This native entry point retains damage/death effects without pre-hit mutations.
	player.call("hit_no_signal", maxf(1.0, float(player.get("hp"))), body.global_position)
	applying_death = false
	if is_instance_valid(player):
		for property in defenses:
			player.set(property, defenses[property])
	if not is_instance_valid(player) or player.get("dead") != true:
		_disable_deathlink("Lethal damage did not end the run. See the client log.")
	else:
		log_line("DeathLink lethal damage ended the run.")

func _on_player_died() -> void:
	var player := _deathlink_player()
	if player == null or player.get("dead") != true or death_reported:
		return
	death_reported = true
	pending_death.clear()
	if applying_death:
		return
	# Keep distinct local deaths distinct even when the system clock moves back.
	last_death_time = maxf(Time.get_unix_time_from_system(), last_death_time + 0.001)
	_remember_death(slot_name, last_death_time)
	if _send({"cmd": "Bounce", "tags": ["DeathLink"], "data": {
			"time": last_death_time, "source": slot_name,
			"cause": "%s died in Pathogenic." % slot_name}}):
		log_line("Sent DeathLink for this run's death.")
	else:
		notify("Could not send DeathLink. The death will not be replayed after reconnecting.")

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
	for location in list:
		if Unlocks.selected.has(int(location) - Unlocks.LOCATION_BASE) \
				and not int(location) in server_unlock_checks:
			server_unlock_checks.append(int(location))
	_send_goal()
	_reconcile_unlocks()

func _send_goal() -> void:
	if not fatal and authenticated and not goal_sent and campaign != null and campaign.goal_reached(required_victories):
		goal_sent = _send({"cmd": "StatusUpdate", "status": 30})

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
	var before := [campaign.bank, campaign.dna_bank, campaign.plasmid_fragment_bank]
	if not campaign.accept_items(item_stream):
		_fail(campaign.error)
		return
	var added_coins: int = campaign.bank - before[0]
	var added_dna: int = campaign.dna_bank - before[1]
	var added_fragments: int = campaign.plasmid_fragment_bank - before[2]
	if added_coins > 0 or added_dna > 0 or added_fragments > 0:
		log_line("Received currency items: Coins %d, DNA %d, Plasmid Fragments %d." % [
			added_coins, added_dna, added_fragments])
		redeem_rewards(true)
	_reconcile_unlocks()

func _send_checks() -> void:
	if campaign != null and (not campaign.checks.is_empty() or not campaign.earned.is_empty()):
		_send({"cmd": "LocationChecks", "locations": campaign.checks + campaign.earned})

func earn_unlock(id: int) -> void:
	if not campaign_ready() or slot_schema < 3 or not Unlocks.selected.has(id):
		return
	var globals := get_node_or_null("/root/G")
	if globals == null or int(globals.get("daily_run")) != 0:
		return
	var location := Unlocks.LOCATION_BASE + id
	if location in campaign.earned:
		return
	if not campaign.earn(id):
		_fail(campaign.error)
		return
	log_line("Naturally earned %s; awaiting server confirmation." % Unlocks.entries[id].name)
	_send_checks()

func _reconcile_unlocks() -> void:
	if slot_schema < 3 or not synchronized or campaign == null:
		return
	var previous := Unlocks.owned.duplicate()
	if Unlocks.reconcile(item_stream.map(func(item): return int(item.item)), server_unlock_checks):
		log_line("Server owns %d/%d campaign unlocks." % [Unlocks.owned.size(), Unlocks.selected.size()])
		var names: Array[String] = []
		for id in Unlocks.owned:
			if not previous.has(id):
				names.append(str(Unlocks.entries[id].name))
		if not names.is_empty():
			show_toast("Unlocked " + "\n".join(names))
		var bus := get_node_or_null("/root/SignalBus")
		if bus != null:
			for signal_name in ["unlocks_changed", "plasmid_state_changed"]:
				if bus.has_signal(signal_name):
					bus.emit_signal(signal_name)
		_refresh_unlock_menus(get_tree().root)

func _refresh_unlock_menus(node: Node) -> void:
	var script: Script = node.get_script()
	if script != null:
		if script.resource_path == "res://scn/ui/start_menus/tube.gd":
			node.update_lock()
		elif node.has_method("_multiworld_loadout_override"):
			var unlocked: bool = node.is_unlocked()
			node.disabled = not unlocked
			node.get_node("Lock").visible = not unlocked
			node.modulate = Color.WHITE if unlocked else Color(0.415, 0.415, 0.415, 1.0)
	for child in node.get_children():
		_refresh_unlock_menus(child)

func _scan_natural_unlocks() -> void:
	if not campaign_ready() or slot_schema < 3:
		return
	var globals := get_node_or_null("/root/G")
	if globals == null or int(globals.get("daily_run")) != 0:
		return
	for id in Unlocks.selected:
		var entry: Dictionary = Unlocks.entries[id]
		var path := str(entry.get("condition", ""))
		if path.is_empty() or Unlocks.LOCATION_BASE + id in campaign.earned:
			continue
		if entry.kind == "loadout" and not entry.get("global", false) \
				and int(entry.parasite) != int(globals.get("selected_parasite")):
			continue
		if not native_conditions.has(path):
			if not ResourceLoader.exists(path):
				_fail("Native unlock resource is unavailable: " + path)
				return
			var condition := load(path)
			if condition == null or not condition.has_method("is_unlocked"):
				_fail("Native unlock hook is unavailable: " + path)
				return
			native_conditions[path] = condition
		if Unlocks.natural_condition(native_conditions[path]):
			earn_unlock(id)

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

# Exactly one pedestal per shop room is the MultiworldGG pedestal: the first pedestal in
# name order that offers a bodypart, else the first currency pedestal. The
# choice is cached on the room instance so it stays put after the purchase.
func designated(room: Node) -> Node:
	if room.has_meta("multiworldgg_pedestal"):
		var cached: Variant = room.get_meta("multiworldgg_pedestal")
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
	room.set_meta("multiworldgg_pedestal", choice)
	log_line("MultiworldGG pedestal for shop room %s: %s" % [room.name, choice.name])
	return choice

func is_multiworld(shop: Node) -> bool:
	if not run_multiworld or not sources.shops or not is_instance_valid(shop) or shop.pay_with_blood:
		return false
	if campaign != null and authenticated and campaign.next_location() < 0:
		return false
	var room := shop_room(shop)
	return room != null and designated(room) == shop

# Kept for callers/tests written against the earlier API.
func eligible(shop: Node) -> bool:
	return is_multiworld(shop)

# Returns true when the pick was consumed by the MultiworldGG path; false lets the
# vanilla shop purchase run.
func handle_pick(shop: Node, theft := false, taker: Node = null) -> bool:
	var multiworld := is_multiworld(shop)
	var room := shop_room(shop)
	var globals := get_node_or_null("/root/G")
	var money: Variant = globals.player.money if globals != null and is_instance_valid(globals.player) else null
	log_line("Shop pick %s/%s cost=%s money=%s paid=%s blood=%s theft=%s -> %s" % [
		room.name if room != null else "-", shop.name, shop.cost, money, shop.paid,
		shop.pay_with_blood, theft, "MULTIWORLDGG" if multiworld else "vanilla local purchase"])
	if not multiworld:
		return false
	purchase(shop, taker)
	return true

func _on_node_added(node: Node) -> void:
	var script: Script = node.get_script()
	if script == null:
		return
	if script.resource_path == OPTIONS_SCRIPT:
		_inject_tab.call_deferred(node)
	elif script.resource_path == MAIN_SCRIPT:
		begin_run()
	elif script.resource_path == START_MENU_SCRIPT:
		_hook_start.call_deferred(node)
	elif script.resource_path == REWARD_SCRIPT:
		_track_free_reward.call_deferred(node)
	elif node.has_method("finalize_purchase") and node.get("_rewards") != null:
		_track_shop.call_deferred(node)

func _track_shop(shop: Node) -> void:
	if not is_instance_valid(shop) or shop.has_method("_multiworld_client"):
		return
	# The script takeover did not apply to this pedestal; route its picks here.
	var area := shop.get_node_or_null("PickupArea")
	if area == null or not area.has_signal("picked"):
		return
	if area.picked.is_connected(shop._on_picked):
		area.picked.disconnect(shop._on_picked)
	area.picked.connect(_fallback_pick.bind(shop))
	log_line("Takeover inactive on %s; picks rerouted through the client." % shop.name)

func _fallback_pick(taker: Node, shop: Node) -> void:
	if is_instance_valid(shop) and not handle_pick(shop, false, taker):
		shop._on_picked(taker)

# --- Free choose-one pedestals (blue item rooms and boss rewards) ------------

# The Room that owns a free reward when it is a blue item room or a boss room;
# null for every other room, which keeps those rewards vanilla.
func free_room(node: Node) -> Node:
	var ancestor := node.get_parent()
	while ancestor != null:
		var script: Script = ancestor.get_script()
		if script != null and script.resource_path == ITEM_ROOM_SCRIPT:
			return ancestor
		if ancestor.get("res") != null:
			return ancestor if _is_boss_room(ancestor) else null
		ancestor = ancestor.get_parent()
	return null

func _is_boss_room(room: Node) -> bool:
	var res: Variant = room.get("res")
	if not res is Object or res.get("type") == null:
		return false
	var globals := get_node_or_null("/root/G")
	var script: Script = globals.get_script() if globals != null else null
	var types: Variant = script.get_script_constant_map().get("RoomType") if script != null else null
	return types is Dictionary and types.has("Boss") and int(res.type) == int(types.Boss)

# Kept for callers/tests written against the item-room-only API.
func item_room(node: Node) -> Node:
	return free_room(node)

static func _is_reward(node: Node) -> bool:
	var script: Script = node.get_script()
	return script != null and script.resource_path == REWARD_SCRIPT

# One free reward per item/boss room becomes the remote unlock: the first in
# scene-tree order (Reward, Reward2, Reward3), cached on the room so it stays put.
func designated_free(room: Node) -> Node:
	if room.has_meta("multiworldgg_reward"):
		var cached: Variant = room.get_meta("multiworldgg_reward")
		if is_instance_valid(cached) and not cached.deleted:
			return cached
	var candidates: Array = []
	for node in room.find_children("*", "", true, false):
		if _is_reward(node) and not node.deleted and not node.consumed and not node.is_queued_for_deletion() \
				and _shop_wrapper(node) == null and free_room(node) == room:
			candidates.append(node)
	if candidates.is_empty():
		return null
	room.set_meta("multiworldgg_reward", candidates[0])
	log_line("MultiworldGG pedestal for %s room %s: %s" % ["boss" if _is_boss_room(room) else "item",
		room.name, room.get_path_to(candidates[0])])
	return candidates[0]

func _track_free_reward(reward: Node) -> void:
	if not is_instance_valid(reward) or reward.deleted or reward.has_meta("multiworldgg_free") \
			or _shop_wrapper(reward) != null:
		return
	var room := free_room(reward)
	if room == null or designated_free(room) != reward:
		return
	var area: Variant = reward.get("pickup_area")
	if not area is Node or not area.has_signal("picked"):
		log_line("Free reward layout changed; %s stays vanilla." % reward.name)
		return
	var vanilla := Callable(reward, "_player_entered")
	if area.picked.is_connected(vanilla):
		area.picked.disconnect(vanilla)
	area.picked.connect(_free_pick.bind(reward))
	reward.set_meta("multiworldgg_free", true)
	free_rewards.append(reward)
	if is_free_multiworld(reward):
		remote_rewards.append(reward)
		_mask_rewards()

func free_source_enabled(reward: Node) -> bool:
	var room := free_room(reward)
	if room == null or not run_multiworld:
		return false
	return sources.boss_rewards if _is_boss_room(room) else sources.item_rooms

func is_free_multiworld(reward: Variant) -> bool:
	if not is_instance_valid(reward) or reward.deleted or reward.consumed or not reward.has_meta("multiworldgg_free"):
		return false
	if not free_source_enabled(reward):
		return false
	return not (campaign != null and authenticated and campaign.next_location() < 0)

func _free_pick(taker: Node, reward: Node) -> void:
	if not is_instance_valid(reward) or reward.deleted or reward.consumed:
		return
	var room := free_room(reward)
	var exhausted: bool = (campaign != null and authenticated and campaign.next_location() < 0) \
			or not free_source_enabled(reward)
	log_line("Free reward pick %s/%s -> %s" % [room.name if room != null else "-", reward.name,
		"vanilla free upgrade" if exhausted else "MULTIWORLDGG"])
	if exhausted:
		_unmask_reward(reward)
		_rename_reward(reward, "")
		reward._player_entered(taker)
		return
	var location := _claim_location()
	if location < 0:
		return
	if not campaign.purchase(location):
		_fail(campaign.error)
		return
	reward.consumed = true
	reward._disable_player_block()
	reward._detach_pickup_area()
	var animation := reward.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animation != null:
		animation.play("take")
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.get("upgrade") != null:
		audio.upgrade.play()
	# Consumes the choose-one siblings and marks the room looted, like a mutation pick.
	reward._confirm_choose_one_siblings()
	reward._confirm_after_take_animation()
	get_node("/root/RunSaveManager").save_run()
	_send_checks()
	show_toast("sent " + offer_text(location))
	notify("Sent %s: %s. Waiting for server confirmation." % [location_name(location), offer_text(location)])

# --- Level-up mutation draft -----------------------------------------------------

func _editor() -> Node:
	var globals := get_node_or_null("/root/G")
	var editor: Variant = globals.get("editor") if globals != null else null
	return editor if is_instance_valid(editor) else null

func _enum_value(enum_name: String, key: String) -> int:
	var globals := get_node_or_null("/root/G")
	var script: Script = globals.get_script() if globals != null else null
	var values: Variant = script.get_script_constant_map().get(enum_name) if script != null else null
	return int(values[key]) if values is Dictionary and values.has(key) else -1

func _level_exhausted() -> bool:
	return campaign != null and authenticated and campaign.next_location() < 0

# Each new draft (level-up or reroll bumps editor._mutation_gen) swaps its last
# card for a remote unlock once the game has finished streaming the cards in.
func _watch_level_up() -> void:
	var editor := _editor()
	if editor == null:
		return
	_hook_level_button(editor)
	var container := editor.get_node_or_null("MutationContainer") as CanvasItem
	var mutations: Variant = editor.get("mutations")
	if container == null or not container.visible or not mutations is Array or mutations.size() <= LEVEL_CARD:
		return
	var current: Variant = mutations[LEVEL_CARD]
	if current == null:
		return
	if level_card != null and not (run_multiworld and sources.level_ups):
		_restore_level_card(editor)
	var gen := int(editor.get("_mutation_gen"))
	if gen != level_gen:
		level_gen = gen
		level_card = null
		if _level_exhausted() or not run_multiworld or not sources.level_ups:
			return
		level_original = current
		level_texture = level_button.texture_normal if is_instance_valid(level_button) else null
		level_card = (load(MUTATION_SKIP) as Resource).duplicate() if ResourceLoader.exists(MUTATION_SKIP) else Resource.new()
		mutations[LEVEL_CARD] = level_card
		log_line("MultiworldGG card for level-up draft %d (replaces %s)." % [gen, _resource_label(current)])
	if level_card == null or mutations[LEVEL_CARD] != level_card:
		return
	if is_instance_valid(level_button):
		var texture := _remote_card_texture()
		if texture != null and level_button.texture_normal != texture:
			level_button.texture_normal = texture
	var tooltip := editor.get_node_or_null("%MutationTooltip") as Control
	if tooltip != null and tooltip.visible:
		var item: Variant = tooltip.get("item")
		if (item is Object and item == level_card) or (item is Dictionary and item.get("multiworldgg", false)):
			_style_tooltip(tooltip)

static func _resource_label(resource: Variant) -> String:
	if resource is Resource:
		var ui_name: Variant = resource.get("ui_name")
		if ui_name is String and not ui_name.is_empty():
			return ui_name
		return resource.resource_name if resource.resource_path.is_empty() else resource.resource_path.get_file()
	return str(resource)

func _hook_level_button(editor: Node) -> void:
	var buttons: Variant = editor.get("mutation_buttons")
	if not buttons is Array or buttons.size() <= LEVEL_CARD or not buttons[LEVEL_CARD] is BaseButton:
		return
	var button: BaseButton = buttons[LEVEL_CARD]
	if button == level_button and button.has_meta("multiworldgg_level"):
		return
	for connection in button.pressed.get_connections():
		var callable: Callable = connection.callable
		if callable.get_object() == editor and callable.get_method() == &"_on_mutation_pressed":
			button.pressed.disconnect(callable)
	button.pressed.connect(_level_pick.bind(editor))
	button.set_meta("multiworldgg_level", true)
	level_button = button
	level_gen = -1
	level_card = null

func _level_pick(editor: Node) -> void:
	if not is_instance_valid(editor):
		return
	var mutations: Array = editor.mutations
	if level_card == null or mutations.size() <= LEVEL_CARD or mutations[LEVEL_CARD] != level_card:
		editor._on_mutation_pressed(LEVEL_CARD)
		return
	if int(editor.state) != _enum_value("EditorState", "ACTIVE"):
		return
	if _level_exhausted():
		log_line("Level-up pick -> vanilla card (all MultiworldGG checks sent)")
		_restore_level_card(editor)
		editor._on_mutation_pressed(LEVEL_CARD)
		return
	var location := _claim_location()
	if location < 0:
		return
	if not campaign.purchase(location):
		_fail(campaign.error)
		return
	log_line("Level-up pick -> MULTIWORLDGG")
	if int(editor.pending_mutation_index) >= 0:
		editor._revert_pending_selection()
	# Commit through the vanilla skip path so the level still consumes its gene.
	mutations[LEVEL_CARD] = load(MUTATION_SKIP) if ResourceLoader.exists(MUTATION_SKIP) else level_original
	level_card = null
	editor.pending_mutation_index = LEVEL_CARD
	await editor._on_confirm_pressed()
	get_node("/root/RunSaveManager").save_run()
	_send_checks()
	show_toast("sent " + offer_text(location))
	notify("Sent %s: %s. Waiting for server confirmation." % [location_name(location), offer_text(location)])

func _restore_level_card(editor: Node) -> void:
	if level_card != null and editor.mutations.size() > LEVEL_CARD and editor.mutations[LEVEL_CARD] == level_card:
		editor.mutations[LEVEL_CARD] = level_original
		if is_instance_valid(level_button) and level_texture != null:
			level_button.texture_normal = level_texture
	level_card = null

# The draft's empty "?" card with the Enhancer icon painted over the glyph.
func _remote_card_texture() -> Texture2D:
	if remote_card != null:
		return remote_card
	if remote_icon == null and ResourceLoader.exists(REMOTE_ICON):
		remote_icon = load(REMOTE_ICON) as Texture2D
	if not ResourceLoader.exists(MUTATION_PLACEHOLDER) or remote_icon == null:
		remote_card = remote_icon
		return remote_card
	var frame: Image = (load(MUTATION_PLACEHOLDER) as Texture2D).get_image()
	var icon: Image = remote_icon.get_image()
	if frame == null or icon == null:
		remote_card = remote_icon
		return remote_card
	frame = frame.duplicate()
	icon = icon.duplicate()
	for image in [frame, icon]:
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
	var center := Vector2i(frame.get_width() / 2, frame.get_height() / 2)
	var radius := int(frame.get_width() * 0.33)
	var fill := frame.get_pixel(center.x - radius + 4, center.y)
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if Vector2(x - center.x, y - center.y).length() <= radius:
				frame.set_pixel(x, y, fill)
	var side := int(radius * 1.8)
	icon.resize(side, side, Image.INTERPOLATE_BILINEAR)
	frame.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), center - icon.get_size() / 2)
	remote_card = ImageTexture.create_from_image(frame)
	return remote_card

func _error_sound() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.get("ui_error") != null:
		audio.ui_error.play()

func _claim_location() -> int:
	if fatal or not authenticated or campaign == null:
		_error_sound()
		show_toast("not connected - open Settings > MultiworldGG.")
		notify("MultiworldGG pedestal blocked: not connected to a MultiworldGG slot.")
		return -1
	var location: int = campaign.next_location()
	if location < 0:
		notify("All MultiworldGG checks purchased. Waiting for confirmation, or campaign complete.")
		return -1
	if not scouts.has(location):
		_error_sound()
		notify("MultiworldGG pedestal blocked: waiting for scouting data from the server.")
		return -1
	return location

func purchase(shop: Node, taker: Node = null) -> void:
	if shop.paid:
		return
	var location := _claim_location()
	if location < 0:
		return
	var globals := get_node("/root/G")
	var player: Node = taker if is_instance_valid(taker) else globals.player
	var price: int = shop.get_cost_for(player) if shop.has_method("get_cost_for") and is_instance_valid(player) else int(shop.cost)
	if not is_instance_valid(player) or int(player.money) < price:
		_error_sound()
		notify("Not enough money for this MultiworldGG unlock.")
		return
	# Persist the location before charging. A crash between the two saves can
	# forgive payment, but cannot lose or duplicate a MultiworldGG check.
	if not campaign.purchase(location):
		_fail(campaign.error)
		return
	player.money -= price
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
		return "[color=orange]Not connected: open Settings > MultiworldGG.[/color]"
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
	return {"name": tooltip_title(), "hint": tooltip_body(), "multiworldgg": true}

func _shop_wrapper(node: Node) -> Node:
	while node != null:
		if node.has_method("finalize_purchase") and node.get("_rewards") != null:
			return node
		node = node.get_parent()
	return null

func _reward_ancestor(node: Node) -> Node:
	while node != null:
		if node.has_meta("multiworldgg_free"):
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
	if shop != null:
		if shop.paid or not is_multiworld(shop):
			return
	elif not is_free_multiworld(_reward_ancestor(anchor)):
		return
	if _style_tooltip(tooltip):
		ui.set("_last_tooltip_item", tooltip.item)

# Returns true when the tooltip item had to be replaced.
func _style_tooltip(tooltip: Control) -> bool:
	var card := tooltip_card()
	var current: Variant = tooltip.item
	var replaced: bool = typeof(current) != TYPE_DICTIONARY or current != card
	if replaced:
		tooltip.item = card
	var name_label := tooltip.get_node_or_null("%Name")
	if name_label != null and name_label.text != card.name:
		name_label.text = card.name
	var type_label := tooltip.get_node_or_null("%Type")
	if type_label != null and type_label.text != "MULTIWORLDGG":
		type_label.text = "MULTIWORLDGG"
		var panel := tooltip.get_node_or_null("%TypePanel")
		if panel != null:
			panel.self_modulate = Color(0.1, 0.35, 0.55, 1.0)
	return replaced

func _refresh_offers() -> void:
	var masked: Array = []
	for shop in get_tree().get_nodes_in_group("shop_item"):
		if not is_instance_valid(shop):
			continue
		if shop.paid or not is_multiworld(shop):
			_rename_rewards(shop, "")
			for reward in shop.get("_rewards"):
				_unmask_reward(reward)
			continue
		_rename_rewards(shop, tooltip_title())
		for reward in shop.get("_rewards"):
			if is_instance_valid(reward):
				masked.append(reward)
	var live: Array = []
	for reward in free_rewards:
		if not is_instance_valid(reward) or reward.deleted:
			continue
		live.append(reward)
		if not is_free_multiworld(reward):
			if not reward.consumed:
				_rename_reward(reward, "")
				_unmask_reward(reward)
			continue
		_rename_reward(reward, tooltip_title())
		masked.append(reward)
	free_rewards = live
	remote_rewards = masked

# Hides the rolled bodypart/mutation and shows the Enhancer icon instead. Runs
# every frame because the game re-spawns the visual on rerolls.
func _mask_rewards() -> void:
	for reward in remote_rewards:
		if not is_instance_valid(reward) or reward.is_queued_for_deletion():
			continue
		var icon := reward.get_node_or_null("%MutationIcon") as Sprite2D
		if icon == null:
			continue
		if remote_icon == null:
			if not ResourceLoader.exists(REMOTE_ICON):
				return
			remote_icon = load(REMOTE_ICON) as Texture2D
		if not icon.has_meta("multiworldgg_original"):
			icon.set_meta("multiworldgg_original", [icon.texture, icon.scale])
		if icon.texture != remote_icon or not icon.visible:
			icon.texture = remote_icon
			icon.scale = REMOTE_ICON_SCALE
			icon.visible = true
		var part: Variant = reward.get("bodypart")
		if part is CanvasItem and is_instance_valid(part) and part.visible:
			part.visible = false

func _unmask_reward(reward: Variant) -> void:
	if not is_instance_valid(reward):
		return
	var icon := reward.get_node_or_null("%MutationIcon") as Sprite2D
	if icon == null or not icon.has_meta("multiworldgg_original"):
		return
	var original: Array = icon.get_meta("multiworldgg_original")
	icon.remove_meta("multiworldgg_original")
	icon.texture = original[0]
	icon.scale = original[1]
	var part: Variant = reward.get("bodypart")
	icon.visible = not (part is CanvasItem and is_instance_valid(part))
	if part is CanvasItem and is_instance_valid(part):
		part.visible = true

# Replaces the floating bodypart name under the MultiworldGG pedestal; "" restores it.
func _rename_rewards(shop: Node, title: String) -> void:
	for reward in shop.get("_rewards"):
		_rename_reward(reward, title)

func _rename_reward(reward: Variant, title: String) -> void:
	if not is_instance_valid(reward):
		return
	var name_label := reward.get_node_or_null("%Label") as Label
	if name_label == null:
		return
	if title.is_empty():
		if name_label.has_meta("multiworldgg_original"):
			name_label.text = name_label.get_meta("multiworldgg_original")
			name_label.remove_meta("multiworldgg_original")
	elif name_label.text != title:
		name_label.set_meta("multiworldgg_original", name_label.text)
		name_label.text = title

func _track_player(delta: float) -> void:
	var globals := get_node_or_null("/root/G")
	var player: Variant = globals.get("player") if globals != null else null
	if not is_instance_valid(player) or player.dead:
		player_seen = 0
		settled_player = 0
		return
	if player.get_instance_id() != player_seen:
		player_seen = player.get_instance_id()
		settled_player = 0
		player_age = 0.0
	elif settled_player == 0:
		player_age += delta
		if player_age >= 2.0:
			settled_player = player_seen

func currency_summary(coins: int, dna: int, fragments: int) -> String:
	var parts: Array[String] = []
	if coins > 0:
		parts.append("%d coin%s" % [coins, "" if coins == 1 else "s"])
	if dna > 0:
		parts.append("%d DNA" % dna)
	if fragments > 0:
		parts.append("%d Plasmid Fragment%s" % [fragments, "" if fragments == 1 else "s"])
	return ", ".join(parts)

# Rewards wait in the journal until a living run exists, so run setup cannot overwrite them.
func redeem_rewards(automatic := false) -> void:
	if fatal or not run_multiworld or not authenticated or not item_stream_ready or campaign == null \
			or (campaign.bank == 0 and campaign.dna_bank == 0 and campaign.plasmid_fragment_bank == 0):
		if not automatic:
			notify("No synchronized currency items available for a MultiworldGG run.")
		return
	var globals := get_node_or_null("/root/G")
	var player: Variant = globals.get("player") if globals != null else null
	if not is_instance_valid(player) or player.dead or not player.is_inside_tree() \
			or (automatic and player.get_instance_id() != settled_player):
		if not automatic:
			notify("Start a living MultiworldGG run before redeeming currency items.")
		return
	var coins: int = campaign.bank * coin_amount
	var dna: int = campaign.dna_bank * dna_amount
	var fragments: int = campaign.plasmid_fragment_bank * plasmid_fragment_amount
	var plasmids: Node = get_node_or_null("/root/PlasmidManager")
	if coins > 0 and not player.has_method("add_money"):
		_fail("The active player does not support the verified money reward API.")
		return
	if dna > 0 and not player.has_method("add_dna"):
		_fail("The active player does not support the verified DNA reward API.")
		return
	if fragments > 0 and (plasmids == null or not plasmids.has_method("add_plasmid_fragments")):
		_fail("The active PlasmidManager does not support the verified fragment reward API.")
		return
	if not campaign.redeem():
		_fail(campaign.error)
		return
	if coins > 0:
		player.add_money(coins)
	if dna > 0:
		player.add_dna(dna)
	if fragments > 0:
		plasmids.add_plasmid_fragments(fragments)
	get_node("/root/RunSaveManager").save_run()
	var summary := currency_summary(coins, dna, fragments)
	show_toast("Received " + summary)
	notify("Redeemed MultiworldGG rewards: " + summary + ".")

# --- Start button confirmation stack ---------------------------------------

static func _strong(text: String, color := "") -> String:
	return "[b][color=%s]%s[/color][/b]" % [color, text] if color else "[b]%s[/b]" % text

static func start_hint() -> String:
	return "\n".join([
		"[center][font_size=34]%s[/font_size][/center]" % _strong("MultiworldGG enabled!", ORANGE),
		"• This run contains unlocks %s" % _strong("for other players", BLUE),
		"• If you get %s or %s in the settings, they %s until you reconnect" % [
			_strong("disconnected"), _strong("disable MultiworldGG"), _strong("still spawn but can't be redeemed")],
		"• To only spawn advancements for you, %s in the settings then %s" % [
			_strong("disable MultiworldGG"), _strong("start a new run")]])

# ButtonConfirmation allows a single "Really Start" press. Its pressed wrapper is
# replaced by a stage list (vanilla organelle warning, then the MultiworldGG
# warning); the wrapper is called with confirmation off once every stage passed,
# which runs the original start handler and click sound.
func _hook_start(menu: Node) -> void:
	if not is_instance_valid(menu):
		return
	var button := menu.get_node_or_null("%ButtonSelect") as Button
	var vanilla_tip := menu.get_node_or_null("%StartWarningTooltip") as Control
	if button == null or vanilla_tip == null or button.has_meta("multiworldgg_start") \
			or not button.get("should_confirm") is Callable or not button.has_method("confirm"):
		log_line("Start menu layout changed; MultiworldGG start warning not added.")
		return
	var wrappers: Array[Callable] = []
	for connection in button.pressed.get_connections():
		var callable: Callable = connection.callable
		if callable.get_object() == button:
			button.pressed.disconnect(callable)
			wrappers.append(callable)
	if wrappers.is_empty():
		log_line("Start button confirmation changed; MultiworldGG start warning not added.")
		return
	var gate: Callable = button.should_confirm
	button.should_confirm = func(): return false
	button.set_meta("multiworldgg_start", {"menu": menu, "gate": gate, "wrappers": wrappers, "stage": 0})
	button.pressed.connect(_start_pressed.bind(button))
	button.mouse_exited.connect(_start_reset.bind(button))
	button.focus_exited.connect(_start_reset.bind(button))
	var tip := vanilla_tip.duplicate(0) as PanelContainer
	for child in tip.get_children():
		child.free()
	tip.name = "MultiworldGGStartTooltip"
	tip.unique_name_in_owner = false
	tip.visible = false
	tip.custom_minimum_size.x = 560
	var style: Variant = vanilla_tip.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style = style.duplicate()
		style.border_color = Color(ORANGE)
		tip.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	tip.add_child(margin)
	var label := RichTextLabel.new()
	label.name = "MultiworldGGStartLabel"
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 22)
	label.add_theme_font_size_override("bold_font_size", 22)
	var bold := FontVariation.new()
	bold.base_font = label.get_theme_font("normal_font")
	bold.variation_embolden = 0.9
	label.add_theme_font_override("bold_font", bold)
	label.text = start_hint()
	margin.add_child(label)
	button.add_child(tip)
	button.get_meta("multiworldgg_start").tip = tip
	start_buttons.append(button)
	log_line("MultiworldGG start warning added to the Start button.")

func start_stages(button: Button) -> Array:
	var hook: Dictionary = button.get_meta("multiworldgg_start")
	var stages: Array = []
	if not hook.menu.get("loadout_active"):
		return stages
	if hook.gate.is_valid() and hook.gate.call():
		stages.append("vanilla")
	if enabled:
		stages.append("multiworldgg")
	return stages

func _start_pressed(button: Button) -> void:
	var hook: Dictionary = button.get_meta("multiworldgg_start")
	if enabled and Isolation.active and hook.menu.get("loadout_active") and not campaign_ready():
		notify("Connect and synchronize this campaign before starting a MultiworldGG run. Your normal save is untouched.")
		return
	var stages := start_stages(button)
	var stage: int = hook.stage
	if stage < stages.size():
		hook.stage = stage + 1
		if stages[stage] == "vanilla":
			button.confirm()
		else:
			button.confirming = true
			button.text = START_TEXT
			var audio := get_node_or_null("/root/AudioManager")
			if audio != null and audio.get("confirm") != null:
				audio.confirm.play()
		return
	hook.stage = 0
	if enabled and hook.menu.get("loadout_active"):
		log_line("Start confirmed with MultiworldGG enabled.")
	for wrapper in hook.wrappers:
		if wrapper.is_valid():
			wrapper.call()

func _start_reset(button: Button) -> void:
	if is_instance_valid(button) and button.has_meta("multiworldgg_start"):
		button.get_meta("multiworldgg_start").stage = 0

# Stacks the MultiworldGG warning above the vanilla one while Start is hovered,
# focused or mid-confirmation.
func _update_start_tip() -> void:
	start_buttons = start_buttons.filter(func(button): return is_instance_valid(button))
	for button in start_buttons:
		_place_start_tip(button)

func _place_start_tip(button: Button) -> void:
	var hook: Dictionary = button.get_meta("multiworldgg_start")
	var menu: Node = hook.menu
	var tip: Control = hook.get("tip")
	if not is_instance_valid(tip) or not is_instance_valid(menu):
		return
	var show: bool = enabled and menu.get("loadout_active") == true and menu.get("starting_run") != true \
			and (menu.get("_start_button_hovered") == true or hook.stage > 0)
	tip.visible = show
	if not show:
		return
	var vanilla_tip := menu.get_node_or_null("%StartWarningTooltip") as Control
	var bottom := -10.0
	if vanilla_tip != null and vanilla_tip.visible:
		bottom = vanilla_tip.position.y - 8.0
	tip.size = tip.get_combined_minimum_size()
	tip.position = Vector2((button.size.x - tip.size.x) / 2.0, bottom - tip.size.y)

# --- Settings > MultiworldGG tab --------------------------------------------

func _inject_tab(menu: Node) -> void:
	if not is_instance_valid(menu) or menu.has_meta("multiworldgg_tab"):
		return
	var buttons: Variant = menu.get("tab_buttons")
	var content: Variant = menu.get("tab_content")
	if not buttons is Array or buttons.is_empty() or not content is Control \
			or content.get_child_count() != buttons.size():
		log_line("Options menu layout changed; MultiworldGG tab not added.")
		return
	menu.set_meta("multiworldgg_tab", true)
	var template: Button = buttons[buttons.size() - 1]
	var button := Button.new()
	button.set_script(template.get_script())
	button.name = "TabMultiworldGG"
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
	page.name = "button_multiworldgg"
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.custom_minimum_size = Vector2(0, PAGE_MIN_HEIGHT)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	page.add_child(box)
	var version := _label(box, SMALL_FONT_SIZE)
	version.text = _mod_version_text()
	var widgets := {"page": page}
	widgets.toggle = CheckButton.new()
	widgets.toggle.text = "Enable MultiworldGG for new runs"
	widgets.toggle.button_pressed = enabled
	widgets.toggle.add_theme_font_size_override("font_size", FONT_SIZE)
	widgets.toggle.add_theme_color_override("font_pressed_color", Color(0.4, 0.9, 1.0))
	widgets.toggle.add_theme_color_override("font_hover_pressed_color", Color(0.4, 0.9, 1.0))
	widgets.toggle.toggled.connect(set_enabled)
	box.add_child(widgets.toggle)
	widgets.run = _label(box, SMALL_FONT_SIZE)
	widgets.status = _label(box, FONT_SIZE)
	widgets.progress = _label(box, FONT_SIZE)
	var fields := GridContainer.new()
	fields.columns = 2
	fields.add_theme_constant_override("h_separation", 8)
	fields.add_theme_constant_override("v_separation", 4)
	box.add_child(fields)
	widgets.server = _line(fields, "Server", server, "host or host:port (port %d if omitted)" % DEFAULT_PORT)
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

func _mod_version_text() -> String:
	var manifest_path := "res://mods-unpacked/ViMaSter-MultiworldGGShop/manifest.json"
	var text := FileAccess.get_file_as_string(manifest_path)
	var read_error := FileAccess.get_open_error()
	var parser := JSON.new()
	if read_error != OK:
		log_line("Cannot read mod version: " + error_string(read_error))
	elif parser.parse(text) != OK:
		log_line("Cannot read mod version: malformed manifest JSON.")
	elif not parser.data is Dictionary or not parser.data.get("version_number") is String \
			or str(parser.data.version_number).strip_edges().is_empty():
		log_line("Cannot read mod version: manifest version_number is missing or invalid.")
	else:
		return "Mod version: " + str(parser.data.version_number)
	return "Mod version: unavailable (see client log)"

func run_text() -> String:
	if not _run_active():
		if Isolation.active:
			if not Unlocks.hooks_ready:
				return "Isolated save selected. Restart Pathogenic once to activate progression hooks."
			return "Isolated campaign save: %s. Normal saves are not used. %s" % [
				Isolation.PM.profile_dir(), "Ready." if campaign_ready() else "Connect and synchronize before playing."]
		return "Normal save selected. Enabling MultiworldGG selects a separate server-bound campaign."
	if run_multiworld:
		return "This run uses MultiworldGG (locked at run start). Disconnects block remote unlocks until you reconnect."
	return "This run is vanilla (MultiworldGG was off when it started). Enabling applies to the next run."

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
		widgets.toggle.set_pressed_no_signal(enabled)
		widgets.run.text = run_text()
		widgets.status.text = status
		if campaign != null:
			widgets.progress.text = "Checks: %d sent, %d/%d confirmed. Next: %s." % [
				campaign.checks.size(), campaign.confirmed.size(), count, tooltip_title()]
			widgets.progress.text += "\nVictories: %d/%d." % [campaign.victories.size(), required_victories]
			widgets.progress.text += "\nRemote unlocks in: %s." % sources_text()
			if campaign.bank > 0 or campaign.dna_bank > 0 or campaign.plasmid_fragment_bank > 0:
				widgets.progress.text += " Waiting for a living MultiworldGG run: %s." % currency_summary(
					campaign.bank * coin_amount, campaign.dna_bank * dna_amount,
					campaign.plasmid_fragment_bank * plasmid_fragment_amount)
		else:
			widgets.progress.text = "No campaign loaded yet."
		if widgets.revision != log_revision:
			widgets.revision = log_revision
			widgets.log.text = "\n".join(log_lines)
	pages = live
