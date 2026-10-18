extends Object

const Hooks = preload("res://mods-unpacked/ViMaSter-MultiworldGGShop/plasmid.gd")
var hooks := Hooks.new()

func restore(chain):
	hooks.restore(chain)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		hooks.free()
