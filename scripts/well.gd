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
const MINER_SIZE := 64.0
const MINER_SOURCE_SIZE := 512.0
const WINCH_ROPE_EXIT := Vector2(256, 432)    # 四个矿工的各帧共用同一处绳卷出绳点
# 头灯灯芯在 512×512 原图上的位置。每个姿势对应同名的矿工贴图。
const HEAD_LAMPS := [
	{
		"idle": Vector2(153, 249), "idle2": Vector2(154, 258),
		"crank1": Vector2(154, 250), "crank2": Vector2(154, 249), "crank3": Vector2(155, 264), "crank4": Vector2(158, 252),
		"pull": Vector2(125, 253), "pull2": Vector2(119, 247), "happy": Vector2(146, 241), "happy2": Vector2(152, 222),
		"sad": Vector2(165, 262), "hit": Vector2(152, 250), "throw": Vector2(205, 257),
	},
	{
		"idle": Vector2(130, 246), "idle2": Vector2(129, 252),
		"crank1": Vector2(129, 248), "crank2": Vector2(129, 248), "crank3": Vector2(169, 283), "crank4": Vector2(184, 253),
		"pull": Vector2(119, 261), "pull2": Vector2(124, 263), "happy": Vector2(130, 246), "happy2": Vector2(129, 243),
		"sad": Vector2(161, 267), "hit": Vector2(129, 248), "throw": Vector2(204, 288),
	},
	{
		"idle": Vector2(145, 211), "idle2": Vector2(144, 216),
		"crank1": Vector2(144, 211), "crank2": Vector2(149, 221), "crank3": Vector2(164, 256), "crank4": Vector2(184, 231),
		"pull": Vector2(134, 235), "pull2": Vector2(101, 233), "happy": Vector2(145, 211), "happy2": Vector2(144, 196),
		"sad": Vector2(144, 211), "hit": Vector2(139, 211), "throw": Vector2(149, 221),
	},
	{
		"idle": Vector2(146, 205), "idle2": Vector2(146, 210),
		"crank1": Vector2(146, 201), "crank2": Vector2(131, 206), "crank3": Vector2(166, 243), "crank4": Vector2(181, 233),
		"pull": Vector2(120, 211), "pull2": Vector2(110, 227), "happy": Vector2(146, 205), "happy2": Vector2(146, 196),
		"sad": Vector2(181, 243), "hit": Vector2(141, 205), "throw": Vector2(184, 211),
	},
]
const FX_SEQUENCES := {
	"boom": {"count": 6, "duration": 0.5, "coverage": 416.0 / 512.0, "alpha": 0.84},
	"spark": {"count": 4, "duration": 0.3, "coverage": 336.0 / 512.0, "alpha": 0.95},
	"dust": {"count": 4, "duration": 0.4, "coverage": 432.0 / 512.0, "alpha": 0.72},
}
static var _fx_frames := {}

