# 井里的一个物件（只负责画）。位置由服务端的状态决定。
extends Node2D

const Cfg = preload("res://scripts/cfg.gd")
const SPRITE_SHADER := preload("res://shaders/sprite.gdshader")
const SWEEP_SHADER := preload("res://shaders/gold_sweep.gdshader")
const BEETLE_FRAMES := [preload("res://art/beetle.tres"), preload("res://art/beetle_2.tres")]
const SWEEP_DURATION := 0.4
const SPARK_DURATION := 0.45
# 光晕半径用碰撞半径的倍数，颜色的透明度是呼吸的中心强度。
const HALOS := {
	"gem": {"radius": 1.35, "color": Color(0.32, 0.85, 1.0, 0.32)},
	"rub": {"radius": 1.30, "color": Color(1.0, 0.34, 0.46, 0.30)},
	"bug": {"radius": 1.20, "color": Color(0.80, 0.48, 1.0, 0.29)},
}

var kind := "gs"                 # 类型代号，见 shared/balance.json 的 TYPES
var uid := 0                     # 物件 id，决定固定的形状和倾斜角度
var walk_dx := 0.0               # 晶甲虫在相邻两帧服务端状态中的横向位移
var _t := 0.0
var _detail := false
var _dark := 0.0
var _glow_strength := 0.0
var _phase := 0.0
var _spark_at := 0.0
var _walk_t := 0.0
var _walk_frame := 0
var _mat: ShaderMaterial
var _sweep_mat: ShaderMaterial
var _sweep_cycle := 0.0
var _sweep_offset := 0.0
var _sweep := Vector2.ZERO
var _halo_color := Color.TRANSPARENT

@onready var sprite: Sprite2D = $Sprite
@onready var glow: Sprite2D = $Glow
@onready var shadow: Sprite2D = $Shadow
@onready var halo: Sprite2D = $Halo
@onready var spark: Sprite2D = $Spark


func _ready() -> void:
	var art: String = Cfg.ART.get(kind, "gold_s")
	var gold := kind in Cfg.GOLD
	if gold:
		var shape := posmod(uid, 4)
		if shape != 0:
			art += "_%d" % shape
	sprite.texture = load("res://art/%s.tres" % art)
	glow.texture = sprite.texture
	_mat = ShaderMaterial.new()
	_mat.shader = SPRITE_SHADER
	sprite.material = _mat
	# 照原型的画法：整张图画成边长 = 碰撞半径 × 2.5 的正方形
	var r: float = float(Cfg.b().TYPES[Cfg.type_index(kind)].r)
	var d: float = r * 2.5 * Cfg.S
	var sc: float = d / float(sprite.texture.get_width())
	sprite.scale = Vector2(sc, sc)
	glow.scale = sprite.scale
	# 金块、石头、化石各自带一个固定的倾斜角度，看着不那么整齐划一
	if kind in Cfg.TILT:
		var h := fmod(absf(sin(uid * 12.9898) * 43758.5453), 1.0)
		sprite.rotation = (h - 0.5) * 0.9
		glow.rotation = sprite.rotation
	_phase = fposmod(float(uid) * 0.61803398875, 1.0)
	if gold:
		_sweep_mat = ShaderMaterial.new()
		_sweep_mat.shader = SWEEP_SHADER
		# 抵消贴图的倾斜角，高光在井里始终朝右下扫。
		var axis := Vector2.ONE.rotated(-sprite.rotation)
		_sweep_mat.set_shader_parameter("sweep_axis", axis / (absf(axis.x) + absf(axis.y)))
		glow.material = _sweep_mat
		_sweep_cycle = lerpf(3.1, 5.3, fposmod(float(uid) * 0.41421356237, 1.0))
		_sweep_offset = _phase * _sweep_cycle
	if HALOS.has(kind):
		var conf: Dictionary = HALOS[kind]
		_halo_color = conf.color
		halo.scale = Vector2.ONE * (2.0 * r * Cfg.S * float(conf.radius) / float(halo.texture.get_width()))
	# 一圈暗影：让东西看着是嵌在岩壁里的，而不是贴在上面
	shadow.scale = Vector2.ONE * (r * 2.6 * Cfg.S + 10.0) / 64.0
	shadow.position = Vector2(0.5, 1.5)
	shadow.modulate.a = 0.85
	spark.position = Vector2(-r * 0.3 * Cfg.S, -r * 0.35 * Cfg.S)
	if kind in Cfg.SPARKLE:
		_spark_at = randf_range(0.35, 2.1)


func _process(dt: float) -> void:
	_t += dt
	if _detail and kind in Cfg.SPARKLE:
		_update_spark()
	if kind == "bug":
		_update_walk(dt)
	_update_glow()


func _update_spark() -> void:
	var s := 0.0
	if _t > _spark_at:
		var u := (_t - _spark_at) / SPARK_DURATION
		if u >= 1.0:
			_spark_at = _t + randf_range(1.0, 2.8)
		else:
			s = sin(u * PI)
	spark.visible = s > 0.0
	if spark.visible:
		spark.modulate.a = minf(1.0, 1.12 * s)
		spark.scale = Vector2.ONE * (0.05 + 0.1 * s)


func _update_walk(dt: float) -> void:
	# 位移来自相邻快照，插值走完等下一帧时也能继续迈步。被钩起或停下时恢复首帧。
	if absf(walk_dx) > 0.02:
		_walk_t += dt
		sprite.flip_h = walk_dx < 0.0
		glow.flip_h = sprite.flip_h
	else:
		_walk_t = 0.0
	var frame := int(_walk_t / 0.11) % BEETLE_FRAMES.size()
	if frame != _walk_frame:
		_walk_frame = frame
		sprite.texture = BEETLE_FRAMES[frame]
		glow.texture = sprite.texture
	sprite.position.y = sin(_walk_t * 16.0) * 0.75
	glow.position.y = sprite.position.y
	halo.position.y = sprite.position.y


func _update_glow() -> void:
	var sweep := Vector2.ZERO
	if _detail and _sweep_mat != null:
		var elapsed := fposmod(_t + _sweep_offset, _sweep_cycle)
		if elapsed < SWEEP_DURATION:
			sweep = Vector2(lerpf(-0.095, 1.095, elapsed / SWEEP_DURATION), lerpf(0.24, 0.46, _dark))
	if sweep != _sweep:
		_sweep = sweep
		_sweep_mat.set_shader_parameter("sweep", sweep)
	var strength := _glow_strength
	if halo.visible:
		var pulse := 1.0 + 0.12 * sin(_t * 2.3 + _phase * TAU)
		strength *= pulse
		halo.modulate.a = _halo_color.a * pulse * lerpf(1.0, 0.55, _dark)
	glow.visible = strength > 0.0 or sweep.y > 0.0
	if glow.visible:
		glow.modulate = Color(strength, strength, strength)


# detail 控制扫光、光晕和十字闪光。黑灯里的基础自发光在各档都保留。
func set_look(fx: bool, detail: bool, dark: float, glow_strength: float, rim: Color) -> void:
	_detail = detail
	_dark = dark
	_glow_strength = glow_strength
	shadow.visible = fx
	halo.visible = detail and _halo_color.a > 0.0
	halo.modulate = _halo_color
	if not detail:
		spark.hide()
	_update_glow()
	_mat.set_shader_parameter("rim", rim)
	# 描边宽度按游戏像素设定，换成贴图像素要除以这张图的缩放。
	_mat.set_shader_parameter("rim_px", 0.9 / maxf(0.001, sprite.scale.x))
