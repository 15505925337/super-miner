# 一口井（只负责画）：底图、点缀的灯光、矿工、钩子、矿物、飘字。
# 画什么全听 set_view() 传进来的内容，那是客户端按服务端状态插值算出来的。
# 合作、同屏对战只有一口井，铺满屏幕；分屏对战每人一口，各画在自己的小窗里。
# 名字、钱、关数这些字不画在这里，由界面层按屏幕分辨率画（缩放后字才清楚）。
extends Node2D

const Cfg = preload("res://scripts/cfg.gd")
const ITEM := preload("res://scenes/item.tscn")
const HOOK := preload("res://scenes/hook.tscn")
const GI := preload("res://scripts/gi.gd")
const LIGHT_TEX := preload("res://res/light_radial.tres")
const HALO := preload("res://res/halo.tres")
const SOFT_SHADOW := preload("res://res/soft_shadow.tres")
const MAT_ADD := preload("res://res/mat_add.tres")
const MAT_UNSHADED := preload("res://res/mat_unshaded.tres")
const ICE := preload("res://art/ice.png")
const CHEST_OPEN := preload("res://art/chest_open.png")
const MAT_SHARP_UNSHADED := preload("res://res/mat_sharp_unshaded.tres")
const PIXEL_SCALE := 2.0 / 3.0   # 1080p 下一个贴图像素对应两个屏幕像素。
const CHEST_GAP := 4.0           # 弹图和矿工画布的间距（游戏像素）。
const SHAFT := preload("res://shaders/shaft.gdshader")
const BG_SHADER := preload("res://shaders/bg.gdshader")
const LAVA_CRACKS := preload("res://art/relief_3_e.png")
const LAVA_CRACK_STRENGTH := 0.60
const DARK_AMBIENT := Color(0.06, 0.06, 0.09)
const CAVE_TOP := 80.0
const MINER_SIZE := 64.0
const DARK_MINER_BRIGHTNESS := 0.40
const MINER_SOURCE_SIZE := 512.0
const WINCH_ROPE_EXIT := Vector2(256, 432)    # 四个矿工的各帧共用同一处绳卷出绳点
const MINER_LEDGE_OFFSET := 31.8             # 贴图中心到台沿的距离（游戏像素）
const MINER_CONTACT := Vector2(-11.0, MINER_LEDGE_OFFSET)
const MINER_POSES := [
	"idle", "idle2", "crank1", "crank2", "crank3", "crank4",
	"pull", "pull2", "happy", "happy2", "sad", "hit", "throw",
]
const FX_SEQUENCES := {
	"boom": {"count": 6, "duration": 0.5, "alpha": 0.84},
	"spark": {"count": 4, "duration": 0.3, "alpha": 0.95},
	"dust": {"count": 4, "duration": 0.4, "alpha": 0.72},
}
const FX_SIZES := {"s": 32, "m": 52, "l": 100}
const FX_COVERAGE := 0.84      # 火花和尘土的可见范围约占画布边长的 84%。
static var _fx_frames := {}
static var _chest_ink := Rect2(CHEST_OPEN.get_image().get_used_rect())

