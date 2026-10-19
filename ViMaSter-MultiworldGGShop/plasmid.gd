extends Object

const Unlocks = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/unlocks.gd")

func _id(node: Node) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	return Unlocks.plasmid_id(node, int(tree.root.get_node("G").selected_parasite))

func restore(chain):
	chain.execute_next()
	var node: Node = chain.reference_object
	var id := _id(node)
	if Unlocks.governs() and Unlocks.selected.has(id) and not Unlocks.received(id):
		node.set("active", false)

func save(chain):
	chain.execute_next()
	var node: Node = chain.reference_object
	if node.get_meta("multiworld_natural_purchase", false) and node.get("active"):
		Unlocks.native_earned(_id(node))

func _on_pressed(chain):
	var node: Node = chain.reference_object
	var id := _id(node)
	if not Unlocks.governs() or not Unlocks.selected.has(id):
		chain.execute_next()
		return
	if not Unlocks.synchronized:
		Unlocks.notify("Connect and synchronize before changing campaign Plasmids.")
		return
	if Unlocks.received(id):
		var map: Node = node.get("map")
		if node.get("active"):
			if not map.can_deactivate(node):
				Unlocks.notify("This Plasmid still connects other assigned nodes.")
				return
		elif not node.get("available"):
			Unlocks.notify("Connect this Plasmid to your assigned map before activating it.")
			return
		node.set("active", not node.get("active"))
		node.save()
		map.reset_availability()
		node.get_node("/root/SignalBus").emit_signal("plasmid_state_changed")
		map.show_tooltip(node)
		return
	node.set_meta("multiworld_natural_purchase", true)
	chain.execute_next()
	node.remove_meta("multiworld_natural_purchase")
	if node.get("active"):
		Unlocks.native_earned(id)

func tooltip_text(chain) -> String:
	var node: Node = chain.reference_object
	if Unlocks.received(_id(node)):
		return "[b]%s[/b]\n%s\nServer unlocked. Assign/unassign free; no point refund." % [
			node.get_ui_name(), node.get_description()]
	return chain.execute_next()
