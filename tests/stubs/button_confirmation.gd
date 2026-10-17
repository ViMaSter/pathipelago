extends Button

# Mirrors the game's ButtonConfirmation pressed wrapper.
signal confirming_started

var orig_text := ""
var confirming := false
var should_confirm: Callable

func _ready() -> void:
	orig_text = text
	pressed.connect(func(): get_parent().clicks += 1)
	var connections = pressed.get_connections()
	for c in connections:
		pressed.disconnect(c["callable"])
	pressed.connect(func():
		var needs_confirm = not should_confirm.is_valid() or should_confirm.call()
		if confirming or not needs_confirm:
			for c in connections:
				c["callable"].call()
			reset()
		else:
			confirm()
	)
	focus_exited.connect(reset)
	mouse_exited.connect(reset)

func confirm() -> void:
	confirming = true
	text = "Really " + orig_text
	confirming_started.emit()

func reset() -> void:
	if not confirming:
		return
	text = orig_text
	confirming = false
