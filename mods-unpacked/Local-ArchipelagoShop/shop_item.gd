extends "res://scn/environ/pickups/shop_item.gd"

func _ap_client() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("ArchipelagoShop") if tree != null else null

func _on_picked() -> void:
	var client := _ap_client()
	if client == null:
		push_error("Archipelago shop client is unavailable; purchase blocked.")
		return
	if client.handle_pick(self):
		return
	super()

# The AP pedestal keeps its price after the shopkeeper fight: stealing it would
# otherwise hand out the displayed local upgrade.
func make_free() -> void:
	var client := _ap_client()
	if client == null:
		push_error("Archipelago shop client is unavailable; theft blocked.")
		return
	if client.is_ap(self):
		client.notify("The Archipelago pedestal keeps its price after the shopkeeper fight.")
		return
	super()

func _take_for_free() -> void:
	var client := _ap_client()
	if client == null:
		push_error("Archipelago shop client is unavailable; theft blocked.")
		return
	if client.handle_pick(self, true):
		return
	super()