# 明暗对比（用户定的，要有反差感）。做法：
#   环境光压得比较低、偏冷；真的灯放在底图里画着光源的位置，偏暖、够亮；
#   井壁叠了程序生成的质地和凹凸（tools/gen_relief.mjs），灯照上去岩块有受光面和背光面，光柱一直打进井里。
#   amb    环境光：没被灯照到的地方保留多少亮度（颜色偏冷）
#   deep   井底的底图再压到多少（地面线以上基本不压）
#   glow   矿物的自发光：保证最暗处也分得清
#   bloom  泛光强度
#   detail 井壁明暗细节叠多重；bump 凹凸多强；emis 井壁自己发光的部分（矿脉、岩浆裂缝）多亮
#   lights [位置, 颜色, 强度, 范围, 光柱（0 没有，1 直着往下，2 斜着），离井壁的高度]
#   rim    哪些矿物在这一层和底图颜色太接近，要加描边光；dust 飘尘的颜色
const TIERS := [
	{   # 浅土层：晴天的地面，阳光从左上斜着照进土里，往下渐暗
		"bg": "bg_1", "amb": Color(0.5, 0.47, 0.5), "deep": 0.62, "glow": 0.3, "bloom": 0.24, "detail": 0.42, "bump": 1.0, "emis": 0.0,
		"ledge": 225.0,
		"lights": [[Vector2(24, 15), Color(1, 0.9, 0.68), 1.15, 3.6, 2, 50.0]],
		"rim": {"fos": Color(0.3, 0.17, 0.09, 0.7)}, "dust": Color(1, 0.95, 0.8),
	},
	{   # 岩石层：两盏矿灯打下暖光，井壁是冷色的碎裂岩块
		"bg": "bg_2", "amb": Color(0.33, 0.38, 0.56), "deep": 0.62, "glow": 0.45, "bloom": 0.28, "detail": 0.42, "bump": 1.1, "emis": 0.7,
		"ledge": 233.0,
		"lights": [
			[Vector2(81, 51), Color(1, 0.7, 0.38), 1.3, 2.3, 1, 46.0],
			[Vector2(403, 51), Color(1, 0.7, 0.38), 1.2, 2.2, 1, 46.0],
		],
		"rim": {"fos": Color(1, 0.92, 0.75, 0.5), "rs": Color(0.75, 0.82, 0.95, 0.4), "rl": Color(0.75, 0.82, 0.95, 0.4)}, "dust": Color(1, 0.92, 0.78),
	},
	{   # 晶洞层：横梁的蓝灯、远处晶体的青光和紫光
		"bg": "bg_3", "amb": Color(0.34, 0.34, 0.6), "deep": 0.62, "glow": 0.55, "bloom": 0.36, "detail": 0.4, "bump": 1.2, "emis": 0.9,
		"ledge": 228.0,
		"lights": [
			[Vector2(135, 20), Color(0.56, 0.8, 1), 0.72, 1.8, 1, 44.0],
			[Vector2(322, 20), Color(0.56, 0.8, 1), 0.68, 1.8, 1, 44.0],
			[Vector2(520, 20), Color(0.56, 0.8, 1), 0.72, 1.8, 1, 44.0],
			[Vector2(20, 61), Color(0.8, 0.55, 1), 1.15, 2.2, 0, 44.0],
			[Vector2(397, 32), Color(0.4, 0.95, 1), 0.8, 2.2, 0, 44.0],
			[Vector2(561, 46), Color(0.4, 0.95, 1), 0.65, 1.7, 0, 44.0],
			[Vector2(606, 63), Color(0.4, 0.95, 1), 0.55, 1.65, 0, 44.0],
		],
		"rim": {"gem": Color(0.9, 1, 1, 0.75), "bug": Color(1, 0.92, 1, 0.8), "rub": Color(1, 0.9, 0.92, 0.6), "rs": Color(0.75, 0.82, 1, 0.4), "rl": Color(0.75, 0.82, 1, 0.4)}, "dust": Color(0.6, 0.95, 1),
	},
	{   # 熔岩层：井架挂灯，井壁保留原有的岩浆裂缝自发光
		"bg": "bg_4", "amb": Color(0.4, 0.32, 0.36), "deep": 0.8, "glow": 0.8, "bloom": 0.44, "detail": 0.45, "bump": 1.2, "emis": 1.0,
		"ledge": 216.0,
		"lights": [[Vector2(151, 37), Color(1, 0.68, 0.36), 1.5, 2.2, 1, 42.0]],
		"rim": {"rs": Color(0.85, 0.8, 0.85, 0.4), "rl": Color(0.85, 0.8, 0.85, 0.4)}, "dust": Color(1, 0.55, 0.2),
	},
]

