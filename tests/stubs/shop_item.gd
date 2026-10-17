extends Node2D

var paid := false
var pay_with_blood := false
var pending_refund := 0
var cost := 10
var _rewards: Array = []
var vanilla_purchases := 0
var finalized := false

func _on_picked() -> void:
	vanilla_purchases += 1

func make_free() -> void:
	paid = true

func _take_for_free() -> void:
	vanilla_purchases += 1

func finalize_purchase() -> void:
	finalized = true
