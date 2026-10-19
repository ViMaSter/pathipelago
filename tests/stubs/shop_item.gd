extends Node2D

var paid := false
var pay_with_blood := false
var pending_refund := 0
var cost := 10
var _rewards: Array = []
var vanilla_purchases := 0
var finalized := false
var last_taker: Node

func _on_picked(taker: Node) -> void:
	last_taker = taker
	vanilla_purchases += 1

func make_free() -> void:
	paid = true

func _take_for_free(taker: Node) -> void:
	last_taker = taker
	vanilla_purchases += 1

func finalize_purchase() -> void:
	finalized = true

func get_cost_for(taker: Node) -> int:
	return maxi(1, roundi(cost * (1.0 - taker.shop_discount)))
