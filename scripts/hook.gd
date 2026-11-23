# 一个玩家的钩子（只负责画）：绳子和钩爪。角度和绳长由服务端的状态决定。
extends Node2D

const Cfg = preload("res://scripts/cfg.gd")
const TEX_OPEN := preload("res://art/claw_1_open.tres")
const TEX_CLOSED := preload("res://art/claw_1_closed.tres")
const MAT_UNSHADED := preload("res://res/mat_unshaded.tres")
const RING_FROM_MOUTH := Vector2(0, -156)     # 原图绳环 (128, 56)，爪口判定点 (128, 212)

@onready var rope: Line2D = $Rope
@onready var rope_edge: Line2D = $RopeEdge
@onready var rope_color := rope.default_color
@onready var claw: Node2D = $Claw
@onready var claw_sprite: Sprite2D = $Claw/Sprite


func _ready() -> void:
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
	var ring := p + (RING_FROM_MOUTH * claw_sprite.scale).rotated(claw.rotation)
	var pts := PackedVector2Array([rope_start, Vector2.ZERO, ring])
	rope.points = pts
	rope_edge.points = pts
	claw_sprite.texture = TEX_CLOSED if closed else TEX_OPEN
	rope.default_color = Color(0.77, 0.94, 1.0) if frozen else (Color(1.0, 0.64, 0.24) if strong else rope_color)
	claw_sprite.modulate = Color(0.6, 0.88, 1.0) if frozen else Color(1, 1, 1)


# 黑灯时只留绳子和钩爪本身的颜色，保留瞄准所需的轮廓。
func set_dark(d: float) -> void:
	var brightness := lerpf(1.0, 0.34, d)
	modulate = Color(brightness, brightness, brightness)
