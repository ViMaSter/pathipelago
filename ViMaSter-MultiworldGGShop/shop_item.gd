extends "res://scn/environ/pickups/shop_item.gd"

func _multiworld_client() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("MultiworldGGShop") if tree != null else null

# v1.3.15 defaults the taker to the local player; overrides must keep that optional signature.
func _default_taker(taker: Node) -> Node:
	if taker != null:
		return taker
	var globals := get_node_or_null("/root/G")
	return globals.get("player") if globals != null else null

func _on_picked(taker: Node = null) -> void:
	taker = _default_taker(taker)
	var client := _multiworld_client()
	if client == null:
		push_error("MultiworldGG shop client is unavailable; purchase blocked.")
		return
	if client.handle_pick(self, false, taker):
		return
	super(taker)

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

func _take_for_free(taker: Node = null) -> void:
	taker = _default_taker(taker)
	var client := _multiworld_client()
	if client == null:
		push_error("MultiworldGG shop client is unavailable; theft blocked.")
		return
	if client.handle_pick(self, true, taker):
		return
	super(taker)
