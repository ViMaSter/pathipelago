extends RefCounted

const PM = preload("res://scn/profile_manager.gd")
const PC = preload("res://addons/maaacks_input_remapping/base/scripts/player_config.gd")
const ROOT := "user://multiworldgg_shop"
# Game preferences (volumes, language, display options) shared by every isolated
# profile. Seeded read-only from the normal profile; never written back to it.
const PREFERENCES := ROOT + "/preferences.json"
const LOCAL_SECTION := "settings"
static var active := false
static var identity := ""
static var error := ""
static var previous: Dictionary = {}
static var generation := 0
static var achievements: Array[WeakRef] = []
static var _preferences_text := ""

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
	_seed_profile(directory)
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
	# Like the native profile switch, re-apply preferences to the live engine so
	# audio buses and display options follow the newly selected profile.
	var audio := tree.root.get_node_or_null("AudioManager")
	if audio != null and audio.has_method("apply_volume_settings"):
		audio.apply_volume_settings()
	var globals := tree.root.get_node_or_null("G")
	if globals != null and globals.has_method("reload_settings_from_save"):
		globals.reload_settings_from_save()
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

## Records the preferences of the loaded profile. Only reads SaveManager memory;
## the normal profile is a read-only source and is never written.
static func capture_preferences(tree: SceneTree) -> void:
	var save := tree.root.get_node_or_null("SaveManager")
	if save == null or not save.get("save_data") is Dictionary:
		return
	var settings = save.save_data.get("settings")
	if not settings is Dictionary or settings.is_empty():
		return
	var local := {}
	var cfg = save.get("_local_cfg")
	if cfg is ConfigFile and cfg.has_section(LOCAL_SECTION):
		for key in cfg.get_section_keys(LOCAL_SECTION):
			local[key] = var_to_str(cfg.get_value(LOCAL_SECTION, key))
	_store_preferences({"settings": settings.duplicate(true), "local": local})

static func preferences() -> Dictionary:
	if FileAccess.file_exists(PREFERENCES):
		var data = JSON.parse_string(FileAccess.get_file_as_string(PREFERENCES))
		if data is Dictionary and data.get("settings") is Dictionary and data.get("local") is Dictionary:
			return data
	return _normal_preferences()

static func _normal_preferences() -> Dictionary:
	var pointer := ConfigFile.new()
	var index := 1
	if pointer.load("user://profiles.cfg") == OK:
		index = clampi(int(pointer.get_value("profiles", "active", 1)), 1, 3)
	var directory := "user://profile_%d" % index
	var save_path := directory.path_join("save.json")
	if index == 1 and not FileAccess.file_exists(save_path):
		save_path = "user://save.json"
	var settings := {}
	if FileAccess.file_exists(save_path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if data is Dictionary and data.get("settings") is Dictionary:
			settings = data.settings
	var local := {}
	var cfg := ConfigFile.new()
	if cfg.load(directory.path_join("local_settings.cfg")) == OK and cfg.has_section(LOCAL_SECTION):
		for key in cfg.get_section_keys(LOCAL_SECTION):
			local[key] = var_to_str(cfg.get_value(LOCAL_SECTION, key))
	return {"settings": settings, "local": local}

static func _store_preferences(data: Dictionary) -> void:
	var text := JSON.stringify(data, "\t", true)
	if text == _preferences_text:
		return
	DirAccess.make_dir_recursive_absolute(ROOT)
	var file := FileAccess.open(PREFERENCES, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()
	_preferences_text = text

# Writes the shared preferences into an isolated profile before its stores load.
# Only reserved MultiworldGG profile directories reach this function.
static func _seed_profile(directory: String) -> void:
	var data := preferences()
	if data.settings.is_empty() and data.local.is_empty():
		return
	_store_preferences(data)
	var save_path := directory.path_join("save.json")
	var save := {}
	if FileAccess.file_exists(save_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if not parsed is Dictionary:
			return
		save = parsed
	if not data.settings.is_empty():
		var settings = save.get("settings")
		if not settings is Dictionary:
			settings = {}
		settings.merge(data.settings, true)
		save["settings"] = settings
		var temp := directory.path_join("multiworldgg-save.tmp")
		var file := FileAccess.open(temp, FileAccess.WRITE)
		if file == null:
			return
		file.store_string(JSON.stringify(save, "\t"))
		file.close()
		if DirAccess.rename_absolute(temp, save_path) != OK:
			DirAccess.remove_absolute(temp)
			return
	if not data.local.is_empty():
		var local_path := directory.path_join("local_settings.cfg")
		var cfg := ConfigFile.new()
		if FileAccess.file_exists(local_path) and cfg.load(local_path) != OK:
			return
		for key in data.local:
			# Local values keep their engine types (JSON would turn ints into floats).
			if data.local[key] is String:
				cfg.set_value(LOCAL_SECTION, key, str_to_var(data.local[key]))
		cfg.save(local_path)
