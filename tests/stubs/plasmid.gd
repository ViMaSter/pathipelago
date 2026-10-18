extends Node2D

var active := false
var available := true
var map: Node
var native_purchases := 0

func restore():
	active = false

func save():
	pass

func _on_pressed():
	native_purchases += 1
	active = not active
	save()

func get_ui_name() -> String:
	return "Test Plasmid"

func get_description() -> String:
	return "Test effect"

func tooltip_text() -> String:
	return "Native cost"
