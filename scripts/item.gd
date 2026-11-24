# 井里的一个物件（只负责画）。位置由服务端的状态决定。
extends Node2D

const Cfg = preload("res://scripts/cfg.gd")
const RIM_SHADER := preload("res://shaders/sprite.gdshader")
const SWEEP_SHADER := preload("res://shaders/gold_sweep.gdshader")
const BEETLE_FRAMES := [preload("res://art/beetle.tres"), preload("res://art/beetle_2.tres")]
const RIM_REACH := 3.0  # 从轮廓向内采样的最大距离，单位为游戏像素。
const SWEEP_DURATION := 0.4
const SPARK_DURATION := 0.45
# 光晕半径用碰撞半径的倍数，颜色的透明度是呼吸的中心强度。
const HALOS := {
	"gem": {"radius": 1.35, "color": Color(0.32, 0.85, 1.0, 0.32)},
	"rub": {"radius": 1.30, "color": Color(1.0, 0.34, 0.46, 0.30)},
	"bug": {"radius": 1.20, "color": Color(0.80, 0.48, 1.0, 0.29)},
}
static var _spark_masks := {}

var kind := "gs"                 # 类型代号，见 shared/balance.json 的 TYPES
var uid := 0                     # 物件 id，决定固定的形状和倾斜角度
var walk_dx := 0.0               # 晶甲虫在相邻两帧服务端状态中的横向位移
var _radius := 0.0
var _light_dir := Vector2.DOWN
var _spark_anchor := Vector2.ZERO
var _t := 0.0
var _detail := false
var _dark := 0.0
var _glow_strength := 0.0
var _phase := 0.0
var _spark_at := 0.0
var _walk_t := 0.0
var _walk_frame := 0
var _rim_mat: ShaderMaterial
var _sweep_mat: ShaderMaterial
var _sweep_cycle := 0.0
var _sweep_offset := 0.0
var _sweep := Vector3.ZERO
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
	_rim_mat = ShaderMaterial.new()
	_rim_mat.shader = RIM_SHADER
	# 照原型的画法：整张图画成边长 = 碰撞半径 × 2.5 的正方形
	_radius = float(Cfg.b().TYPES[Cfg.type_index(kind)].r) * Cfg.S
	var d := _radius * 2.5
	var sc: float = d / float(sprite.texture.get_width())
	sprite.scale = Vector2(sc, sc)
	glow.scale = sprite.scale
	_rim_mat.set_shader_parameter("rim_px", RIM_REACH / sc)
	# 金块、石头、化石各自带一个固定的倾斜角度，看着不那么整齐划一
	if kind in Cfg.TILT:
		var h := fmod(absf(sin(uid * 12.9898) * 43758.5453), 1.0)
		sprite.rotation = (h - 0.5) * 0.9
		glow.rotation = sprite.rotation
	_phase = fposmod(float(uid) * 0.61803398875, 1.0)
	if gold:
		_sweep_mat = ShaderMaterial.new()
		_sweep_mat.shader = SWEEP_SHADER
		glow.material = _sweep_mat
		_sweep_cycle = lerpf(3.1, 5.3, fposmod(float(uid) * 0.41421356237, 1.0))
		_sweep_offset = _phase * _sweep_cycle
	if HALOS.has(kind):
		var conf: Dictionary = HALOS[kind]
		_halo_color = conf.color
		halo.scale = Vector2.ONE * (2.0 * _radius * float(conf.radius) / float(halo.texture.get_width()))
	# 沿物件轮廓压一小片软影。
	shadow.scale = (Vector2(2.5, 2.2) * _radius + Vector2(4.0, 3.0)) / shadow.texture.get_size()
	if kind in Cfg.SPARKLE:
		_spark_at = randf_range(0.35, 2.1)


func set_lighting(light_dir: Vector2, light_col: Color, under_col: Color) -> void:
	_light_dir = light_dir
	shadow.position = light_dir * clampf(_radius * 0.25, 1.4, 3.2)
	spark.modulate = light_col
	_rim_mat.set_shader_parameter("light_col", light_col)
	_rim_mat.set_shader_parameter("under_col", under_col)
	if _sweep_mat != null:
		_sweep_mat.set_shader_parameter("light_col", light_col)
	_update_light_axes()