var quality: int = Cfg.Q.HIGH
var fx_on := true
var bloom := 0.36                # 当前层要的泛光强度，主场景来读
var _k := 1.0
var _items := {}                 # 物件 id → 节点
var _miners := {}                # 玩家 id → { root, sprite, hook, frames, c }
var _extra: Array[PointLight2D] = []
var _t := 0.0
var _tier := -1
var _base := Vector2.ZERO         # 这口井在画面上的位置（震动是在它上面加一点偏移）
var _shake := 0.0                 # 震动的幅度（游戏像素），自己衰减
var _dark := 0.0                  # 黑灯的程度，0 正常，1 全黑（只剩钩灯、头灯和会发光的东西）
var _dark_want := 0.0
var _dark_done := 0.0
var _live_t := -1.0               # 这一关是从什么时候开始挖的（中途冒出来的东西要有个"掉下来"的动作）
var _emis := 0.0

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
@onready var low_light: ColorRect = $LowLight


func _ready() -> void:
	low_light.material = low_light.material.duplicate()      # 每口井各用一份，不然分屏时几口井会互相盖掉
	low_light.material.set_shader_parameter("origin", low_light.position)
	var bm := ShaderMaterial.new()
	bm.shader = BG_SHADER
	bg.material = bm
	set_draw_area(Rect2(0, 0, Cfg.GW, Cfg.GH))
	_set_tier(1)
	apply(quality, fx_on)


func _lit() -> bool:
	return fx_on and quality != Cfg.Q.LOW


func _set_tier(tier: int) -> void:
	_tier = tier
	var t: Dictionary = TIERS[tier]
	bg.texture = load("res://art/%s.png" % t.bg)
	far.texture = load("res://art/%s_far.png" % t.bg)
	frame_layer.texture = load("res://art/%s_frame.png" % t.bg)
	foreground.texture = load("res://art/%s_fg.png" % t.bg)
	ambient.color = t.amb
	bloom = t.bloom
	var bm: ShaderMaterial = bg.material
	bm.set_shader_parameter("deep_mul", t.deep)
	bm.set_shader_parameter("relief", load("res://art/relief_%d.png" % tier))
	bm.set_shader_parameter("relief_n", load("res://art/relief_%d_n.png" % tier))
	bm.set_shader_parameter("detail", t.detail)
	bm.set_shader_parameter("bump", t.bump)
	emis.texture = load("res://art/relief_%d_e.png" % tier)
	_emis = t.emis
	dust.color = Color(t.dust.r, t.dust.g, t.dust.b, 0.85)
	embers.emitting = tier == 3
	embers.visible = tier == 3 and fx_on
	for c in lights_root.get_children():
		lights_root.remove_child(c)
		c.queue_free()
	for l in t.lights:
		var node := Node2D.new()
		node.position = l[0]
		var pl := PointLight2D.new()
		pl.texture = LIGHT_TEX
		pl.color = l[1]
		pl.energy = l[2]
		pl.texture_scale = l[3]
		pl.height = l[5]
		pl.set_meta("e0", l[2])
		node.add_child(pl)
		var halo := Sprite2D.new()
		halo.texture = HALO
		halo.material = MAT_ADD
		halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		halo.z_index = 45
		halo.scale = Vector2.ONE * 0.6
		halo.modulate = Color(l[1].r, l[1].g, l[1].b, 0.38)
		node.add_child(halo)
		if int(l[4]) > 0:                         # 一束光柱，一直打进井里；斜的那种像从缝里漏下来的天光
			var shaft := ColorRect.new()
			var m := ShaderMaterial.new()
			m.shader = SHAFT
			m.set_shader_parameter("strength", 0.26)
			m.set_shader_parameter("tint", Color(l[1].r, l[1].g, l[1].b, 1.0))
			m.set_shader_parameter("seed", l[0].x * 0.01)
			m.set_shader_parameter("half_angle", 0.46 if int(l[4]) == 1 else 0.3)
			shaft.material = m
			shaft.position = Vector2(-170, 2)
			shaft.size = Vector2(340, 340)
			shaft.pivot_offset = Vector2(170, 0)
			if int(l[4]) == 2:
				shaft.rotation = 0.5 if l[0].x < 320.0 else -0.42
			shaft.z_index = 44
			shaft.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.add_child(shaft)
		lights_root.add_child(node)
	_fix_lights(lights_root)
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
			items_root.add_child(n)
			n.set_look(fx_on, _lit(), _glow_for(n.kind), conf.rim.get(n.kind, Color(1, 1, 1, 0)))
			_fix_lights(n)
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
		var head_lamp: Vector2 = HEAD_LAMPS[int(p.c) % HEAD_LAMPS.size()][frame]
		m.head.position = (head_lamp - sprite_center) * source_scale
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
	for pose in HEAD_LAMPS[c % HEAD_LAMPS.size()]:
		frames[pose] = load(base + ("" if pose == "idle" else "_" + pose) + ".tres")
	var sprite := Sprite2D.new()
	sprite.texture = frames.idle
	sprite.scale = Vector2.ONE * MINER_SIZE / float(frames.idle.get_width())
	root.add_child(sprite)
	var ice := Sprite2D.new()
	ice.texture = ICE
	ice.scale = Vector2.ONE * MINER_SIZE / float(ICE.get_width())
	ice.material = MAT_UNSHADED
	ice.modulate.a = 0.48
	ice.z_index = 63
	ice.hide()
	root.add_child(ice)
	var head := PointLight2D.new()                # 头灯：照亮矿工自己和脚下一小块
	head.texture = LIGHT_TEX
	head.texture_scale = 0.5
	head.color = Color(1, 0.9, 0.7)
	head.energy = 0.3
	head.height = 20.0
	head.enabled = _lit()
	root.add_child(head)
	var hook: Node2D = HOOK.instantiate()
	miners_root.add_child(hook)
	hook.set_fx(fx_on, _lit())
	_fix_lights(root)
	_fix_lights(hook)
	return {"root": root, "sprite": sprite, "hook": hook, "frames": frames, "c": c, "head": head, "ice": ice}