# 以原画为主。井壁、远景和支架共用同一层的调色，环境光只在黑灯事件里压暗。
#   grade [伽马, 对比度, 饱和度]；grade_tint 各色通道倍率；bag_chest_glow 宝袋和宝箱的黑灯倍率；bloom 泛光强度
#   light_dir 是光照过去的单位向量（向右、向下为正）；light_col 主光色；under_col 岩浆反光
#   lamps 是原画里的光源位置；beam 是光柱半张角；rim 是需要额外辨识度的物件的描边强度
const TIERS := [
	{   # 浅土层：保留原画里的土黄色和斜阳
		"bg": "bg_1", "grade": Vector3.ONE, "bag_chest_glow": 1.4, "bloom": 0.06,
		"ledge": 225.0,
		"light_dir": Vector2(0.707107, 0.707107), "light_col": Color(1.0, 0.94, 0.82),
		"lamps": [Vector2(24, 15)], "beam": 0.30,
		"rim": {"fos": 0.7}, "dust": Color(1, 0.95, 0.8),
	},
	{   # 岩石层：两盏矿灯打下暖光，井壁是冷色的碎裂岩块
		"bg": "bg_2", "grade": Vector3.ONE, "bag_chest_glow": 1.85, "bloom": 0.06,
		"ledge": 233.0,
		"miner_shadow_height": 4.0, "miner_shadow_distance": 1.2,   # 岩石台沿窄，软影收在台沿附近
		"light_dir": Vector2(0.28, 0.96), "light_col": Color(1.0, 0.78, 0.52),
		"lamps": [Vector2(81, 51), Vector2(403, 51)], "beam": 0.46,
		"rim": {"fos": 0.5, "rs": 0.4, "rl": 0.4}, "dust": Color(1, 0.92, 0.78),
	},
	{   # 晶洞层：提亮蓝紫色岩壁，支架蓝灯只留小光晕
		"bg": "bg_3", "grade": Vector3(1.18, 1.02, 1.04), "bag_chest_glow": 2.15, "bloom": 0.04,
		"ledge": 228.0,
		"light_dir": Vector2(0.20, 0.979796), "light_col": Color(0.64, 0.83, 1.0),
		"lamps": [Vector2(135, 20), Vector2(322, 20), Vector2(520, 20)],
		"rim": {"gem": 0.75, "bug": 0.8, "rub": 0.6, "rs": 0.4, "rl": 0.4}, "dust": Color(0.6, 0.95, 1),
	},
	{   # 熔岩层：井架挂灯，井壁保留原有的岩浆裂缝自发光
		"bg": "bg_4", "grade": Vector3(1.34, 1.12, 1.40), "grade_tint": Vector3(1.08, 1.05, 0.60),
		"bag_chest_glow": 2.9, "bloom": 0.06,
		"ledge": 216.0,
		"light_dir": Vector2(0.60, 0.80), "light_col": Color(1.0, 0.74, 0.47),
		"under_col": Color(1.0, 0.32, 0.20, 0.22),
		"lamps": [Vector2(151, 37)], "beam": 0.46,
		"rim": {"rs": 0.4, "rl": 0.4, "tnt": 0.28},
		"dust": Color(1, 0.55, 0.2),
	},
]

var quality: int = Cfg.Q.HIGH
var fx_on := true
var chest_layer: Node2D          # 玩法合成画布，以最终屏幕像素绘制开箱弹图。
var bloom := 0.06                # 当前层要的泛光强度，主场景来读
var _k := 1.0
var _items := {}                 # 物件 id → 节点
var _miners := {}                # 玩家 id → { root, sprite, shadow, hook, frames, ice }
var _gi: GI
var _extra: Array[PointLight2D] = []
var _chest_popups := {}          # 开箱玩家 id → 弹图节点。
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
	bloom = t.bloom
	bg.material.set_shader_parameter("grade", t.grade)
	bg.material.set_shader_parameter("grade_tint", t.get("grade_tint", Vector3.ONE))
	emis.visible = tier == 3 and _show_lava_cracks
	dust.color = Color(t.dust.r, t.dust.g, t.dust.b, 0.85)
	embers.emitting = tier == 3
	for c in lights_root.get_children():
		lights_root.remove_child(c)
		c.queue_free()
	var light_col: Color = t.light_col
	var beam := float(t.get("beam", 0.0))
	for lamp_pos in t.lamps:
		var node := Node2D.new()
		node.position = lamp_pos
		# 小光晕和光柱画在矿工后面。
		var halo := Sprite2D.new()
		halo.texture = HALO
		halo.material = MAT_ADD
		halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		halo.z_index = -5
		halo.scale = Vector2.ONE * 0.28
		halo.modulate = Color(light_col, 0.18)
		node.add_child(halo)
		if beam > 0.0:
			var shaft := ColorRect.new()
			var m := ShaderMaterial.new()
			m.shader = SHAFT
			m.set_shader_parameter("strength", 0.045)
			m.set_shader_parameter("tint", light_col)
			m.set_shader_parameter("seed", node.position.x * 0.01)
			m.set_shader_parameter("half_angle", beam)
			shaft.material = m
			shaft.position = Vector2(-70, 0)
			shaft.size = Vector2(140, 140)
			shaft.pivot_offset = Vector2(70, 0)
			shaft.rotation = Vector2.DOWN.angle_to(t.light_dir)
			shaft.z_index = -6
			shaft.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.add_child(shaft)
		lights_root.add_child(node)
	for n in _items.values():
		_set_item_lighting(n)
	if _gi != null:
		_gi.set_tier(t, tier == 3, CAVE_TOP if tier == 0 else 0.0)
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
		clear_chest_popups()
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
			_set_item_lighting(n)
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
		m.frame = frame
		# 动作帧已画好身体起伏，整张图保持固定，让木台贴着台沿。
		m.root.position = Vector2(x, ledge - MINER_LEDGE_OFFSET)
		m.ice.visible = int(p.fz) == 1 or _t < float(m.get("preview_ice_until", 0.0))
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
	sprite.material = MAT_UNSHADED
	sprite.scale = Vector2.ONE * MINER_SIZE / float(frames.idle.get_width())
	root.add_child(sprite)
	# 木台底部在贴图中心的左侧，短影贴住底边和台沿。
	var shadow := Sprite2D.new()
	shadow.texture = SOFT_SHADOW
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shadow.z_index = -1
	root.add_child(shadow)
	var ice := Sprite2D.new()
	ice.texture = ICE
	ice.material = MAT_SHARP_UNSHADED
	ice.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ice.scale = Vector2.ONE * PIXEL_SCALE
	ice.modulate.a = 0.48
	ice.z_index = 63
	ice.hide()
	root.add_child(ice)
	var hook: Node2D = HOOK.instantiate()
	miners_root.add_child(hook)
	var m := {"c": c, "root": root, "sprite": sprite, "shadow": shadow, "hook": hook, "frames": frames, "ice": ice}
	_set_miner_dark(m, _dark)
	return m