func _update_light_axes() -> void:
	# 抵消贴图的倾斜和翻转，让井内的方向不随物件姿势变。
	var axis := _light_dir.rotated(-sprite.rotation)
	var under := Vector2.UP.rotated(-sprite.rotation)
	if sprite.flip_h:
		axis.x = -axis.x
		under.x = -under.x
	_rim_mat.set_shader_parameter("light_axis", axis)
	_rim_mat.set_shader_parameter("under_axis", under)
	if _sweep_mat != null:
		_sweep_mat.set_shader_parameter("sweep_axis", axis / (absf(axis.x) + absf(axis.y)))
	if kind in Cfg.SPARKLE:
		_spark_anchor = -_light_dir * (_find_spark_edge(axis) * sprite.scale.x)
		spark.position = sprite.position + _spark_anchor


func _find_spark_edge(axis: Vector2) -> float:
	# 从受光侧往中心找第一个可见像素，形状带缺口时也能贴上沿。
	var diffuse: Texture2D = sprite.texture.diffuse_texture
	var path := diffuse.resource_path
	if not _spark_masks.has(path):
		var mask: BitMap
		var image := diffuse.get_image()
		if image != null and not image.is_empty():
			mask = BitMap.new()
			mask.create_from_image_alpha(image, 0.5)
		_spark_masks[path] = mask
	var mask: BitMap = _spark_masks[path]
	var size := diffuse.get_size()
	if mask != null:
		var center := (size - Vector2.ONE) * 0.5
		var extent := int(minf(center.x / maxf(absf(axis.x), 0.001), center.y / maxf(absf(axis.y), 0.001)))
		for distance in range(extent, 0, -1):
			var pixel := Vector2i((center - axis * float(distance)).round())
			if mask.get_bitv(pixel):
				return float(distance)
	return size.x * 0.18


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
	var was_flipped := sprite.flip_h
	if absf(walk_dx) > 0.02:
		_walk_t += dt
		sprite.flip_h = walk_dx < 0.0
		glow.flip_h = sprite.flip_h
	else:
		_walk_t = 0.0
	var frame := int(_walk_t / 0.11) % BEETLE_FRAMES.size()
	var frame_changed := frame != _walk_frame
	if frame_changed:
		_walk_frame = frame
		sprite.texture = BEETLE_FRAMES[frame]
		glow.texture = sprite.texture
	sprite.position.y = sin(_walk_t * 16.0) * 0.75
	glow.position.y = sprite.position.y
	halo.position.y = sprite.position.y
	if frame_changed or sprite.flip_h != was_flipped:
		_update_light_axes()
	spark.position = sprite.position + _spark_anchor


func _update_glow() -> void:
	var sweep := Vector3.ZERO
	if _detail and _sweep_mat != null:
		var elapsed := fposmod(_t + _sweep_offset, _sweep_cycle)
		if elapsed < SWEEP_DURATION:
			sweep = Vector3(
				lerpf(-0.095, 1.095, elapsed / SWEEP_DURATION),
				lerpf(0.10, 0.46, _dark),
				lerpf(0.55, 1.0, _dark)
			)
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


# detail 控制附加光影。黑灯里的基础自发光在各档都保留。
func set_look(detail: bool, dark: float, glow_strength: float, rim_strength: float) -> void:
	_detail = detail
	_dark = dark
	_glow_strength = glow_strength
	shadow.visible = detail and dark < 1.0
	shadow.modulate.a = 0.64 * (1.0 - dark)
	halo.visible = detail and _halo_color.a > 0.0
	halo.modulate = _halo_color
	if not detail:
		spark.hide()
	_update_glow()
	sprite.material = _rim_mat if detail and dark < 1.0 else null
	_rim_mat.set_shader_parameter("rim_strength", rim_strength)
	_rim_mat.set_shader_parameter("light_fade", 1.0 - dark)