func miner_pos(id: int) -> Vector2:
	var m: Dictionary = _miners.get(id, {})
	return m.root.position if not m.is_empty() else Vector2(320, 51)


# 井壁、远景与支架在窗口露出的范围内按同一坐标镜像。剪影贴着实际画面四边，避免在中央竖起两道剪影。
func set_draw_area(area: Rect2) -> void:
	var visible_area := area.merge(Rect2(0, 0, Cfg.GW, Cfg.GH)).grow(4.0)
	var cave := Rect2(visible_area.position.x, 80.0, visible_area.size.x, visible_area.end.y - 80.0)
	bg.position = cave.position
	bg.region_rect = Rect2(cave.position * 3.0, cave.size * 3.0)
	bg.material.set_shader_parameter("region_origin", bg.region_rect.position)
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


# 一件东西自己的微光有多亮。黑灯的时候值钱的东西调亮（不能完全看不见）；石头和炸药桶不调，藏在黑里，这就是黑灯的坑
func _glow_for(kind: String) -> float:
	var conf: Dictionary = TIERS[maxi(_tier, 0)]
	if kind in ["rs", "rl", "tnt"]:
		return float(conf.glow) * (1.0 - 0.6 * _dark)
	return float(conf.glow) * (1.0 + 2.0 * _dark) + 0.5 * _dark


