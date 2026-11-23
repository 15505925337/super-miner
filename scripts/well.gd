# 一口井（只负责画）：底图、点缀的灯光、矿工、钩子、矿物、飘字。
# 画什么全听 set_view() 传进来的内容，那是客户端按服务端状态插值算出来的。
# 合作、同屏对战只有一口井，铺满屏幕；分屏对战每人一口，各画在自己的小窗里。
# 名字、钱、关数这些字不画在这里，由界面层按屏幕分辨率画（缩放后字才清楚）。
extends Node2D

const Cfg = preload("res://scripts/cfg.gd")
const ITEM := preload("res://scenes/item.tscn")
const HOOK := preload("res://scenes/hook.tscn")
const LIGHT_TEX := preload("res://res/light_radial.tres")
const HALO := preload("res://res/halo.tres")
const MAT_ADD := preload("res://res/mat_add.tres")
const MAT_UNSHADED := preload("res://res/mat_unshaded.tres")
const ICE := preload("res://art/ice.png")
const CHEST_OPEN := preload("res://art/chest_open.png")
const SHAFT := preload("res://shaders/shaft.gdshader")
const BG_SHADER := preload("res://shaders/bg.gdshader")
const LAVA_CRACKS := preload("res://art/relief_3_e.png")
const LAVA_CRACK_STRENGTH := 0.60
const DARK_AMBIENT := Color(0.06, 0.06, 0.09)
const MINER_SIZE := 64.0
const DARK_MINER_BRIGHTNESS := 0.40
const MINER_SOURCE_SIZE := 512.0
const WINCH_ROPE_EXIT := Vector2(256, 432)    # 四个矿工的各帧共用同一处绳卷出绳点
const MINER_POSES := [
	"idle", "idle2", "crank1", "crank2", "crank3", "crank4",
	"pull", "pull2", "happy", "happy2", "sad", "hit", "throw",
]
const FX_SEQUENCES := {
	"boom": {"count": 6, "duration": 0.5, "coverage": 416.0 / 512.0, "alpha": 0.84},
	"spark": {"count": 4, "duration": 0.3, "coverage": 336.0 / 512.0, "alpha": 0.95},
	"dust": {"count": 4, "duration": 0.4, "coverage": 432.0 / 512.0, "alpha": 0.72},
}
static var _fx_frames := {}

# 以原画为主。井壁、远景和支架共用同一层的调色，环境光只在黑灯事件里压暗。
#   grade [伽马, 对比度, 饱和度]；grade_tint 各色通道倍率；bag_chest_glow 宝袋和宝箱的黑灯倍率；bloom 泛光强度
#   lights [灯芯位置, 颜色, 光柱（0 没有，1 朝下，2 斜着）]
#   rim    哪些矿物在这一层和底图颜色太接近，要加描边光；dust 飘尘的颜色
const TIERS := [
	{   # 浅土层：保留原画里的土黄色和斜阳
		"bg": "bg_1", "grade": Vector3.ONE, "bag_chest_glow": 1.4, "bloom": 0.06,
		"ledge": 225.0,
		"lights": [[Vector2(24, 15), Color(1, 0.9, 0.68), 2]],
		"rim": {"fos": Color(0.3, 0.17, 0.09, 0.7)}, "dust": Color(1, 0.95, 0.8),
	},
	{   # 岩石层：两盏矿灯打下暖光，井壁是冷色的碎裂岩块
		"bg": "bg_2", "grade": Vector3.ONE, "bag_chest_glow": 1.85, "bloom": 0.06,
		"ledge": 233.0,
		"lights": [
			[Vector2(81, 51), Color(1, 0.7, 0.38), 1],
			[Vector2(403, 51), Color(1, 0.7, 0.38), 1],
		],
		"rim": {"fos": Color(1, 0.92, 0.75, 0.5), "rs": Color(0.75, 0.82, 0.95, 0.4), "rl": Color(0.75, 0.82, 0.95, 0.4)}, "dust": Color(1, 0.92, 0.78),
	},
	{   # 晶洞层：提亮蓝紫色岩壁，支架蓝灯只留小光晕
		"bg": "bg_3", "grade": Vector3(1.18, 1.02, 1.04), "bag_chest_glow": 2.15, "bloom": 0.04,
		"ledge": 228.0,
		"lights": [
			[Vector2(135, 20), Color(0.56, 0.8, 1), 0],
			[Vector2(322, 20), Color(0.56, 0.8, 1), 0],
			[Vector2(520, 20), Color(0.56, 0.8, 1), 0],
		],
		"rim": {"gem": Color(0.9, 1, 1, 0.75), "bug": Color(1, 0.92, 1, 0.8), "rub": Color(1, 0.9, 0.92, 0.6), "rs": Color(0.75, 0.82, 1, 0.4), "rl": Color(0.75, 0.82, 1, 0.4)}, "dust": Color(0.6, 0.95, 1),
	},
	{   # 熔岩层：井架挂灯，井壁保留原有的岩浆裂缝自发光
		"bg": "bg_4", "grade": Vector3(1.34, 1.12, 1.40), "grade_tint": Vector3(1.08, 1.05, 0.60),
		"bag_chest_glow": 2.9, "bloom": 0.06,
		"ledge": 216.0,
		"lights": [[Vector2(151, 37), Color(1, 0.68, 0.36), 1]],
		"rim": {"rs": Color(0.85, 0.8, 0.85, 0.4), "rl": Color(0.85, 0.8, 0.85, 0.4), "tnt": Color(1.0, 0.76, 0.47, 0.28)},
		"dust": Color(1, 0.55, 0.2),
	},
]