func miner_pos(id: int) -> Vector2:
	var m: Dictionary = _miners.get(id, {})
	return m.root.position if not m.is_empty() else Vector2(320, 51)


# 井壁、远景与支架在窗口露出的范围内按同一坐标镜像。剪影贴着实际画面四边，避免在中央竖起两道剪影。
func set_draw_area(area: Rect2) -> void:
	var visible_area := area.merge(Rect2(0, 0, Cfg.GW, Cfg.GH)).grow(4.0)
	var cave := Rect2(visible_area.position.x, CAVE_TOP, visible_area.size.x, visible_area.end.y - CAVE_TOP)
	bg.position = cave.position
	bg.region_rect = Rect2(cave.position * 3.0, cave.size * 3.0)
	emis.position = cave.position
	emis.region_rect = Rect2(cave.position * 1.5, cave.size * 1.5)
	var passage := Rect2(visible_area.position.x, 0.0, visible_area.size.x, CAVE_TOP)
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


func _set_item_lighting(n: Node2D) -> void:
	var conf: Dictionary = TIERS[_tier]
	n.set_lighting(conf.light_dir, conf.light_col, conf.get("under_col", Color.TRANSPARENT))


func _set_item_look(n: Node2D) -> void:
	var conf: Dictionary = TIERS[_tier]
	var detail := _lit()
	var dark_glow := float(Cfg.DARK_GLOW.get(n.kind, 0.0))
	if n.kind in ["bag", "chest"]:
		dark_glow *= float(conf.bag_chest_glow)
	var rim_strength := float(conf.rim.get(n.kind, 0.20))
	n.set_look(detail, _dark, dark_glow * _dark, rim_strength)


func _set_miner_shadow(m: Dictionary) -> void:
	var conf: Dictionary = TIERS[_tier]
	m.shadow.position = MINER_CONTACT + conf.light_dir * float(conf.get("miner_shadow_distance", 2.0))
	m.shadow.scale = Vector2(46.0, float(conf.get("miner_shadow_height", 5.0))) / SOFT_SHADOW.get_size()
	m.shadow.modulate.a = 0.92 * (1.0 - _dark)
	m.shadow.visible = _lit() and _dark < 1.0


func _set_miner_dark(m: Dictionary, dark: float) -> void:
	m.hook.set_dark(dark)
	var brightness := lerpf(1.0, DARK_MINER_BRIGHTNESS, dark)
	m.root.modulate = Color(brightness, brightness, brightness, m.root.modulate.a)
	_set_miner_shadow(m)


# 黑灯是对局事件，所有画质和光影开关共用同一套明暗过渡。
func _apply_dark() -> void:
	var d := _dark
	_dark_done = d
	if _gi != null:
		_gi.set_dark(d)
	ambient.color = Color.WHITE.lerp(DARK_AMBIENT, d)
	lights_root.modulate.a = 1.0 - d
	embers.modulate.a = 1.0 - d
	for n in _items.values():
		_set_item_look(n)
	for m in _miners.values():
		_set_miner_dark(m, d)


# 演示局从首帧进入指定明暗。
func set_dark_now(dark: float) -> void:
	_dark = dark
	_dark_want = dark
	_apply_dark()


