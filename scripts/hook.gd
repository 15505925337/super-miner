# 一个玩家的钩子（只负责画）：绳子、钩爪、钩灯。角度和绳长由服务端的状态决定。
extends Node2D

var _tex_open: Texture2D = preload("res://art/claw_open.tres")
var _tex_closed: Texture2D = preload("res://art/claw_closed.tres")

@onready var rope: Line2D = $Rope
@onready var rope_edge: Line2D = $RopeEdge
@onready var claw: Node2D = $Claw
@onready var claw_sprite: Sprite2D = $Claw/Sprite
@onready var halo: Sprite2D = $Claw/Halo
@onready var light: PointLight2D = $Claw/Light


# ang：偏离正下方的角度（弧度）；length：转轴到爪尖的长度（游戏像素）
func apply(ang: float, length: float, closed: bool, frozen: bool, strong: bool) -> void:
	var p := Vector2(sin(ang), cos(ang)) * length
	claw.position = p
	claw.rotation = -ang
	var pts := PackedVector2Array([Vector2.ZERO, p])
	rope.points = pts
	rope_edge.points = pts
	claw_sprite.texture = _tex_closed if closed else _tex_open
	rope.default_color = Color(0.77, 0.94, 1.0) if frozen else (Color(1.0, 0.64, 0.24) if strong else Color(0.89, 0.74, 0.52))
	claw_sprite.modulate = Color(0.6, 0.88, 1.0) if frozen else Color(1, 1, 1)


# 黑灯的时候钩灯是主要的光：更亮、照得更远（d 从 0 到 1）
func set_dark(d: float) -> void:
	light.energy = 0.8 + 1.1 * d
	light.texture_scale = 1.25 + 1.0 * d


func set_fx(on: bool, lit: bool) -> void:
	light.enabled = on and lit
	halo.visible = on