var quality: int = Cfg.Q.HIGH
var fx_on := true
var light_test_args := {}         # 只由主场景从网页网址传入
var bloom := 0.06                # 当前层要的泛光强度，主场景来读
var _k := 1.0
var _items := {}                 # 物件 id → 节点
var _miners := {}                # 玩家 id → { root, sprite, hook, frames, ice }
var _extra: Array[PointLight2D] = []
var _test_light: Light2D
var _move_test_light := false
var _t := 0.0
var _tier := -1
var _base := Vector2.ZERO         # 这口井在画面上的位置（震动是在它上面加一点偏移）
var _shake := 0.0                 # 震动的幅度（游戏像素），自己衰减
var _dark := 0.0                  # 黑灯的程度，0 正常，1 最暗
var _dark_want := 0.0
var _dark_done := 0.0
var _live_t := -1.0               # 这一关是从什么时候开始挖的（中途冒出来的东西要有个"掉下来"的动作）
var _show_lava_cracks := String(Cfg.args().get("lava_cracks", "1")) != "0"

@onready var ambient: CanvasModulate = $Ambient
@onready var far: Sprite2D = $Far
@onready var bg: Sprite2D = $Bg
@onready var frame_layer: Sprite2D = $Frame
@onready var foreground: Sprite2D = $Foreground
@onready var lights_root: Node2D = $Lights
@onready var items_root: Node2D = $Items
@onready var miners_root: Node2D = $Miners
@onready var fx_root: Node2D = $Fx
@onready var dust: CPUParticles2D = $Dust
@onready var emis: Sprite2D = $Emis
@onready var embers: CPUParticles2D = $Embers


func _ready() -> void:
	# 同一口井的背景共用调色。分屏时每口井各用一份材质。
	var bm := ShaderMaterial.new()
	bm.shader = BG_SHADER
	bg.material = bm
	far.material = bm
	frame_layer.material = bm
	emis.texture = LAVA_CRACKS
	_setup_light_test()
	set_draw_area(Rect2(0, 0, Cfg.GW, Cfg.GH))
	_set_tier(1)
	apply(quality, fx_on)


func _lit() -> bool:
	return fx_on and quality != Cfg.Q.LOW


func _setup_light_test() -> void:
	match light_test_args.get("lt", ""):
		"dir":
			var directional := DirectionalLight2D.new()
			# 正角度从朝下顺时针转。默认向右下方照，稍抬高以显示法线的明暗变化。
			directional.rotation_degrees = fposmod(_light_test_number("ltd", -45.0), 360.0)
			directional.height = 0.35
			directional.energy = clampf(_light_test_number("lte", 0.2), 0.0, 1.0)
			_test_light = directional
			# 方向光忽略受光遮罩。底图由着色器排除，剪影和飘尘由无光照材质排除。
			foreground.material = MAT_UNSHADED
			dust.material = MAT_ADD
		"occ":
			var point := PointLight2D.new()
			point.texture = LIGHT_TEX
			point.texture_scale = 2.4
			point.position = Vector2(320.0, 190.0)
			point.height = 20.0
			point.energy = 0.8
			point.shadow_enabled = true
			point.range_z_min = bg.z_index
			point.range_z_max = 0
			_test_light = point
			_move_test_light = light_test_args.get("ltm", "0") == "1"
	if _test_light != null:
		add_child(_test_light)


