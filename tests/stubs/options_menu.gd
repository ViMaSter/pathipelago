extends VBoxContainer

var current_tab := 0
var tab_buttons: Array[Button] = []
var tab_content := PanelContainer.new()

func _init() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	add_child(tab_content)
	for title in ["button_game", "button_remap"]:
		var button := Button.new()
		button.text = title
		row.add_child(button)
		tab_buttons.append(button)
		var page := VBoxContainer.new()
		page.name = title
		tab_content.add_child(page)

func _on_tab_changed(tab_index: int) -> void:
	current_tab = tab_index
	for i in tab_content.get_child_count():
		tab_content.get_child(i).visible = i == tab_index
