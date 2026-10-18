extends Node

var applied: Array = []

func apply_saved(entries: Array) -> void:
	applied = entries.duplicate()