func _light_test_number(key: String, fallback: float) -> float:
	var value := String(light_test_args.get(key, ""))
	if value.is_valid_float() and is_finite(value.to_float()):
		return value.to_float()
	return fallback


func _set_tier(tier: int) -> void:
	_tier = tier
	var t: Dictionary = TIERS[tier]
	bg.texture = load("res://art/%s.png" % t.bg)
	far.texture = load("res://art/%s_far.png" % t.bg)
	frame_layer.texture = load("res://art/%s_frame.png" % t.bg)
	foreground.texture = load("res://art/%s_fg.png" % t.bg)
	bloom = t.bloom
	bg.material.set_shader_parameter("grade", t.grade)
	bg.material.set_shader_parameter("grade_tint", t.get("grade_tint", Vector3.ONE))
	emis.visible = tier == 3 and _show_lava_cracks
	dust.color = Color(t.dust.r, t.dust.g, t.dust.b, 0.85)
	embers.emitting = tier == 3
	embers.visible = tier == 3 and fx_on
	for c in lights_root.get_children():
		lights_root.remove_child(c)
		c.queue_free()
	for l in t.lights:
		var node := Node2D.new()
		node.position = l[0]
		# 小光晕和光柱画在矿工后面。
		var halo := Sprite2D.new()
		halo.texture = HALO
		halo.material = MAT_ADD
		halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		halo.z_index = -5
		halo.scale = Vector2.ONE * 0.28
		halo.modulate = Color(l[1].r, l[1].g, l[1].b, 0.18)
		node.add_child(halo)
		var beam := int(l[2])
		if beam > 0:
			var shaft := ColorRect.new()
			var m := ShaderMaterial.new()
			m.shader = SHAFT
			m.set_shader_parameter("strength", 0.045)
			m.set_shader_parameter("tint", Color(l[1].r, l[1].g, l[1].b, 1.0))
			m.set_shader_parameter("seed", l[0].x * 0.01)
			m.set_shader_parameter("half_angle", 0.46 if beam == 1 else 0.3)
			shaft.material = m
			shaft.position = Vector2(-70, 2)
			shaft.size = Vector2(140, 140)
			shaft.pivot_offset = Vector2(70, 0)
			if beam == 2:
				shaft.rotation = 0.5 if l[0].x < 320.0 else -0.42
			shaft.z_index = -6
			shaft.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.add_child(shaft)
		lights_root.add_child(node)
	apply(quality, fx_on)


