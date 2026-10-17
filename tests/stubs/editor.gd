extends Control

# Mirrors the parts of res://scn/ui/editor.gd the client touches.
var mutations: Array = []
var mutation_buttons: Array[BaseButton] = []
var _mutation_gen := 0
var state := 2
var pending_mutation_index := -1
var vanilla_presses: Array = []
var committed: Array = []

func _init() -> void:
	var container := Control.new()
	container.name = "MutationContainer"
	container.visible = false
	add_child(container)
	for i in 4:
		var button := TextureButton.new()
		button.name = "Mutation%s" % "ACGT"[i]
		container.add_child(button)
		button.pressed.connect(_on_mutation_pressed.bind(i))
		mutation_buttons.append(button)
	var tooltip: Control = load("res://tests/stubs/tooltip.gd").new()
	tooltip.name = "MutationTooltip"
	tooltip.visible = false
	add_child(tooltip)
	tooltip.owner = self
	tooltip.unique_name_in_owner = true

func draft(names: Array) -> void:
	_mutation_gen += 1
	mutations = names.map(func(n):
		var m := Resource.new()
		m.resource_name = n
		return m)
	$MutationContainer.visible = true

func _on_mutation_pressed(index: int) -> void:
	vanilla_presses.append(index)

func _revert_pending_selection() -> void:
	pending_mutation_index = -1

func _on_confirm_pressed() -> void:
	committed.append(mutations[pending_mutation_index])
	pending_mutation_index = -1
	$MutationContainer.visible = false
	await get_tree().process_frame
