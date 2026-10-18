extends "res://scn/metaprogression/plasmids/plasmid_manager.gd"

const Unlocks = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/unlocks.gd")

func apply_saved(active_entries: Array) -> void:
	if not Unlocks.governs():
		await super(active_entries)
		return
	var selected: int = get_node("/root/G").selected_parasite
	var allowed := active_entries.filter(func(entry):
		var name: String = entry if entry is String else str(entry.get("name", ""))
		var id: int = Unlocks.nodes.get("%d/%s" % [selected, name], -1)
		return not Unlocks.selected.has(id) or Unlocks.received(id))
	await super(allowed)