# items：[{id, t, x, y, by, walk_dx}]，坐标是服务端单位。players：[{id, c, x, ang, len, st, fz, sg, out, frame}]
# info：{live, tier}
func set_view(items: Array, players: Array, info: Dictionary) -> void:
	var tier := int(info.get("tier", 1))
	if tier != _tier:
		_set_tier(tier)
	var live: bool = info.get("live", false)
	var conf: Dictionary = TIERS[_tier]
	_dark_want = float(info.get("dark", 0.0)) if live else 0.0
	if not live:
		_live_t = -1.0
	elif _live_t < 0.0:
		_live_t = _t
	var seen := {}
	for it in items:
		var id := int(it.id)
		seen[id] = true
		var n: Node2D = _items.get(id)
		if n == null:
			n = ITEM.instantiate()
			n.kind = Cfg.type_key(it.t)
			n.uid = id
			n.cast_test_shadow = _test_light is PointLight2D
			items_root.add_child(n)
			_set_item_look(n)
			_items[id] = n
			if live and _live_t >= 0.0 and _t - _live_t > 0.6:     # 开挖以后才冒出来的（丢来的石头、金矿雨、塌方）：从小变大弹一下
				n.scale = Vector2.ONE * 0.15
				n.create_tween().tween_property(n, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				fx_flash(Vector2(it.x, it.y) * Cfg.S, 26.0, Color(0.8, 0.72, 0.6), 0.3)
		n.position = Vector2(it.x, it.y) * Cfg.S
		n.walk_dx = float(it.get("walk_dx", 0.0))
		n.modulate.a = 1.0 if live else 0.6
	for id in _items.keys():
		if not seen.has(id):
			_items[id].queue_free()
			_items.erase(id)

	seen = {}
	var y0: float = float(Cfg.b().Y0) * Cfg.S
	var ledge := float(conf.ledge) / 3.0
	var sprite_center := Vector2.ONE * (MINER_SOURCE_SIZE * 0.5)
	var source_scale := MINER_SIZE / MINER_SOURCE_SIZE
	for p in players:
		var id := int(p.id)
		seen[id] = true
		var m: Dictionary = _miners.get(id, {})
		if not m.is_empty() and int(m.c) != int(p.c):
			m.root.queue_free()
			m.hook.queue_free()
			m = {}
		if m.is_empty():
			m = _make_miner(int(p.c))
			_miners[id] = m
		var x: float = float(p.x) * Cfg.S
		var st := int(p.st)
		var hauling := st == 2 or st == 4
		var frame := String(p.get("frame", "idle"))
		m.sprite.texture = m.frames[frame]
		# 动作帧已画好身体起伏，整张图保持固定，让木台贴着台沿。
		m.root.position = Vector2(x, ledge - 31.8)
		m.ice.visible = int(p.fz) == 1
		var pivot := Vector2(x, y0)
		var winch: Vector2 = m.root.position + (WINCH_ROPE_EXIT - sprite_center) * source_scale
		m.hook.position = pivot
		m.hook.apply(float(p.ang), float(p.len) * Cfg.S, hauling, int(p.fz) == 1, int(p.sg) == 1, winch - pivot)
		var inactive: bool = int(p.get("out", 0)) == 1 or not bool(p.get("on", true))
		m.root.modulate.a = 0.4 if inactive else 1.0
		m.hook.visible = not inactive
	for id in _miners.keys():
		if not seen.has(id):
			_miners[id].root.queue_free()
			_miners[id].hook.queue_free()
			_miners.erase(id)


func _make_miner(c: int) -> Dictionary:
	var root := Node2D.new()
	miners_root.add_child(root)
	var base := "res://art/miner_%d" % (c % 4 + 1)
	var frames := {}
	for pose in MINER_POSES:
		frames[pose] = load(base + ("" if pose == "idle" else "_" + pose) + ".tres")
	var sprite := Sprite2D.new()
	sprite.texture = frames.idle
	sprite.material = null if _test_light is DirectionalLight2D and _test_light.enabled else MAT_UNSHADED
	sprite.scale = Vector2.ONE * MINER_SIZE / float(frames.idle.get_width())
	root.add_child(sprite)
	var ice := Sprite2D.new()
	ice.texture = ICE
	ice.material = MAT_UNSHADED
	ice.scale = Vector2.ONE * MINER_SIZE / float(ICE.get_width())
	ice.modulate.a = 0.48
	ice.z_index = 63
	ice.hide()
	root.add_child(ice)
	var hook: Node2D = HOOK.instantiate()
	miners_root.add_child(hook)
	var m := {"c": c, "root": root, "sprite": sprite, "hook": hook, "frames": frames, "ice": ice}
	_set_miner_dark(m, _dark)
	return m


func miner_pos(id: int) -> Vector2:
	var m: Dictionary = _miners.get(id, {})
	return m.root.position if not m.is_empty() else Vector2(320, 51)


# 井壁、远景与支架在窗口露出的范围内按同一坐标镜像。剪影贴着实际画面四边，避免在中央竖起两道剪影。
func set_draw_area(area: Rect2) -> void:
	var visible_area := area.merge(Rect2(0, 0, Cfg.GW, Cfg.GH)).grow(4.0)
	var cave := Rect2(visible_area.position.x, 80.0, visible_area.size.x, visible_area.end.y - 80.0)
	bg.position = cave.position
	bg.region_rect = Rect2(cave.position * 3.0, cave.size * 3.0)
	emis.position = cave.position
	emis.region_rect = Rect2(cave.position * 1.5, cave.size * 1.5)
	var passage := Rect2(visible_area.position.x, 0.0, visible_area.size.x, 80.0)
	far.position = passage.position
	far.region_rect = Rect2(passage.position * 3.0, passage.size * 3.0)
	frame_layer.position = far.position
	frame_layer.region_rect = far.region_rect
	foreground.position = area.position
	foreground.scale = area.size / Vector2(1920, 1080)


# 这口井在画面上的位置；震一下（幅度是游戏像素，取大的那个）
func set_base(p: Vector2) -> void:
	_base = p
	position = p


func shake(amount: float) -> void:
	if fx_on:
		_shake = maxf(_shake, amount)


func _set_item_look(n: Node2D) -> void:
	var conf: Dictionary = TIERS[_tier]
	var levels: Vector2 = Cfg.GLOW.get(n.kind, Vector2.ZERO)
	var dark_glow := levels.y
	if n.kind in ["bag", "chest"]:
		dark_glow *= float(conf.bag_chest_glow)
	var rim: Color = conf.rim.get(n.kind, Color.TRANSPARENT)
	rim.a *= 1.0 - _dark
	n.set_look(fx_on, _lit(), _dark, lerpf(levels.x if fx_on else 0.0, dark_glow, _dark), rim)


func _set_miner_dark(m: Dictionary, dark: float) -> void:
	m.hook.set_dark(dark)
	var brightness := lerpf(1.0, DARK_MINER_BRIGHTNESS, dark)
	m.root.modulate = Color(brightness, brightness, brightness, m.root.modulate.a)


# 黑灯是对局事件，所有画质和光影开关共用同一套明暗过渡。
func _apply_dark() -> void:
	var d := _dark
	_dark_done = d
	ambient.color = Color.WHITE.lerp(DARK_AMBIENT, d)
	if _test_light is DirectionalLight2D:
		foreground.self_modulate = ambient.color
		dust.self_modulate = ambient.color
	lights_root.modulate.a = 1.0 - d
	embers.modulate.a = 1.0 - d
	for n in _items.values():
		_set_item_look(n)
	for m in _miners.values():
		_set_miner_dark(m, d)


# 单次播放。用同一组图中可见范围最大的一帧对齐目标尺寸。
func _fx_sequence(kind: String, pos: Vector2, span: float) -> void:
	var conf: Dictionary = FX_SEQUENCES[kind]
	var frames: SpriteFrames = _fx_frames.get(kind)
	if frames == null:
		frames = SpriteFrames.new()
		frames.set_animation_loop("default", false)
		frames.set_animation_speed("default", float(conf.count) / float(conf.duration))
		for i in range(1, int(conf.count) + 1):
			frames.add_frame("default", load("res://art/%s_%d.png" % [kind, i]))
		_fx_frames[kind] = frames
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.material = MAT_UNSHADED
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.scale = Vector2.ONE * span / (float(conf.coverage) * frames.get_frame_texture("default", 0).get_width())
	s.position = pos
	s.modulate.a = float(conf.alpha)
	fx_root.add_child(s)
	s.animation_finished.connect(s.queue_free)
	s.play()
	var duration := float(conf.duration)
	s.create_tween().tween_property(s, "modulate:a", 0.0, duration * 0.5).set_delay(duration * 0.5)


func fx_grab(pos: Vector2, kind: String) -> void:
	var rock := kind in ["rs", "rl"]
	var radius := float(Cfg.b().TYPES[Cfg.type_index(kind)].r) * Cfg.S
	_fx_sequence("dust" if rock else "spark", pos, radius * 2.5)
	if not rock:
		fx_flash(pos, radius * 1.5, Color(1.0, 0.95, 0.8), 0.16, 0.4)


func fx_chest(id: int) -> void:
	var m: Dictionary = _miners.get(id, {})
	if m.is_empty():
		return
	var pos: Vector2 = m.root.position + m.head.position + Vector2(14, -14)
	pos.y = maxf(13.0, pos.y)
	var s := Sprite2D.new()
	s.texture = CHEST_OPEN
	s.material = MAT_UNSHADED
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.position = pos + Vector2(0, 7)
	var full_scale := Vector2.ONE * 24.0 / float(CHEST_OPEN.get_width())
	s.scale = full_scale * 0.4
	fx_root.add_child(s)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "position", pos, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "scale", full_scale, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(1.0)
	tw.chain().tween_property(s, "modulate:a", 0.0, 0.24)
	tw.chain().tween_callback(s.queue_free)
	_fx_sequence("spark", pos + Vector2(10, -2), 16.0)


# 飘字：从某个位置往上飘、淡出
func fx_text(pos: Vector2, text: String, color: Color = Color(1, 0.88, 0.29), size_mul: float = 1.0) -> void:
	var l := Label.new()
	l.material = MAT_UNSHADED
	l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Cfg.font() != null:
		l.add_theme_font_override("font", Cfg.font())
	l.add_theme_font_size_override("font_size", roundi(24 * size_mul))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.05))
	l.add_theme_constant_override("outline_size", 6)
	l.scale = Vector2(0.5, 0.5)                   # 字按两倍大小画再缩一半，放大后不糊
	l.size = Vector2(320, 30)
	l.position = pos + Vector2(-80, -8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = text
	l.z_index = 2
	fx_root.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 26.0, 1.2)
	tw.tween_property(l, "modulate:a", 0.0, 1.2).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(l.queue_free)