func set_gi(on: bool, divisor: int, bounce: float, shadow: float, keep_dark_glow: bool) -> void:
	if _gi == null:
		if not on:
			return
		_gi = GI.new(_items, _miners, divisor, bounce, shadow, keep_dark_glow)
		add_child(_gi)
		_gi.set_tier(TIERS[_tier], _tier == 3, CAVE_TOP if _tier == 0 else 0.0)
		_gi.set_dark(_dark_done)
	_gi.set_active(on)


# 按画面上的物件边长，找可见范围最接近的一档。
func _fx_size(span: float) -> String:
	var closest := "s"
	var best := INF
	for size: String in FX_SIZES:
		var difference := absf(span - float(FX_SIZES[size]) * PIXEL_SCALE * FX_COVERAGE)
		if difference < best:
			closest = size
			best = difference
	return closest


# 单次播放。帧组按类别和档位复用，每个贴图像素的大小固定。
func _fx_sequence(kind: String, pos: Vector2, size: String = "", parent: Node2D = null) -> void:
	var conf: Dictionary = FX_SEQUENCES[kind]
	var prefix := kind if size.is_empty() else "%s_%s" % [kind, size]
	var frames: SpriteFrames = _fx_frames.get(prefix)
	if frames == null:
		frames = SpriteFrames.new()
		frames.set_animation_loop("default", false)
		frames.set_animation_speed("default", float(conf.count) / float(conf.duration))
		for i in range(1, int(conf.count) + 1):
			frames.add_frame("default", load("res://art/%s_%d.png" % [prefix, i]))
		_fx_frames[prefix] = frames
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.material = MAT_SHARP_UNSHADED
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.scale = Vector2.ONE * PIXEL_SCALE
	s.position = pos
	s.modulate.a = float(conf.alpha)
	(parent if parent != null else fx_root).add_child(s)
	s.animation_finished.connect(s.queue_free)
	s.play()
	var duration := float(conf.duration)
	s.create_tween().tween_property(s, "modulate:a", 0.0, duration * 0.5).set_delay(duration * 0.5)


func fx_grab(pos: Vector2, kind: String) -> void:
	var rock := kind in ["rs", "rl"]
	var radius := float(Cfg.b().TYPES[Cfg.type_index(kind)].r) * Cfg.S
	_fx_sequence("dust" if rock else "spark", pos, _fx_size(radius * 2.5))
	if not rock:
		fx_flash(pos, radius * 1.5, Color(1.0, 0.95, 0.8), 0.16, 0.4)


func fx_chest(id: int) -> void:
	if not _miners.has(id) or _chest_popups.has(id):
		return
	var popup := Node2D.new()
	popup.hide()
	popup.modulate.a = 0.0
	chest_layer.add_child(popup)
	_chest_popups[id] = popup
	var sprite := Sprite2D.new()
	sprite.texture = CHEST_OPEN
	sprite.material = MAT_SHARP_UNSHADED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.centered = false
	sprite.scale = Vector2.ONE * PIXEL_SCALE
	popup.add_child(sprite)
	_fx_sequence("spark", Vector2(25, 22) * PIXEL_SCALE, _fx_size(16.0), popup)
	var tw := popup.create_tween()
	tw.tween_property(popup, "modulate:a", 1.0, 0.16)
	tw.tween_interval(1.0)
	tw.tween_property(popup, "modulate:a", 0.0, 0.24)
	tw.tween_callback(_remove_chest_popup.bind(id))


func has_chest_popups() -> bool:
	return not _chest_popups.is_empty()


func _remove_chest_popup(id: int) -> void:
	var popup: Node2D = _chest_popups[id]
	chest_layer.remove_child(popup)
	popup.queue_free()
	_chest_popups.erase(id)


func clear_chest_popups() -> void:
	for id in _chest_popups.keys():
		_remove_chest_popup(id)


