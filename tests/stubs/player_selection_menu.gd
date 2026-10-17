extends Control

var loadout_active := false
var starting_run := false
var _start_button_hovered := false
var full := true
var clicks := 0
var starts := 0

func _init() -> void:
	var button := Button.new()
	button.name = "ButtonSelect"
	button.text = "Start"
	button.set_script(load("res://tests/stubs/button_confirmation.gd"))
	add_child(button)
	button.owner = self
	button.unique_name_in_owner = true
	button.pressed.connect(func(): starts += 1)
	var tip := PanelContainer.new()
	tip.name = "StartWarningTooltip"
	tip.visible = false
	button.add_child(tip)
	tip.owner = self
	tip.unique_name_in_owner = true

func _ready() -> void:
	$ButtonSelect.should_confirm = func(): return loadout_active and not full