# 爆炸范围用半径换成直径，闪光叠在短暂的火球和烟上面。
func fx_boom(pos: Vector2, radius: float) -> void:
	_fx_sequence("boom", pos, radius * 2.0)
	fx_flash(pos, radius, Color(1, 0.75, 0.35), 0.32, 0.6)


func fx_flash(pos: Vector2, radius: float, color: Color, dur: float = 0.4, alpha: float = 1.0) -> void:
	if not _lit():
		return
	for pass_i in 2:
		var s := Sprite2D.new()
		s.texture = HALO
		s.material = MAT_ADD
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s.position = pos
		s.modulate = color if pass_i == 0 else Color(1, 1, 0.9, 1)
		s.modulate.a *= alpha
		s.z_index = 1
		var r0 := radius / 64.0 * (0.5 if pass_i == 0 else 0.25)
		s.scale = Vector2.ONE * r0
		fx_root.add_child(s)
		var tw := s.create_tween()
		tw.set_parallel(true)
		tw.tween_property(s, "scale", Vector2.ONE * r0 * 3.2, dur).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "modulate:a", 0.0, dur)
		tw.chain().tween_callback(s.queue_free)


func _process(dt: float) -> void:
	_t += dt
	# 震动：每帧随机偏一点，很快衰减
	if _shake > 0.02:
		position = _base + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * scale.x
		_shake = maxf(0.0, _shake - dt * (6.0 + _shake * 6.0))
	elif position != _base:
		position = _base
		_shake = 0.0
	# 黑灯：半秒左右暗下去、亮回来
	if _dark != _dark_want:
		_dark = move_toward(_dark, _dark_want, dt * 2.2)
	if absf(_dark - _dark_done) > 0.02 or (_dark == _dark_want and _dark != _dark_done):
		_apply_dark()
	if emis.visible:
		var pulse := 0.8 + 0.2 * sin(_t * 1.3) + 0.08 * sin(_t * 3.7) if fx_on else 0.8
		emis.modulate.a = LAVA_CRACK_STRENGTH * pulse * (1.0 - _dark)
	for i in _extra.size():
		var a := _t * (0.25 + 0.05 * i) + i * 1.7
		_extra[i].position = Vector2(320.0 + cos(a) * (120.0 + 22.0 * (i % 5)), 215.0 + sin(a * 1.3) * 95.0)
	if _move_test_light:
		_test_light.position.x = 320.0 + 240.0 * sin(_t * TAU / 12.0)


