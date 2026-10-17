extends Node

enum RoomType {
	Normal = 0,
	Boss = 1,
	Item = 2,
}

enum EditorState {
	ANIMATING_IN,
	ANIMATING_OUT,
	ACTIVE,
	HIDDEN,
}

var player: Node
var main: Node
var rng_seed := "SEEDAAAA"
var editor: Node
