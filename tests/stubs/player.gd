extends Node

var money := 50
var shop_discount := 0.0
var dna := 0
var dead := false
var hp := 6
var armor := 0
var invulnerability := 0.0
var player_damage_mult := 1
var damage_blocked := false
var center_body := Node2D.new()
var damage_calls: Array = []
var refuse_damage := false

func add_money(amount: int) -> void:
	money += amount

func add_dna(amount: int) -> void:
	dna += amount

func _init() -> void:
	add_child(center_body)

func hit_no_signal(damage: float, position: Vector2, _attack: Variant = null) -> void:
	damage_calls.append([damage, position])
	var editor: Node = get_node("/root/G").editor
	if refuse_damage or dead or invulnerability > 0 or (is_instance_valid(editor) and editor.active):
		return
	if damage_blocked:
		damage_blocked = false
		return
	if armor > 0:
		armor = maxi(0, armor - int(damage * player_damage_mult))
		return
	hp = maxi(0, hp - int(damage * player_damage_mult))
	if hp == 0:
		dead = true
		get_node("/root/SignalBus").emit_signal("player_died")
