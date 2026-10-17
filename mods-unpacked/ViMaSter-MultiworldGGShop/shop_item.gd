extends "res://scn/environ/pickups/shop_item.gd"

func _multiworld_client() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("MultiworldGGShop") if tree != null else null

func _on_picked() -> void:
	var client := _multiworld_client()
	if client == null:
		push_error("MultiworldGG shop client is unavailable; purchase blocked.")
		return
	if client.handle_pick(self):
		return
	super()

# The MultiworldGG pedestal keeps its price after the shopkeeper fight: stealing it would
# otherwise hand out the displayed local upgrade.
func make_free() -> void:
	var client := _multiworld_client()
	if client == null:
		push_error("MultiworldGG shop client is unavailable; theft blocked.")
		return
	if client.is_multiworld(self):
		client.notify("The MultiworldGG pedestal keeps its price after the shopkeeper fight.")
		return
	super()

func _take_for_free() -> void:
	var client := _multiworld_client()
	if client == null:
		push_error("MultiworldGG shop client is unavailable; theft blocked.")
		return
	if client.handle_pick(self, true):
		return
	super()
