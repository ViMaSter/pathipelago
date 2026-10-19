extends RefCounted

const Isolation = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/isolation.gd")
const ITEM_BASE := 402960000
const LOCATION_BASE := 402970000
const CATALOG := "res://mods-unpacked/ViMaSter-MultiworldGGShop/catalog.json"
static var entries: Dictionary = {}
static var conditions: Dictionary = {}
static var nodes: Dictionary = {}
static var selected: Dictionary = {}
static var owned: Dictionary = {}
static var configured := false
static var synchronized := false
static var evaluating_native := false
static var hooks_ready := false
static var resources: Dictionary = {}
static var loadouts: Dictionary = {}
static var error := ""

static func load_catalog() -> bool:
	if not entries.is_empty():
		return true
	var parser := JSON.new()
	var text := FileAccess.get_file_as_string(CATALOG)
	if FileAccess.get_open_error() != OK or parser.parse(text) != OK \
			or not parser.data is Dictionary or parser.data.get("schema") != 1 \
			or not parser.data.get("entries") is Array:
		error = "Cannot read the Pathogenic unlock catalogue. Reinstall the complete mod."
		return false
	for entry in parser.data.entries:
		if not entry is Dictionary or not entry.get("id") is float and not entry.get("id") is int \
				or int(entry.id) < 0 or entries.has(int(entry.id)) \
				or not entry.get("kind") is String or not entry.get("name") is String:
			error = "Malformed Pathogenic unlock catalogue."
			entries.clear()
			return false
		entries[int(entry.id)] = entry
		if entry.get("resource", "") != "":
			resources[str(entry.resource)] = int(entry.id)
		if entry.get("condition", "") != "":
			var path := str(entry.condition)
			if not conditions.has(path):
				conditions[path] = []
			conditions[path].append(int(entry.id))
		if entry.kind == "plasmid":
			nodes["%d/%s" % [int(entry.parasite), entry.node]] = int(entry.id)
		elif entry.kind == "loadout":
			loadouts["%d/%s" % [int(entry.parasite), entry.bodypart]] = int(entry.id)
	return true

static func configure(ids: Array) -> bool:
	if not load_catalog():
		return false
	var next := {}
	for id in ids:
		if not (id is int or id is float) or float(id) != floor(float(id)) \
				or not entries.has(int(id)) or next.has(int(id)):
			error = "Server supplied an unknown or duplicate unlock catalogue ID."
			return false
		next[int(id)] = true
	selected = next
	owned.clear()
	configured = true
	synchronized = false
	return true

static func reset() -> void:
	configured = false
	synchronized = false
	selected.clear()
	owned.clear()

static func governs() -> bool:
	return Isolation.active and configured

static func received(id: int) -> bool:
	return governs() and owned.has(id)

static func reconcile(items: Array, confirmed: Array) -> bool:
	var next := {}
	for item in items:
		var id := int(item) - ITEM_BASE
		if selected.has(id):
			next[id] = true
	for location in confirmed:
		var id := int(location) - LOCATION_BASE
		if selected.has(id):
			next[id] = true
	var changed := next != owned
	owned = next
	return changed

static func condition_override(path: String) -> Variant:
	if not governs():
		return null
	var relevant := false
	for id in conditions.get(path, []):
		if selected.has(id):
			relevant = true
			if not owned.has(id):
				return false
	return true if relevant else null

static func resource_override(path: String) -> Variant:
	var id: int = resources.get(path, -1)
	return owned.has(id) if governs() and selected.has(id) else null

static func loadout_override(bodypart: String, parasite: int) -> Variant:
	var id: int = loadouts.get("%d/%s" % [parasite, bodypart], -1)
	return owned.has(id) if governs() and selected.has(id) else null

static func natural_condition(condition: Resource) -> bool:
	var previous := evaluating_native
	evaluating_native = true
	var result: bool = condition.is_unlocked()
	evaluating_native = previous
	return result

static func plasmid_id(node: Node, parasite: int) -> int:
	return int(nodes.get("%d/%s" % [parasite, node.name], -1))

static func native_earned(id: int) -> void:
	if not governs() or not selected.has(id):
		return
	var tree := Engine.get_main_loop() as SceneTree
	var client := tree.root.get_node_or_null("MultiworldGGShop") if tree != null else null
	if client != null:
		client.earn_unlock(id)

static func notify(message: String) -> void:
	Isolation.report(message)