# 名字在屏幕坐标里，矿工和绳子从各自的井投到同一个坐标系。
func layout_chest_popups(to_screen: Transform2D, name_bounds: Array[Rect2]) -> void:
	if _chest_popups.is_empty():
		return
	var blocked := name_bounds.duplicate()
	var miner_bounds := {}
	for id in _miners:
		var m: Dictionary = _miners[id]
		var sprite: Sprite2D = m.sprite
		var box := to_screen * sprite.get_global_transform() * sprite.get_rect()
		miner_bounds[id] = box
		blocked.append(box)
		if m.hook.visible:
			var rope: Line2D = m.hook.rope_edge
			var rope_to_screen := to_screen * rope.get_global_transform()
			var padding := rope.width * 0.5 * rope_to_screen.get_scale().x + 1.0
			for i in range(1, rope.points.size()):
				var a := rope_to_screen * rope.points[i - 1]
				var b := rope_to_screen * rope.points[i]
				blocked.append(Rect2(a, b - a).abs().grow(padding))
	var render := to_screen * get_global_transform()
	var zoom := render.get_scale().x
	var texel := zoom * PIXEL_SCALE
	var field := to_screen * Rect2(_base, Vector2(Cfg.GW, Cfg.GH) * scale)
	var ledge := (render * Vector2(0, float(TIERS[_tier].ledge) / 3.0)).y
	var y := roundf(ledge - _chest_ink.end.y * texel)
	var ink := Rect2(_chest_ink.position * texel, _chest_ink.size * texel).grow(0.5)
	for id in _chest_popups.keys():
		if not miner_bounds.has(id):
			_remove_chest_popup(id)
			continue
		var miner: Rect2 = miner_bounds[id]
		var popup: Node2D = _chest_popups[id]
		var right := ceilf(miner.end.x + CHEST_GAP * zoom - ink.position.x)
		var left := floorf(miner.position.x - CHEST_GAP * zoom - ink.end.x)
		var free_right := _free_chest_x(right, 1.0, y, ink, field, blocked)
		var x := free_right
		if free_right != right:
			var free_left := _free_chest_x(left, -1.0, y, ink, field, blocked)
			if is_finite(free_left) and (free_left == left or left - free_left < free_right - right):
				x = free_left
		popup.visible = is_finite(x)
		if popup.visible:
			popup.position = Vector2(x, y)
			popup.scale = Vector2.ONE * zoom
			blocked.append(Rect2(popup.position + ink.position, ink.size))


# 遇到障碍时移到它另一端，直到同一台沿上有空位或到达井边。
func _free_chest_x(start: float, direction: float, y: float, ink: Rect2, field: Rect2, blocked: Array[Rect2]) -> float:
	var x := start
	var box := Rect2(Vector2(x, y) + ink.position, ink.size)
	while field.encloses(box):
		var next := x
		for obstacle in blocked:
			if box.intersects(obstacle):
				if direction > 0.0:
					next = maxf(next, maxf(x + 1.0, ceilf(obstacle.end.x - ink.position.x)))
				else:
					next = minf(next, minf(x - 1.0, floorf(obstacle.position.x - ink.end.x)))
		if next == x:
			return x
		x = next
		box.position.x = x + ink.position.x
	return INF


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


# 火球和烟用固定画布，附加闪光按服务端给的半径绘制。
func fx_boom(pos: Vector2, radius: float) -> void:
	_fx_sequence("boom", pos)
	fx_flash(pos, radius, Color(1, 0.75, 0.35), 0.32, 0.6)


# 网页验收用，只播放指定帧组或临时显示冰层。
func preview_fx(kind: String, size: String, pos: Vector2) -> void:
	if kind == "boom":
		_fx_sequence(kind, pos)
	elif kind in ["spark", "dust"] and FX_SIZES.has(size):
		_fx_sequence(kind, pos, size)


func preview_ice(id: int) -> void:
	if _miners.has(id):
		_miners[id].preview_ice_until = _t + float(Cfg.b().RULES.freezeSecs)


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
	dt = Cfg.visual_delta(dt)
	if Cfg.dumping_frames and dt == 0.0:
		return
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
		var pulse := 0.8 + 0.2 * sin(_t * 1.3) + 0.08 * sin(_t * 3.7) if _lit() else 0.8
		emis.modulate.a = LAVA_CRACK_STRENGTH * pulse * (1.0 - _dark)
	for i in _extra.size():
		var a := _t * (0.25 + 0.05 * i) + i * 1.7
		_extra[i].position = Vector2(320.0 + cos(a) * (120.0 + 22.0 * (i % 5)), 215.0 + sin(a * 1.3) * 95.0)


# 画质和光影开关控制装饰效果，黑灯事件由 _apply_dark 处理。
func apply(q: int, fx: bool) -> void:
	quality = q
	fx_on = fx
	var lit := _lit()
	lights_root.visible = lit
	for n in _items.values():
		_set_item_look(n)
	for m in _miners.values():
		_set_miner_shadow(m)
	for n in fx_root.get_children():
		if n.material == MAT_ADD:
			n.visible = lit
	embers.visible = lit and _tier == 3
	dust.visible = lit
	for l in _extra:
		l.enabled = lit


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
	return _extra.size() if _lit() else 0


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
