extends RefCounted

# Received "Organelle: <name>" items, delivered into the in-run editor one at a time.
const ITEM_BASE := 402980000
const POOL := "res://mods-unpacked/ViMaSter-MultiworldGGShop/organelles.json"
const BODYPART_ROOT := "res://scn/player/bodyparts/"
static var entries: Dictionary = {}
static var selected: Dictionary = {}
static var error := ""

static func load_pool() -> bool:
	if not entries.is_empty():
		return true
	var parser := JSON.new()
	var text := FileAccess.get_file_as_string(POOL)
	if FileAccess.get_open_error() != OK or parser.parse(text) != OK \
			or not parser.data is Dictionary or parser.data.get("schema") != 1 \
			or not parser.data.get("entries") is Array:
		error = "Cannot read the Pathogenic organelle pool. Reinstall the complete mod."
		return false
	for entry in parser.data.entries:
		if not entry is Dictionary or not (entry.get("id") is float or entry.get("id") is int) \
				or int(entry.id) < 1 or entries.has(int(entry.id)) \
				or not entry.get("name") is String \
				or not str(entry.get("resource", "")).begins_with(BODYPART_ROOT):
			error = "Malformed Pathogenic organelle pool."
			entries.clear()
			return false
		entries[int(entry.id)] = entry
	return true

static func configure(ids: Array) -> bool:
	if not ids.is_empty() and not load_pool():
		return false
	var next := {}
	for id in ids:
		if not (id is int or id is float) or float(id) != floor(float(id)) \
				or not entries.has(int(id)) or next.has(int(id)):
			error = "Server supplied an unknown or duplicate organelle ID."
			return false
		next[int(id)] = true
	selected = next
	return true

static func reset() -> void:
	selected.clear()

static func item_id(id: int) -> int:
	return ITEM_BASE + id

static func id_of(item: int) -> int:
	return item - ITEM_BASE if selected.has(item - ITEM_BASE) else -1

static func display_name(id: int) -> String:
	return str(entries[id].name) if entries.has(id) else "Organelle %d" % id

static func resource(id: int) -> String:
	return str(entries[id].resource) if entries.has(id) else ""
