# 一个玩家的钩子（只负责画）：绳子和钩爪。角度和绳长由服务端的状态决定。
extends Node2D

const Cfg = preload("res://scripts/cfg.gd")
const CLAW_TEXTURES := {
	"1": [preload("res://art/claw_1_open.tres"), preload("res://art/claw_1_closed.tres")],
	"2": [preload("res://art/claw_2_open.tres"), preload("res://art/claw_2_closed.tres")],
	"3": [preload("res://art/claw_3_open.tres"), preload("res://art/claw_3_closed.tres")],
	"4": [preload("res://art/claw_4_open.tres"), preload("res://art/claw_4_closed.tres")],
	"5": [preload("res://art/claw_5_open.tres"), preload("res://art/claw_5_closed.tres")],
}
const MAT_UNSHADED := preload("res://res/mat_unshaded.tres")
const DRAW_SIZE := Vector2.ONE * 60.0 * Cfg.S
# 用相对画布的位置保留旧版几何。45 格图上绳环约在 (22.5, 9.84)，爪口约在 (22.5, 37.27)。
const RING_UV := Vector2(0.5, 56.0 / 256.0)
const MOUTH_UV := Vector2(0.5, 212.0 / 256.0)
const RING_FROM_MOUTH := (RING_UV - MOUTH_UV) * DRAW_SIZE

var _textures: Array

@onready var rope: Line2D = $Rope
@onready var rope_edge: Line2D = $RopeEdge
@onready var rope_color := rope.default_color
@onready var claw: Node2D = $Claw
@onready var claw_sprite: Sprite2D = $Claw/Sprite


func _ready() -> void:
	_textures = CLAW_TEXTURES.get(Cfg.args().get("claw", "1"), CLAW_TEXTURES["1"])
	claw_sprite.texture = _textures[0]
	var size := claw_sprite.texture.get_size()
	claw_sprite.scale = DRAW_SIZE / size
	claw_sprite.offset = (Vector2.ONE * 0.5 - MOUTH_UV) * size
	if Cfg.args().get("hookdbg", "0") != "1":
		return
	var circle := Line2D.new()
	var radius := float(Cfg.b().HOOK_R) * Cfg.S
	for i in 48:
		circle.add_point(Vector2.from_angle(TAU * i / 48.0) * radius)
	circle.closed = true
	circle.width = 0.75
	circle.default_color = Color(0.32, 1.0, 0.76)
	circle.antialiased = true
	circle.material = MAT_UNSHADED
	circle.z_index = 66
	claw.add_child(circle)


# ang：偏离正下方的角度（弧度）；length：转轴到判定圆圆心的长度（游戏像素）
# rope_start：绳卷出绳点相对于转轴的位置
func apply(ang: float, length: float, closed: bool, frozen: bool, strong: bool, rope_start: Vector2) -> void:
	var p := Vector2(sin(ang), cos(ang)) * length
	claw.position = p
	claw.rotation = -ang
	var ring := p + RING_FROM_MOUTH.rotated(claw.rotation)
	var pts := PackedVector2Array([rope_start, Vector2.ZERO, ring])
	rope.points = pts
	rope_edge.points = pts
	claw_sprite.texture = _textures[1 if closed else 0]
	rope.default_color = Color(0.77, 0.94, 1.0) if frozen else (Color(1.0, 0.64, 0.24) if strong else rope_color)
	claw_sprite.modulate = Color(0.6, 0.88, 1.0) if frozen else Color(1, 1, 1)


# 黑灯时只留绳子和钩爪本身的颜色，保留瞄准所需的轮廓。
func set_dark(d: float) -> void:
	var brightness := lerpf(1.0, 0.34, d)
	modulate = Color(brightness, brightness, brightness)