# 黑灯：环境光几乎压没，画里的灯暗下去，钩灯和头灯变亮，所有东西自己的微光调高（值钱的东西不能完全看不见）
func _apply_dark() -> void:
	var conf: Dictionary = TIERS[maxi(_tier, 0)]
	var d := _dark
	_dark_done = d
	var amb: Color = conf.amb
	ambient.color = amb.lerp(Color(amb.r * 0.1, amb.g * 0.1, amb.b * 0.15), d)
	if fx_on:
		bg.material.set_shader_parameter("deep_mul", float(conf.deep) * (1.0 - 0.55 * d))
		bg.material.set_shader_parameter("top_mul", 0.95 * (1.0 - 0.6 * d))
	for n in lights_root.get_children():
		n.modulate.a = 1.0 - 0.85 * d
	for n in _items.values():
		n.set_look(fx_on, _lit(), _glow_for(n.kind), conf.rim.get(n.kind, Color(1, 1, 1, 0)))
	for m in _miners.values():
		m.hook.set_dark(d)
		m.head.energy = 0.3 + 0.5 * d


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
	# 井壁上自己发光的部分（矿脉、岩浆）缓慢地一明一暗
	var pulse := _emis * (0.8 + 0.2 * sin(_t * 1.3) + 0.08 * sin(_t * 3.7))
	emis.modulate = Color(pulse, pulse, pulse, 1.0)
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
	for n in lights_root.get_children():           # 画里的灯轻轻摇曳
		var pl: PointLight2D = n.get_child(0)
		pl.energy = float(pl.get_meta("e0")) * (1.0 + 0.06 * sin(_t * 6.1 + n.position.x) + 0.03 * sin(_t * 13.3)) * (1.0 - 0.85 * _dark)
	for i in _extra.size():
		var a := _t * (0.25 + 0.05 * i) + i * 1.7
		_extra[i].position = Vector2(320.0 + cos(a) * (120.0 + 22.0 * (i % 5)), 215.0 + sin(a * 1.3) * 95.0)
	if low_light.visible:
		_update_low_light()


# 画质和光影总开关。lit = 用真灯加法线贴图；低档不用真灯，改用一层整屏的"光斑"
func apply(q: int, fx: bool) -> void:
	quality = q
	fx_on = fx
	var lit := _lit()
	var conf: Dictionary = TIERS[maxi(_tier, 0)]
	ambient.visible = lit
	low_light.visible = fx and q == Cfg.Q.LOW
	for n in lights_root.get_children():
		n.get_child(0).enabled = lit
		for i in range(1, n.get_child_count()):
			n.get_child(i).visible = fx
	for n in _items.values():
		n.set_look(fx, lit, _glow_for(n.kind), conf.rim.get(n.kind, Color(1, 1, 1, 0)))
	for m in _miners.values():
		m.hook.set_fx(fx, lit)
		m.head.enabled = lit
	for n in fx_root.get_children():
		if n.material == MAT_ADD:
			n.visible = lit
	bg.material.set_shader_parameter("top_mul", 0.95 if fx else 1.0)       # 关掉光影时底图恢复原样
	if not fx:
		bg.material.set_shader_parameter("deep_mul", 1.0)
		bg.material.set_shader_parameter("saturation", 1.0)
	else:
		bg.material.set_shader_parameter("deep_mul", conf.deep)
		bg.material.set_shader_parameter("saturation", 1.12)
	emis.visible = fx
	embers.visible = fx and _tier == 3
	dust.visible = fx and q != Cfg.Q.LOW
	for l in _extra:
		l.enabled = lit


# 压力测试：把同屏真灯的总数加到 n 盏（多出来的在井里转圈）
func set_light_count(n: int) -> void:
	while light_count() < n:
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
	var gems := 0
	for n in _items.values():
		if n.light.visible:
			gems += 1
	return lights_root.get_child_count() + _miners.size() * 2 + gems + _extra.size()


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


func _update_low_light() -> void:
	var ls := PackedVector4Array()
	var cs := PackedVector3Array()
	for n in lights_root.get_children():
		var pl: PointLight2D = n.get_child(0)
		ls.append(Vector4(n.position.x, n.position.y, 128.0 * pl.texture_scale, pl.energy))
		cs.append(Vector3(pl.color.r, pl.color.g, pl.color.b))
	for m in _miners.values():
		if ls.size() >= 12:
			break
		var cp: Vector2 = m.hook.position + m.hook.claw.position
		ls.append(Vector4(cp.x, cp.y + 6.0, 110.0, 0.8))
		cs.append(Vector3(1.0, 0.88, 0.66))
	var cnt := ls.size()
	ls.resize(12)
	cs.resize(12)
	var mat: ShaderMaterial = low_light.material
	mat.set_shader_parameter("count", cnt)
	mat.set_shader_parameter("lights", ls)
	mat.set_shader_parameter("colors", cs)
	mat.set_shader_parameter("ambient", Vector3(ambient.color.r, ambient.color.g, ambient.color.b))
