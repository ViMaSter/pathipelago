extends Button

var bodypart_res: Resource
var unlock: Resource
var loadout_category: Resource

func _init() -> void:
	var lock := Control.new()
	lock.name = "Lock"
	add_child(lock)

func is_unlocked() -> bool:
	return unlock == null or unlock.is_unlocked()
