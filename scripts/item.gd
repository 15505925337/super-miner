# 井里的一个物件（只负责画）。位置由服务端的状态决定。
extends Node2D

const Cfg = preload("res://scripts/cfg.gd")
const SPRITE_SHADER := preload("res://shaders/sprite.gdshader")

var kind := "gs"                 # 类型代号，见 shared/balance.json 的 TYPES
var uid := 0                     # 物件 id，用来定每个物件固定的倾斜角度
var _sparkle := false
var _t := 0.0
var _spark_at := 0.0
var _last_x := 0.0
var _mat: ShaderMaterial

@onready var sprite: Sprite2D = $Sprite
@onready var glow: Sprite2D = $Glow
@onready var shadow: Sprite2D = $Shadow
@onready var spark: Sprite2D = $Spark
@onready var light: PointLight2D = $Light


func _ready() -> void:
	var art: String = Cfg.ART.get(kind, "gold_s")
	sprite.texture = load("res://art/%s.tres" % art)
	glow.texture = load("res://art/%s.png" % art)
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
	# 一圈暗影：让东西看着是嵌在岩壁里的，而不是贴在上面
	shadow.scale = Vector2.ONE * (r * 2.6 * Cfg.S + 10.0) / 64.0
	shadow.position = Vector2(0.5, 1.5)
	shadow.modulate.a = 0.85
	_sparkle = kind in Cfg.SPARKLE
	spark.visible = _sparkle
	spark.position = Vector2(-r * 0.3 * Cfg.S, -r * 0.35 * Cfg.S)
	light.visible = kind == "gem" or kind == "rub"       # 晶石和红宝石自己发一点光
	if kind == "rub":
		light.color = Color(1.0, 0.35, 0.45)
	_spark_at = randf_range(0.5, 3.0)
	_last_x = position.x


func _process(dt: float) -> void:
	_t += dt
	var s := 0.0
	if _sparkle and _t > _spark_at:          # 闪光：隔几秒亮一下
		var u := (_t - _spark_at) / 0.45
		if u >= 1.0:
			_spark_at = _t + randf_range(1.6, 4.2)
		else:
			s = sin(u * PI)
	spark.modulate.a = s
	spark.scale = Vector2.ONE * (0.05 + 0.1 * s)
	if kind == "bug":                        # 晶甲虫：朝着跑的方向，一颠一颠
		if absf(position.x - _last_x) > 0.02:
			sprite.flip_h = position.x < _last_x
		_last_x = position.x
		sprite.position.y = sin(_t * 16.0 + uid) * 0.75
	if light.visible:
		light.energy = 0.7 + 0.12 * sin(_t * 2.3)


# glow：自发光强度（只有底图暗的层才需要）；rim：描边光（底图和物件颜色接近时用）
func set_look(fx: bool, lit: bool, glow_amount: float, rim: Color) -> void:
	var g: float = Cfg.GLOW.get(kind, 0.1) * glow_amount
	glow.visible = fx and g > 0.01
	glow.modulate = Color(g, g, g, 1.0)
	shadow.visible = fx
	spark.visible = fx and _sparkle
	light.enabled = fx and lit
	_mat.set_shader_parameter("rim", rim)
	# 描边的粗细按屏幕上看到的算（大约 1.3 个游戏像素），换成贴图像素要除以这张图的缩放
	_mat.set_shader_parameter("rim_px", 0.9 / maxf(0.001, sprite.scale.x))
