extends RefCounted

const PM = preload("res://scn/profile_manager.gd")
const PC = preload("res://addons/maaacks_input_remapping/base/scripts/player_config.gd")
const ROOT := "user://multiworldgg_shop"
static var active := false
static var identity := ""
static var error := ""
static var previous: Dictionary = {}
static var generation := 0
static var achievements: Array[WeakRef] = []

static func boot() -> void:
	var config := ConfigFile.new()
	var result := config.load(ROOT + "/connection.cfg")
	if result == OK and config.get_value("mod", "enabled", false) == true:
		enter("")
	elif result != OK and result != ERR_FILE_NOT_FOUND:
		error = "Cannot read MultiworldGG configuration: " + error_string(result)
		# An unreadable configuration must never fall through to a local save.
		enter("")

static func enter(campaign_identity: String) -> bool:
	if active and identity == campaign_identity:
		return error.is_empty()
	if not active:
		previous = {"active": PM.active, "initialized": PM._initialized,
			"legacy": PM._legacy_fallback, "migrated": PM.migrated,
			"migrated_legacy": PM.migrated_legacy,
			"config_path": PC.CONFIG_FILE_LOCATION, "config": PC.config_file}
		# Route before any fallible I/O, so a profile/configuration error cannot
		# make native autoloads open or flush the normal profile during boot.
		PM.active = 4
		PM._initialized = true
		PM._legacy_fallback = false
		PM.migrated = true
		PM.migrated_legacy = false
		PC.CONFIG_FILE_LOCATION = "user://profile_4/player_config.cfg"
		PC.config_file = null
		active = true
		identity = ""
	# Native consumers preload ProfileManager and call its static path helpers.
	# A reserved index routes all of them, not just SaveManager, without changing
	# the persisted normal-profile pointer or adopting legacy recovery files.
	var index := 4 if campaign_identity.is_empty() else 16 + campaign_identity.sha256_text().left(14).hex_to_int()
	var directory := "user://profile_%d" % index
	var result := DirAccess.make_dir_recursive_absolute(directory)
	if result != OK:
		error = "Cannot create isolated campaign profile: " + error_string(result)
		return false
	var marker := directory.path_join("multiworldgg-identity.json")
	if FileAccess.file_exists(marker):
		var parser := JSON.new()
		var text := FileAccess.get_file_as_string(marker)
		if FileAccess.get_open_error() != OK or parser.parse(text) != OK \
				or not parser.data is Dictionary or parser.data.get("identity") != campaign_identity:
			error = "Campaign profile identity is unreadable or mismatched; it has not been reset."
			return false
	else:
		# Never adopt an existing save merely because its directory index matches.
		for filename in PM.PROFILE_FILES:
			if FileAccess.file_exists(directory.path_join(filename)):
				error = "Unidentified files already occupy the campaign profile; refusing to use them."
				return false
		var file := FileAccess.open(marker, FileAccess.WRITE)
		if file == null:
			error = "Cannot write campaign profile identity: " + error_string(FileAccess.get_open_error())
			return false
		file.store_string(JSON.stringify({"identity": campaign_identity}))
		file.flush()
		result = file.get_error()
		file.close()
		if result != OK:
			error = "Cannot persist campaign profile identity: " + error_string(result)
			return false
	PM.active = index
	PM._initialized = true
	PM._legacy_fallback = false
	PM.migrated = true
	PM.migrated_legacy = false
	PC.CONFIG_FILE_LOCATION = directory.path_join("player_config.cfg")
	PC.config_file = null
	active = true
	identity = campaign_identity
	generation += 1
	return true

static func leave() -> void:
	if not active:
		return
	PM.active = previous.active
	PM._initialized = previous.initialized
	PM._legacy_fallback = previous.legacy
	PM.migrated = previous.migrated
	PM.migrated_legacy = previous.migrated_legacy
	PC.CONFIG_FILE_LOCATION = previous.config_path
	PC.config_file = previous.config
	active = false
	identity = ""
	generation += 1
	PM._ensure_init()

static func reload_stores(tree: SceneTree) -> void:
	for name in ["SaveManager", "RunSaveManager"]:
		var store := tree.root.get_node_or_null(name)
		if store != null:
			store.reload()
	var plasmids := tree.root.get_node_or_null("PlasmidManager")
	if plasmids != null:
		plasmids.reset()
		plasmids.plasmid_fragments = plasmids.read_plasmid_fragments()
	var stats := tree.root.get_node_or_null("StatManager")
	if stats != null:
		stats.initialize()
	var antibiotics := tree.root.get_node_or_null("AntibioticsManager")
	if antibiotics != null:
		antibiotics.update()
	for reference in achievements:
		var achievement: Resource = reference.get_ref()
		if achievement != null:
			_refresh_achievement(achievement, tree)
	var bus := tree.root.get_node_or_null("SignalBus")
	if bus != null and bus.has_signal("profile_changed"):
		bus.emit_signal("profile_changed")

static func _refresh_achievement(achievement: Resource, tree: SceneTree) -> void:
	var snapshot := generation
	achievement.set_meta("multiworld_generation", snapshot)
	achievement.set("_achieved", false)
	if active:
		return
	# Do not rerun subclass initialization: it installs one-time stat listeners.
	var saved: bool = tree.root.get_node("SaveManager").read_custom(
		"achievements", achievement.get_id(), false)
	var platform: bool = await tree.root.get_node("Platform").is_achievement_unlocked(achievement.get_id())
	if generation == snapshot and not active:
		achievement.set("_achieved", saved or platform)

static func report(message: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var client := tree.root.get_node_or_null("MultiworldGGShop") if tree != null else null
	if client != null:
		client.notify(message)
	else:
		push_warning("[MultiworldGG] " + message)
