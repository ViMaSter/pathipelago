extends Node2D

var looted := false

func _on_reward_picked_up(_reward) -> void:
	looted = true