# 画质和光影开关控制装饰效果，黑灯事件由 _apply_dark 处理。
func apply(q: int, fx: bool) -> void:
	quality = q
	fx_on = fx
	var lit := _lit()
	lights_root.visible = fx
	for n in _items.values():
		_set_item_look(n)
	for n in fx_root.get_children():
		if n.material == MAT_ADD:
			n.visible = lit
	embers.visible = fx and _tier == 3
	dust.visible = fx and q != Cfg.Q.LOW
	for l in _extra:
		l.enabled = lit
	if _test_light != null:
		_test_light.enabled = lit
		if _test_light is DirectionalLight2D:
			for m in _miners.values():
				m.sprite.material = null if lit else MAT_UNSHADED


# 压力测试：把同屏真灯的总数加到 n 盏（多出来的在井里转圈）
func set_light_count(n: int) -> void:
	var extra_count := maxi(0, n - light_count())
	for _i in extra_count:
		var l := PointLight2D.new()
		l.texture = LIGHT_TEX
		l.texture_scale = 0.7
		l.height = 12.0
		l.energy = 0.3
		l.color = Color.from_hsv(fmod(0.08 + 0.13 * _extra.size(), 1.0), 0.55, 1.0)
		l.enabled = _lit()
		add_child(l)
		_extra.append(l)
	_fix_lights(self)


func light_count() -> int:
	return _extra.size() + int(_test_light != null) if _lit() else 0


# 灯光高度要跟着放大倍数走，不然放大后光会显得更"贴地"
func set_scale_k(kk: float) -> void:
	_k = kk
	_fix_lights(self)


func _fix_lights(root: Node) -> void:
	var list: Array = root.find_children("*", "PointLight2D", true, false)
	if root is PointLight2D:
		list.append(root)
	for n in list:
		if not n.has_meta("h0"):
			n.set_meta("h0", n.height)
		n.height = float(n.get_meta("h0")) * _k
