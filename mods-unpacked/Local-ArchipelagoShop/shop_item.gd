extends "res://scn/environ/pickups/shop_item.gd"

func _ap_client() -> Node:
	return get_node_or_null("/root/ArchipelagoShop")

func _on_picked() -> void:
	var client := _ap_client()
	if client == null:
		push_error("Archipelago shop client is unavailable; purchase blocked.")
		return
	if client.eligible(self):
		client.purchase(self)
		return
	super()

func make_free() -> void:
	var client := _ap_client()
	if client == null:
		push_error("Archipelago shop client is unavailable; theft blocked.")
		return
	if client.eligible(self):
		client.notify("AP shipments retain their price after the shopkeeper fight.")
		return
	super()

func _take_for_free() -> void:
	var client := _ap_client()
	if client == null:
		push_error("Archipelago shop client is unavailable; theft blocked.")
		return
	if client.eligible(self):
		client.purchase(self)
		return
	super()
