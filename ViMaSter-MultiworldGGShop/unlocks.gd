extends RefCounted

const Isolation = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/isolation.gd")
const ITEM_BASE := 402960000
const LOCATION_BASE := 402970000
# Plasmid slot N uses pseudo ID SLOT_BASE + N for its item and "Earn Plasmid Slot N" check.
const SLOT_BASE := 30000
const CATALOG := "res://mods-unpacked/ViMaSter-MultiworldGGShop/catalog.json"
# Every organelle can drop in a multiworld campaign; their native gates live in these files.
const BODYPART_ROOT := "res://scn/player/bodyparts/"
# Schema 6 seeds no longer randomize these catalogue kinds; their IDs remain reserved.
const RETIRED_KINDS := ["organelle", "environment"]
static var entries: Dictionary = {}
static var conditions: Dictionary = {}
static var nodes: Dictionary = {}
static var selected: Dictionary = {}
static var owned: Dictionary = {}
static var configured := false
static var start_with_all_characters := false
static var synchronized := false
static var evaluating_native := false
static var hooks_ready := false
static var resources: Dictionary = {}
static var loadouts: Dictionary = {}
static var slots: Dictionary = {}
static var slot_plasmids: Dictionary = {}
static var slot_mode := false
static var remote: Dictionary = {}
static var natural: Dictionary = {}
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
			if entry.get("slot") is float or entry.get("slot") is int:
				var slot := SLOT_BASE + int(entry.slot)
				slots[int(entry.id)] = slot
				if not slot_plasmids.has(slot):
					slot_plasmids[slot] = []
				slot_plasmids[slot].append(int(entry.id))
		elif entry.kind == "loadout":
			loadouts["%d/%s" % [int(entry.parasite), entry.bodypart]] = int(entry.id)
	return true

static func configure(ids: Array, all_characters: bool = false, shared_slots: bool = false,
		retired_kinds: bool = false) -> bool:
	if not load_catalog():
		return false
	var next := {}
	for id in ids:
		if not (id is int or id is float) or float(id) != floor(float(id)) \
				or not entries.has(int(id)) or next.has(int(id)):
			error = "Server supplied an unknown or duplicate unlock catalogue ID."
			return false
		next[int(id)] = true
		if all_characters and entries[int(id)].kind == "character":
			error = "Server included character unlocks despite starting with all characters."
			return false
		if retired_kinds and entries[int(id)].kind in RETIRED_KINDS:
			error = "Server selected a retired organelle or environment unlock."
			return false
		if shared_slots and entries[int(id)].kind == "plasmid" and not slots.has(int(id)):
			error = "Server selected a Plasmid without a shared slot."
			return false
	selected = next
	start_with_all_characters = all_characters
	slot_mode = shared_slots
	remote.clear()
	for id in selected:
		remote[remote_id(id)] = true
	owned.clear()
	natural.clear()
	configured = true
	synchronized = false
	return true

static func reset() -> void:
	configured = false
	start_with_all_characters = false
	synchronized = false
	slot_mode = false
	selected.clear()
	remote.clear()
	owned.clear()
	natural.clear()

static func governs() -> bool:
	return Isolation.active and configured

static func received(id: int) -> bool:
	return governs() and owned.has(id)

# Item/location pseudo ID: the shared slot for plasmids in slot mode, else the catalogue ID.
static func remote_id(id: int) -> int:
	return slots[id] if slot_mode and slots.has(id) else id

static func is_slot(id: int) -> bool:
	return id >= SLOT_BASE

static func reconcile(items: Array, confirmed: Array) -> bool:
	var next := {}
	for item in items:
		var id := int(item) - ITEM_BASE
		if not remote.has(id):
			continue
		if is_slot(id):
			for plasmid in slot_plasmids.get(id, []):
				if selected.has(plasmid):
					next[plasmid] = true
		else:
			next[id] = true
	# Slot checks hold randomized items; natural plasmids are tracked per character instead.
	for location in confirmed:
		var id := int(location) - LOCATION_BASE
		if remote.has(id) and not is_slot(id):
			next[id] = true
	for id in natural:
		if selected.has(id):
			next[id] = true
	var changed := next != owned
	owned = next
	return changed

static func condition_override(path: String) -> Variant:
	if not governs():
		return null
	if path.begins_with(BODYPART_ROOT):
		return true
	var relevant := false
	for id in conditions.get(path, []):
		if start_with_all_characters and entries[id].kind == "character":
			return true
		if selected.has(id):
			relevant = true
			if not owned.has(id):
				return false
	return true if relevant else null

static func resource_override(path: String) -> Variant:
	if governs() and path.begins_with(BODYPART_ROOT):
		return true
	var id: int = resources.get(path, -1)
	if governs() and start_with_all_characters and entries.has(id) \
			and entries[id].kind == "character":
		return true
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
