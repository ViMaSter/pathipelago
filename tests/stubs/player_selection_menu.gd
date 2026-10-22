extends Control

var loadout_active := false
var starting_run := false
var _start_button_hovered := false
var full := true
var clicks := 0
var starts := 0
var profile_updates := 0
var refreshed_profile := -1

class LoadoutDouble extends Node:
	var player: Node
	var player_setups := 0
	var bodypart_setups := 0
	var refreshed_profile := -1
	func setup_player() -> void:
		player_setups += 1
		refreshed_profile = load("res://scn/profile_manager.gd").active
	func setup_bodyparts() -> void:
		bodypart_setups += 1

func update() -> void:
	profile_updates += 1
	refreshed_profile = load("res://scn/profile_manager.gd").active

func _on_button_select_pressed() -> void:
	if loadout_active:
		starts += 1
	else:
		loadout_active = true

func _init() -> void:
	var loadout := LoadoutDouble.new()
	loadout.name = "LoadoutMenu"
	add_child(loadout)
	loadout.owner = self
	loadout.unique_name_in_owner = true
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
