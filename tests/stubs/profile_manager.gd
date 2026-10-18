extends Node

const PROFILE_FILES := ["save.json", "run_save.json", "past_runs.json", "player_config.cfg", "local_settings.cfg"]
static var active := 1
static var _initialized := true
static var _legacy_fallback := false
static var migrated := true
static var migrated_legacy := false
var local_writes := 0

static func _ensure_init() -> void:
	_initialized = true

static func profile_dir(idx := -1) -> String:
	return "user://profile_%d" % (active if idx == -1 else idx)

static func profile_path(filename: String, idx := -1) -> String:
	return profile_dir(idx).path_join(filename)

func persist() -> void:
	local_writes += 1

func had_legacy_migration() -> bool:
	return migrated_legacy

func has_seen_profile_intro() -> bool:
	return false

func set_seen_profile_intro() -> void:
	local_writes += 1

func switch_to(idx: int) -> void:
	active = idx
	local_writes += 1

func create_profile(idx: int) -> void:
	switch_to(idx)

func clear_profile(_idx: int) -> void:
	local_writes += 1
