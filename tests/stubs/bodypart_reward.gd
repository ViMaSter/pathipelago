extends Node2D

signal picked_up(reward)

var choose_one := false
var consumed := false
var deleted := false
var bodypart: Node2D
var unique_from: Array = []
var pickup_area: Node
var vanilla_picks := 0
var last_taker: Node

func _init() -> void:
	pickup_area = load("res://tests/stubs/pickup_area.gd").new()
	pickup_area.name = "PickupArea"
	add_child(pickup_area)
	# v1.3.13 wires the pickup to take_reward(taker) in bodypart_reward.tscn.
	pickup_area.picked.connect(take_reward)
	for pair in [["Label", Label.new()], ["MutationIcon", Sprite2D.new()]]:
		pair[1].name = pair[0]
		add_child(pair[1])
		pair[1].owner = self
		pair[1].unique_name_in_owner = true
	get_node("%Label").text = "Pressurized Spicule"
	bodypart = Node2D.new()
	add_child(bodypart)

func _player_entered() -> void:
	take_reward()

func take_reward(taker: Node = null) -> void:
	last_taker = taker
	vanilla_picks += 1
	consumed = true

func _disable_player_block() -> void:
	pass

func _detach_pickup_area() -> void:
	pass

func _confirm_choose_one_siblings() -> void:
	if choose_one:
		for r in unique_from:
			if r != self:
				r.consumed = true
				r.deleted = true

func _confirm_after_take_animation() -> void:
	deleted = true
	picked_up.emit(self)
