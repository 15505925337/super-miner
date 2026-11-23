# 界面：首页、房间、对局中的道具栏、关末结算、商店、总结算，以及井上所有的字。
# 样式参考《八方旅人》那一类界面的做法（只参考做法，不用它的任何素材）：
#   暗色半透明的底、上下渐变，细金线双框和四角小装饰，左上一片柔光，外面一圈柔和的投影；
#   字用米白，强调用暖金；按钮平时很安静，指到时泛起一圈金色的光；
#   面板打开时，后面的游戏画面虚化、压暗（在 main.gd 的最终合成里做）。
# 整个界面按 640×360 设计，由引擎按放大倍数重新生成字形，任何倍数下都清楚。
extends Control

const Cfg = preload("res://scripts/cfg.gd")
const PANEL_SHADER := preload("res://shaders/ui_panel.gdshader")
const HALO := preload("res://res/halo.tres")
const MAT_ADD := preload("res://res/mat_add.tres")
const SHOP_SHELF_Y := 201.0                       # 原图货架上沿 y≈603
const SHOP_COUNTER_Y := 290.0                     # 原图柜台上沿 y≈870
const SHOP_FACE_Y := 138.0
const SHOP_CARD_WIDTH := 84.0
const KEEPER_EXPRESSIONS := ["happy", "angry", "think", "surprised", "sigh", "smug", "refuse"]

const MODE_DESC := {
	"co": "共用一口井，钱算全队的，手里的钱到了累计目标才能进下一关。",
	"race": "每人一口一模一样的井，各挖各的，钱到不了累计目标就淘汰，比谁过关多。",
	"vs": "大家挤在同一口井里抢，打完钱最多的赢。",
}
const GOLD := Color(0.96, 0.8, 0.46)             # 暖金：标题、强调、钱
const GOLD_DIM := Color(0.62, 0.5, 0.28)         # 暗金：平时的描边
const CREAM := Color(0.94, 0.9, 0.8)             # 米白：正文
const DIM := Color(0.7, 0.65, 0.56)              # 次要的字
const INK := Color(0.1, 0.07, 0.05)              # 最深的暖棕：字的描边、阴影
const BAD := Color(1.0, 0.56, 0.44)              # 坏消息（没过关、淘汰、掉线）
const PAD := 12.0                                # 面板四周留给投影的宽度

var cl: Node                     # 客户端逻辑（client.gd）
var reg := {}                    # 名字 → 控件，自动测试用它找到按钮的位置
var _sig := {}                   # 各块内容的"指纹"，内容没变就不重建
var _toast_t := 0.0
var _shop_sel := ""              # 商店里选中准备还价的商品
var _face := ""
var _keeper_faces := {}
var _keeper_lines := {}         # 玩家 id → 当前话序、表情和收到它们的时间
var _blink_at := -1.0
var _t := 0.0
var _draw_area := Rect2(0, 0, Cfg.GW, Cfg.GH)

var home: Control
var home_bg: Sprite2D
var lobby: Control
var hud: Control
var hud_text: Control            # 井上的字都画在这里（在各个面板下面）
var rend: Control
var shop: Control
var over: Control
var solo_over: Control
var pause_btn: Button
var pause_layer: Control
var pause_shade: ColorRect
var resume_btn: Button
var pause_title: Label
var pause_actions: VBoxContainer
var leave_confirm: VBoxContainer
var name_edit: LineEdit
var code_edit: LineEdit
var solo_role_name: Label
var solo_role_skill: Label
var lobby_box: VBoxContainer
var lobby_pick_id := 0
var tools_bar: HBoxContainer
var count_l: Label
var toast_l: Label
var toast_band: TextureRect
var net_l: Label
var rend_box: VBoxContainer
var over_box: VBoxContainer
var solo_over_box: VBoxContainer
var shop_head: Label
var shop_sub: Label
var shop_timer: Label
var shop_seats: HBoxContainer
var shop_say: Label
var shop_face: TextureRect
var shop_halo: TextureRect
var shop_mood: Label
var shop_bar: ProgressBar
var shop_info: Label
var shop_items: Control
var shop_bg: Sprite2D
var shop_counter: Sprite2D
var shop_own: Label
var buy_btn: Button
var offer_btn: Button
var _cards := {}                 # 货架上的货：代号 → {card, icon, halo, name, tag, price, born, scale}
var shop_sel_l: Label
var shop_desc: Label
var _shop_hover := ""
var offer_edit: LineEdit
var say_edit: LineEdit
var ready_btn: Button
var _hud_pool: Array = []
var _hud_n := 0
var _veils: Array = []
var _veil_n := 0
var _bands: Array = []
var _band_n := 0
var _band_tex: GradientTexture2D
var emo_btn: Button
var emo_box: VBoxContainer
var help: Control
var mute_btn: Button
var _last_ph := ""


# 标题下面的分隔线：两头淡出的细金线，中间一个小菱形
class Divider extends Control:
	var col := Color(0.9, 0.74, 0.44)

	func _init() -> void:
		custom_minimum_size = Vector2(0, 7)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var y := size.y * 0.5
		var seg := 24
		for i in seg:
			var a0 := float(i) / seg
			var a1 := float(i + 1) / seg
			var fade := sin(((a0 + a1) * 0.5) * PI)
			if absf((a0 + a1) * 0.5 - 0.5) < 0.03:
				continue
			draw_line(Vector2(a0 * w, y), Vector2(a1 * w, y), Color(col.r, col.g, col.b, 0.75 * fade), 1.0)
		var c := Vector2(w * 0.5, y)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(3, 0), c + Vector2(0, 3), c + Vector2(-3, 0)]), col)


func _ready() -> void:
	size = Vector2(Cfg.GW, Cfg.GH)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	_band_tex = _gradient(Color(0.03, 0.02, 0.02, 0.62), Color(0.03, 0.02, 0.02, 0.0), true)
	hud_text = Control.new()
	hud_text.size = size
	hud_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_text)
	_build_home()
	_build_lobby()
	_build_hud()
	_build_rend()
	_build_shop()
	_build_over()
	_build_pause()
	_build_help()
	# 提示条：一条两头淡出的暗带，字在中间
	toast_band = TextureRect.new()
	toast_band.texture = _gradient(Color(0.04, 0.03, 0.03, 0.0), Color(0.04, 0.03, 0.03, 0.82), false, true)
	toast_band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	toast_band.stretch_mode = TextureRect.STRETCH_SCALE
	toast_band.position = Vector2(110, 44)
	toast_band.size = Vector2(420, 20)
	toast_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_band.visible = false
	add_child(toast_band)
	toast_l = _l("", 12, CREAM)
	toast_l.position = Vector2(110, 47)
	toast_l.size = Vector2(420, 16)
	toast_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_l)
	net_l = _l("连接断开，正在重连…", 12, BAD)
	net_l.position = Vector2(220, 318)
	net_l.size = Vector2(200, 14)
	net_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(net_l, 4)
	add_child(net_l)
	cl.changed.connect(refresh)
	cl.toast.connect(_show_toast)
	name_edit.text = Net.my_name
	if Cfg.args().has("r"):
		code_edit.text = String(Cfg.args()["r"])
	refresh()


# 有面板开着（主场景据此把后面的游戏画面虚化、压暗）
func menu_open() -> bool:
	return home.visible or lobby.visible or rend.visible or shop.visible or over.visible or solo_over.visible or help.visible


# ───── 样式 ─────
func _gradient(a: Color, b: Color, vertical: bool, mirror: bool = false) -> GradientTexture2D:
	var g := Gradient.new()
	if mirror:                                    # 两头是 a，中间是 b
		g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
		g.colors = PackedColorArray([a, b, b, a])
	else:
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([a, b])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	return t


# bg 底色，border 描边，glow > 0 时外面带一圈光（平时是深色的投影，指到时是金色的光）
func _box(bg: Color, border: Color, pad_x: int = 6, pad_y: int = 3, glow: Color = Color(0, 0, 0, 0), glow_size: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	s.set_corner_radius_all(2)
	s.border_blend = true
	if glow_size > 0:
		s.shadow_color = glow
		s.shadow_size = glow_size
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	if Cfg.font() != null:
		t.default_font = Cfg.font()
	t.default_font_size = 12
	var dark := Color(0.12, 0.085, 0.065, 0.86)
	var shade := Color(0.02, 0.012, 0.01, 0.45)
	var lit := Color(1.0, 0.82, 0.45, 0.42)
	# 普通按钮：安静的暗底细金边；指到时底色变暖、边变亮、外面泛一圈金光
	t.set_stylebox("normal", "Button", _box(dark, GOLD_DIM, 6, 3, shade, 3))
	t.set_stylebox("hover", "Button", _box(Color(0.3, 0.21, 0.1, 0.94), Color(1.0, 0.87, 0.55), 6, 3, lit, 6))
	t.set_stylebox("pressed", "Button", _box(Color(0.46, 0.33, 0.14, 0.96), Color(1.0, 0.92, 0.66), 6, 3, lit, 3))
	t.set_stylebox("disabled", "Button", _box(Color(0.09, 0.07, 0.065, 0.6), Color(0.3, 0.26, 0.2), 6, 3))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color(1.0, 0.95, 0.8))
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.48, 0.44, 0.38))
	t.set_color("icon_disabled_color", "Button", Color(1, 1, 1, 0.35))
	# 主要按钮（开始、准备好了）：一块发亮的金
	t.set_type_variation("Primary", "Button")
	t.set_stylebox("normal", "Primary", _box(Color(0.78, 0.58, 0.24), Color(1.0, 0.9, 0.62), 8, 3, Color(1.0, 0.75, 0.3, 0.3), 5))
	t.set_stylebox("hover", "Primary", _box(Color(0.93, 0.72, 0.32), Color(1.0, 0.96, 0.78), 8, 3, Color(1.0, 0.82, 0.4, 0.55), 8))
	t.set_stylebox("pressed", "Primary", _box(Color(0.62, 0.45, 0.17), Color(1.0, 0.9, 0.62), 8, 3, Color(1.0, 0.75, 0.3, 0.3), 3))
	t.set_stylebox("disabled", "Primary", _box(Color(0.2, 0.16, 0.11, 0.7), Color(0.36, 0.3, 0.2), 8, 3))
	t.set_color("font_color", "Primary", INK)
	t.set_color("font_hover_color", "Primary", INK)
	t.set_color("font_pressed_color", "Primary", INK)
	t.set_color("font_disabled_color", "Primary", Color(0.5, 0.45, 0.36))
	# 小按钮：商店每一行用，矮一点
	t.set_type_variation("Small", "Button")
	t.set_stylebox("normal", "Small", _box(dark, GOLD_DIM, 5, 1))
	t.set_stylebox("hover", "Small", _box(Color(0.3, 0.21, 0.1, 0.94), Color(1.0, 0.87, 0.55), 5, 1, lit, 4))
	t.set_stylebox("pressed", "Small", _box(Color(0.46, 0.33, 0.14, 0.96), Color(1.0, 0.92, 0.66), 5, 1))
	t.set_stylebox("disabled", "Small", _box(Color(0.09, 0.07, 0.065, 0.5), Color(0.26, 0.23, 0.18), 5, 1))
	t.set_color("font_color", "Label", CREAM)
	# 输入框：往里凹的暗底；选中时金边发亮
	t.set_stylebox("normal", "LineEdit", _box(Color(0.03, 0.022, 0.025, 0.86), GOLD_DIM, 5, 3))
	t.set_stylebox("focus", "LineEdit", _box(Color(0.06, 0.045, 0.035, 0.92), Color(1.0, 0.87, 0.55), 5, 3, lit, 5))
	t.set_stylebox("read_only", "LineEdit", _box(Color(0.06, 0.05, 0.05, 0.6), Color(0.34, 0.29, 0.2), 5, 3))
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_color("font_uneditable_color", "LineEdit", DIM)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.5, 0.46, 0.4))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(0.9, 0.7, 0.3, 0.4))
	# 耐心条
	t.set_stylebox("background", "ProgressBar", _box(Color(0.03, 0.022, 0.025, 0.86), GOLD_DIM, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _box(Color(0.9, 0.68, 0.3), Color(1.0, 0.9, 0.6), 0, 0))
	t.set_constant("separation", "VBoxContainer", 4)
	t.set_constant("separation", "HBoxContainer", 5)
	return t


func _outline(l: Label, w: int = 3) -> void:
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", w)


func _l(text: String, fs: int = 12, color: Color = CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	return l


# 标题：暖金色的大字，带一点深色的投影
func _title(text: String, fs: int = 24, color: Color = GOLD) -> Label:
	var l := _l(text, fs, color)
	l.add_theme_color_override("font_shadow_color", Color(0.02, 0.01, 0.0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _b(text: String, cb: Callable, key: String = "", variation: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	if variation != "":
		b.theme_type_variation = variation
	if key != "":
		reg[key] = b
	return b


func _edit(placeholder: String, max_len: int, key: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.context_menu_enabled = false
	reg[key] = e
	return e


# 一块面板：底是着色器画的（暗底、金线双框、角饰、柔光、投影），内容加在返回的控件上
func _panel(r: Rect2) -> Control:
	var p := Control.new()
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.position = Vector2(-PAD, -PAD)
	bg.size = r.size + Vector2(PAD, PAD) * 2.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = PANEL_SHADER
	m.set_shader_parameter("size", bg.size)
	m.set_shader_parameter("pad", PAD)
	bg.material = m
	p.add_child(bg)
	add_child(p)
	return p


func _vbox(p: Control, margin: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = Vector2(margin, margin)
	v.size = p.size - Vector2(margin, margin) * 2
	p.add_child(v)
	return v


func _hbox(children: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	for c in children:
		h.add_child(c)
	return h


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _spacer_v() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _pic(path: String, min_size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.custom_minimum_size = min_size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


# 一团柔光（叠加），放在标题或头像后面，像有盏灯照着
func _halo(color: Color, box: Rect2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = HALO
	t.material = MAT_ADD
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	t.position = box.position
	t.size = box.size
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _dot(c: Color) -> ColorRect:
	var d := ColorRect.new()
	d.color = c
	d.custom_minimum_size = Vector2(4, 12)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _portrait(c: int, height: int, cb: Callable, key: String) -> Button:
	var b := _b("", cb, key, "Small")
	b.icon = load("res://art/miner_%d.png" % (c + 1))
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.custom_minimum_size = Vector2(height, height)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var role := Cfg.character(c)
	b.tooltip_text = "%s · %s" % [role.n, role.d]
	return b


# ───── 首页 ─────
func _build_home() -> void:
	home_bg = _screen_bg(preload("res://art/home_bg.png"))
	add_child(home_bg)
	home = _panel(Rect2(160, 16, 320, 328))
	home.add_child(_halo(Color(1.0, 0.74, 0.36, 0.5), Rect2(40, -34, 240, 150)))
	var v := _vbox(home, 14)
	v.add_child(_pic("res://art/logo.png", Vector2(0, 68)))
	v.add_theme_constant_override("separation", 2)
	var solo := _b("单人闯关", func(): cl.create("solo", name_edit.text), "create_solo", "Primary")
	solo.custom_minimum_size.y = 34
	solo.add_theme_font_size_override("font_size", 18)
	v.add_child(solo)
	var picks := _hbox([_spacer()])
	var group := ButtonGroup.new()
	for c in Cfg.b().CHARACTERS.size():
		var portrait := _portrait(c, 30, _pick_solo_character.bind(c), "solo_role_%d" % c)
		portrait.toggle_mode = true
		portrait.button_group = group
		portrait.button_pressed = c == cl.solo_character
		picks.add_child(portrait)
	var details := VBoxContainer.new()
	details.custom_minimum_size.x = 106
	details.add_theme_constant_override("separation", 0)
	solo_role_name = _l("", 12)
	solo_role_skill = _l("", 11, DIM)
	details.add_child(solo_role_name)
	details.add_child(solo_role_skill)
	picks.add_child(details)
	picks.add_child(_spacer())
	v.add_child(picks)
	_show_solo_character(cl.solo_character)
	v.add_child(Divider.new())
	name_edit = _edit("起个名字（最多 10 个字）", 10, "name_edit")
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_hbox([_l("名字", 12, GOLD), name_edit]))
	v.add_child(_l("和朋友一起玩", 12, GOLD))
	var descriptions := {"co": "共用一口井，合力达到目标", "race": "各挖一口井，比谁闯得远", "vs": "同一口井抢矿，比谁钱多"}
	for m in ["co", "race", "vs"]:
		var b := _b(String(Cfg.b().MODE_NAMES[m]), func(): cl.create(m, name_edit.text), "create_" + m)
		b.custom_minimum_size = Vector2(76, 24)
		v.add_child(_hbox([b, _l(descriptions[m], 12, DIM)]))
	v.add_child(Divider.new())
	code_edit = _edit("4 位房间号", 4, "code_edit")
	code_edit.custom_minimum_size = Vector2(90, 0)
	code_edit.text_submitted.connect(func(_t): cl.join(code_edit.text, name_edit.text))
	v.add_child(_hbox([_l("进别人的房间", 12, GOLD), _spacer(), code_edit, _b("进房间", func(): cl.join(code_edit.text, name_edit.text), "join")]))


func _pick_solo_character(c: int) -> void:
	cl.set_solo_character(c)
	_show_solo_character(c)


func _show_solo_character(c: int) -> void:
	var role := Cfg.character(c)
	solo_role_name.text = String(role.n)
	solo_role_name.add_theme_color_override("font_color", Cfg.COLORS[c])
	solo_role_skill.text = String(role.d)


# 整屏底图与井下用同一比例，超出原图的部分镜像延展。
func _screen_bg(texture: Texture2D) -> Sprite2D:
	var bg := Sprite2D.new()
	bg.texture = texture
	bg.centered = false
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR
	bg.scale = Vector2.ONE / 3.0
	bg.region_enabled = true
	return bg


func set_draw_area(area: Rect2) -> void:
	_draw_area = area
	pause_shade.position = area.position
	pause_shade.size = area.size
	for bg in [home_bg, shop_bg]:
		bg.position = area.position
		bg.region_rect = Rect2(area.position * 3.0, area.size * 3.0)
	var counter_area := Rect2(area.position.x, SHOP_COUNTER_Y, area.size.x, area.end.y - SHOP_COUNTER_Y)
	shop_counter.position = counter_area.position
	shop_counter.region_rect = Rect2(counter_area.position * 3.0, counter_area.size * 3.0)


# ───── 房间（等人） ─────
func _build_lobby() -> void:
	lobby = _panel(Rect2(110, 12, 420, 336))
	lobby_box = _vbox(lobby, 12)
	lobby_box.add_theme_constant_override("separation", 2)


func _fill_lobby() -> void:
	var m: Dictionary = cl.meta
	var mine: Array = cl.my_ids()
	if not mine.has(lobby_pick_id):
		lobby_pick_id = int(mine[0]) if not mine.is_empty() else 0
	var sig := JSON.stringify([m.code, m.mode, m.rounds, m.players, m.host, m.you, m.get("urls", []), lobby_pick_id])
	if _sig.get("lobby", "") == sig:
		return
	_sig["lobby"] = sig
	_clear(lobby_box)
	var host: bool = cl.is_host()
	var mode := String(m.mode)
	lobby_box.add_child(_hbox([_title("房间 " + String(m.code), 24), _spacer(), _title(String(Cfg.b().MODE_NAMES[mode]), 16, CREAM)]))
	lobby_box.add_child(Divider.new())
	var link := LineEdit.new()
	link.text = Net.invite_url(String(m.code))
	link.editable = false
	link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_box.add_child(_hbox([_l("邀请地址", 12, GOLD), link]))
	var urls: Array = m.get("urls", [])
	if not urls.is_empty():
		var network_links := VBoxContainer.new()
		network_links.add_theme_constant_override("separation", 0)
		for u in urls:
			network_links.add_child(_l("同一 WiFi：" + String(u) + "/?r=" + String(m.code), 12, DIM))
		var links_scroll := ScrollContainer.new()
		links_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		links_scroll.add_child(network_links)
		lobby_box.add_child(links_scroll)
		var row_height := network_links.get_combined_minimum_size().y / urls.size()
		links_scroll.custom_minimum_size.y = row_height * mini(urls.size(), 2)
	var desc := _l(MODE_DESC[mode], 12, DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	lobby_box.add_child(desc)
	var occupants := {}
	for p in m.players:
		occupants[int(p.c)] = p
	var portraits := _hbox([])
	for c in Cfg.b().CHARACTERS.size():
		portraits.add_child(_lobby_role_card(c, occupants.get(c, {}), mine, int(m.hostId), host))
	lobby_box.add_child(portraits)
	if mine.size() > 1:
		var seats := _hbox([_l("为本机座位选角", 12, GOLD)])
		for i in mine.size():
			var id := int(mine[i])
			var b := _b("%d号 · %s" % [i + 1, Cfg.KEYSETS[i].label], _pick_lobby_seat.bind(id), "pick_seat_%d" % i, "Small")
			b.disabled = lobby_pick_id == id
			b.tooltip_text = cl.pname(id)
			seats.add_child(b)
		lobby_box.add_child(seats)
	lobby_box.add_child(_spacer_v())
	lobby_box.add_child(Divider.new())
	if host:
		var modes := [_l("玩法", 12, GOLD)]
		for k in ["co", "race", "vs"]:
			var b := _b(String(Cfg.b().MODE_NAMES[k]), func(): Net.send({"t": "cfg", "mode": k}), "mode_" + k)
			b.disabled = k == mode
			modes.append(b)
		if mode == "vs":
			modes.append(_spacer())
			modes.append(_l("局数", 12, GOLD))
			for r in [3, 5]:
				var b := _b("%d 局" % r, func(): Net.send({"t": "cfg", "rounds": r}), "rounds_%d" % r)
				b.disabled = int(m.rounds) == r
				modes.append(b)
		lobby_box.add_child(_hbox(modes))
	var full: bool = m.players.size() >= int(Cfg.b().MAXP)
	var btns := [_b("离开", func(): Net.send({"t": "leave"}), "leave")]
	var add_local := _b("本机加一人", func(): Net.send({"t": "addLocal"}), "add_local")
	add_local.disabled = full
	btns.append(add_local)
	btns.append(_b("玩法说明", _show_help.bind(true), "help"))
	if host:
		var add_bot := _b("加电脑", func(): Net.send({"t": "addBot"}), "add_bot")
		add_bot.disabled = full
		btns.append(add_bot)
		btns.append(_spacer())
		btns.append(_b("　开 始　", func(): Net.send({"t": "start"}), "start", "Primary"))
	else:
		btns.append(_spacer())
		btns.append(_l("等房主开始…", 12, DIM))
	lobby_box.add_child(_hbox(btns))


func _pick_lobby_seat(id: int) -> void:
	lobby_pick_id = id
	_fill_lobby()


func _lobby_role_card(c: int, p: Dictionary, mine: Array, host_id: int, host: bool) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 1)
	var id := int(p.get("id", 0))
	var bot := bool(p.get("bot", false))
	var seat := mine.find(id)
	var selected := id != 0 and id == lobby_pick_id
	var portrait := _portrait(c, 40, func(): Net.send({"t": "pick", "i": lobby_pick_id, "c": c}), "pick_role_%d" % c)
	portrait.disabled = id != 0 and not bot
	portrait.add_theme_color_override("icon_disabled_color", Color.WHITE)
	if selected:
		portrait.add_theme_stylebox_override("disabled", _box(Color(0.3, 0.21, 0.1, 0.94), Cfg.COLORS[c], 5, 1, GOLD, 3))
	elif id != 0:
		portrait.modulate = Color(1, 1, 1, 0.55)
	card.add_child(portrait)
	var role := Cfg.character(c)
	var role_name := _l(String(role.n), 12, Cfg.COLORS[c])
	role_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(role_name)
	var skill := _l(String(role.d), 11, CREAM)
	skill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(skill)
	var occupant := "可选择" if id == 0 else String(p.name)
	if bot:
		portrait.tooltip_text += "\n电脑 %s 会让位" % occupant
		occupant += " · 可让位"
	elif seat >= 0:
		portrait.tooltip_text += "\n%s · %s放钩" % [occupant, Cfg.KEYSETS[seat].label]
	elif id != 0:
		portrait.tooltip_text += "\n%s 已选" % occupant
	if id == host_id:
		portrait.tooltip_text += " · 房主"
	var player := _l(occupant, 11, GOLD if selected else DIM)
	player.tooltip_text = occupant
	player.mouse_filter = Control.MOUSE_FILTER_PASS
	player.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(player)
	if id != 0 and (seat > 0 or (host and seat < 0)):
		card.add_child(_b("请出", func(): Net.send({"t": "kick", "id": id}), "kick_%d" % id, "Small"))
	return card


# ───── 对局中：道具栏、倒计时、井上的字 ─────
func _build_hud() -> void:
	hud = Control.new()
	hud.size = size
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	tools_bar = HBoxContainer.new()
	tools_bar.position = Vector2(240, 338)
	tools_bar.size = Vector2(160, 20)
	tools_bar.add_theme_constant_override("separation", 3)
	tools_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	hud.add_child(tools_bar)
	count_l = _title("", 64, GOLD)
	_outline(count_l, 10)
	count_l.position = Vector2(170, 120)
	count_l.size = Vector2(300, 80)
	count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(count_l)
	pause_btn = _b("暂停", func(): cl.request_solo_pause(true), "solo_pause", "Small")
	pause_btn.position = Vector2(588, 2)
	pause_btn.custom_minimum_size = Vector2(44, 20)
	pause_btn.tooltip_text = "Esc 暂停"
	hud.add_child(pause_btn)
	# 喊话：左下角一个小按钮，点开是六句固定的话（也可以直接按 Z X C V B N）
	var list: Array = Cfg.b().FUN.emotes
	emo_box = VBoxContainer.new()
	emo_box.position = Vector2(3, 339 - list.size() * 18)
	emo_box.add_theme_constant_override("separation", 1)
	emo_box.visible = false
	hud.add_child(emo_box)
	for i in list.size():
		var b := _b("%s [%s]" % [String(list[i]), cl.EMOTE_KEY_NAMES[i]], _send_emo.bind(i), "emo_%d" % i, "Small")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		emo_box.add_child(b)
	emo_btn = _b("喊话", func(): emo_box.visible = not emo_box.visible, "emo_btn", "Small")
	emo_btn.position = Vector2(3, 341)
	hud.add_child(emo_btn)


func _send_emo(i: int) -> void:
	cl.emote(i)
	emo_box.visible = false


# ───── 玩法说明 ─────
func _build_help() -> void:
	help = _panel(Rect2(56, 10, 528, 340))
	help.visible = false
	var v := _vbox(help, 14)
	mute_btn = _b("", _toggle_mute, "mute")
	v.add_child(_hbox([_title("玩法说明", 24), _spacer(), mute_btn, _b("关闭", _show_help.bind(false), "help_close")]))
	v.add_child(Divider.new())
	var f: Dictionary = Cfg.b().FUN
	var ev: Dictionary = f.events
	var parts := [
		["合作联机（两人以上）", "巨型金块一个人拉不动：钩住后吊着等队友，队友也钩上去才拉得动，%d 秒没人帮就松手。钥匙和宝箱要两个人分工：一人把钥匙钩上来，另一人把宝箱拉上来才打得开；没钥匙，或者拿钥匙的人自己去拉，宝箱会掉回原处。" % int(f.coop.giantWait)],
		["分屏对战", "连续钩中值钱的东西（落后的人 %d 次，领先的人 %d 次），就往钱最多的对手井里丢一块碎石；钩空、钩到石头、炸了炸药桶，连钩就断。每人每关最多挨 %d 块。被淘汰后不用干等：按放钩键往钱最多的人井里丢碎石，每 %d 秒一次，每关最多 %d 次。" % [int(f.race.comboBehind), int(f.race.comboLead), int(f.race.rockCap), int(f.race.ghostCd), int(f.race.ghostCap)]],
		["随机事件（第 %d 关起，每关最多一个，倒计时的时候预告）" % int(ev.firstRound), "金矿雨：第 %d 秒掉下一批金块。塌方：第 %d 秒掉下一堆石头。黑灯：第 %d 秒灯灭 %d 秒，只看得清钩灯照到的地方。" % [int(ev.rain.at), int(ev.cave.at), int(ev.dark.at), int(ev.dark.secs)]],
		["喊话、声音、颁奖", "对局里按 Z X C V B N 喊话，或者点左下角的「喊话」。按 M 开关声音。整场打完按每个人的数据颁奖，人人有份。"],
	]
	for p in parts:
		v.add_child(_l(String(p[0]), 12, GOLD))
		var body := _l(String(p[1]), 12, CREAM)
		body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		v.add_child(body)
	_toggle_mute(false)


# 打开玩法说明时先把后面的房间面板收起来，不然两层字叠在一起
func _show_help(on: bool) -> void:
	help.visible = on
	lobby.visible = cl.ph() == "lobby" and not on


func _toggle_mute(flip: bool = true) -> void:
	if flip:
		Sfx.set_muted(not Sfx.muted)
	mute_btn.text = "声音：关" if Sfx.muted else "声音：开"


# huds 里每一项是一口井：{origin 井的左上角, scale 井相对 640×360 的缩放, plate, plank, clock, veil, players}
func draw_hud(huds: Array, split: bool) -> void:
	_hud_n = 0
	_veil_n = 0
	_band_n = 0
	for h in huds:
		var o: Vector2 = h.origin
		var sc: float = h.scale
		if sc < 0.4:                              # 对手的小窗太小，只留一行名字和钱
			for p in h.players:
				_hud_text(o + Vector2(3, 1), Vector2(118, 10), "%s %s" % [p.name, Cfg.money(p.m)], 8, cl.pcolor(int(p.id)), HORIZONTAL_ALIGNMENT_LEFT)
		else:
			var fs := maxi(8, roundi(12 * sc))
			if String(h.plate) != "" or String(h.plank) != "":   # 顶上一条往下淡出的暗带，字压在上面才清楚
				var band := Rect2(o, Vector2(Cfg.GW, 26) * sc)
				if not split:
					band.position.x = _draw_area.position.x
					band.size.x = _draw_area.size.x
				_band(band.position, band.size)
			_hud_text(o + Vector2(8, 3) * sc, Vector2(220, 16) * sc, String(h.plate), fs, CREAM, HORIZONTAL_ALIGNMENT_LEFT)
			_hud_text(o + Vector2(170, 3) * sc, Vector2(300, 16) * sc, String(h.plank), fs, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
			var clock_x := 483 if cl.mode() == "solo" else 540
			_hud_text(o + Vector2(clock_x, 3) * sc, Vector2(92, 16) * sc, String(h.clock), fs, CREAM, HORIZONTAL_ALIGNMENT_RIGHT)
			for p in h.players:
				var x: float = float(p.x) * Cfg.S
				_hud_text(o + Vector2(x - 75, 31) * sc, Vector2(150, 14) * sc, String(p.name) + "  " + String(p.tag), fs, cl.pcolor(int(p.id)), HORIZONTAL_ALIGNMENT_CENTER)
				if String(p.hint) != "":
					_hud_text(o + Vector2(x - 90, 15) * sc, Vector2(180, 14) * sc, String(p.hint), fs, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
		if String(h.veil) != "":                  # 淘汰了：盖一层深色，写上"淘汰"
			if _veil_n >= _veils.size():
				var r := ColorRect.new()
				r.color = Color(0.04, 0.025, 0.03, 0.72)
				r.mouse_filter = Control.MOUSE_FILTER_IGNORE
				hud_text.add_child(r)
				hud_text.move_child(r, 0)
				_veils.append(r)
			_veils[_veil_n].position = o
			_veils[_veil_n].size = Vector2(Cfg.GW, Cfg.GH) * sc
			_veils[_veil_n].visible = true
			_veil_n += 1
			_hud_text(o + Vector2(0, 150) * sc, Vector2(640, 40) * sc, String(h.veil), maxi(8, roundi(24 * sc)), BAD, HORIZONTAL_ALIGNMENT_CENTER)
			if String(h.get("note", "")) != "":       # 自己淘汰了：下面一行写怎么丢石头
				_hud_text(o + Vector2(0, 190) * sc, Vector2(640, 16) * sc, String(h.note), maxi(8, roundi(12 * sc)), CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	# 倒计时的时候，在数字下面大字预告这一关的随机事件
	if huds.size() > 0 and String(huds[0].get("event_big", "")) != "":
		_hud_text(Vector2(70, 204), Vector2(500, 30), String(huds[0].event_big), 24, Color(1.0, 0.68, 0.42), HORIZONTAL_ALIGNMENT_CENTER)
		_hud_text(Vector2(70, 234), Vector2(500, 16), String(huds[0].event_sub), 12, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(_hud_n, _hud_pool.size()):
		_hud_pool[i].visible = false
	for i in range(_veil_n, _veils.size()):
		_veils[i].visible = false
	for i in range(_band_n, _bands.size()):
		_bands[i].visible = false


func _band(pos: Vector2, box: Vector2) -> void:
	if _band_n >= _bands.size():
		var t := TextureRect.new()
		t.texture = _band_tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_text.add_child(t)
		hud_text.move_child(t, 0)
		_bands.append(t)
	var b: TextureRect = _bands[_band_n]
	_band_n += 1
	b.visible = true
	b.position = pos
	b.size = box


func _hud_text(pos: Vector2, box: Vector2, text: String, fs: int, color: Color, align: int) -> void:
	if text == "":
		return
	if _hud_n >= _hud_pool.size():
		var n := Label.new()
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.add_theme_color_override("font_outline_color", INK)
		hud_text.add_child(n)
		_hud_pool.append(n)
	var l: Label = _hud_pool[_hud_n]
	_hud_n += 1
	l.visible = true
	l.position = pos
	l.size = box
	l.horizontal_alignment = align
	if l.text != text:
		l.text = text
	if l.get_meta("fs", 0) != fs:
		l.set_meta("fs", fs)
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_constant_override("outline_size", maxi(2, fs / 3))
	l.add_theme_color_override("font_color", color)


func _fill_hud() -> void:
	var ids: Array = cl.my_ids()
	var me: Dictionary = cl.pstate(ids[0]) if ids.size() > 0 else {}
	var order: Array = Cfg.b().TOOL_ORDER[cl.mode()]
	var sig := JSON.stringify([cl.mode(), me.get("tl", {}), int(me.get("out", 0))])
	if _sig.get("hud", "") != sig:
		_sig["hud"] = sig
		_clear(tools_bar)
		if not me.is_empty() and int(me.get("out", 0)) == 0:
			for i in order.size():
				var k: String = order[i]
				var n := int(me.tl.get(k, 0))
				# 道具栏要窄：服务端只在井底正中留了一小块不放矿物（左右各约 64 个游戏像素），所以只放图标、数量和按键
				var b := _b("×%d [%s]" % [n, Cfg.KEYSETS[0].tl[i]], func(): cl.tool_seat(0, i), "tool_" + k, "Small")
				b.tooltip_text = String(Cfg.b().SHOP[k].n)
				b.icon = load("res://art/icon_%s.png" % k)
				b.add_theme_constant_override("icon_max_width", 14)
				b.disabled = n <= 0
				tools_bar.add_child(b)
	count_l.text = str(maxi(1, ceili(cl.time_left()))) if cl.ph() == "count" else ""


# ───── 一关结束 ─────
func _build_rend() -> void:
	rend = _panel(Rect2(170, 70, 300, 220))
	rend_box = _vbox(rend, 14)


func _rank_row(pos: int, id: int, mid: String, right: String, mid_color: Color = DIM) -> HBoxContainer:
	var name_l := _l(cl.pname(id), 12, cl.pcolor(id))
	var you := _l("（你）" if cl.seat_of(id) >= 0 else "", 12, DIM)
	return _hbox([_l("%d" % pos, 12, GOLD), _dot(cl.pcolor(id)), name_l, you, _spacer(), _l(mid, 12, mid_color), _l(right, 12, GOLD)])


func _fill_rend() -> void:
	var r: Dictionary = cl.cur.get("res", {})
	var sig := JSON.stringify(r)
	if r.is_empty() or _sig.get("rend", "") == sig:
		return
	_sig["rend"] = sig
	_clear(rend_box)
	var rows: Array = r.rows.duplicate()
	var mode := String(r.mode)
	if mode == "co":
		var co: Dictionary = r.co
		rend_box.add_child(_title("第 %d 关%s" % [int(r.round), "过关" if bool(co.pass) else "没过关"], 24, GOLD if bool(co.pass) else BAD))
		rend_box.add_child(Divider.new())
		rend_box.add_child(_l("累计目标 %s，全队手里 %s" % [Cfg.money(co.target), Cfg.money(co.have)], 12, DIM))
		rows.sort_custom(func(x, y): return int(x.e) > int(y.e))
		for i in rows.size():
			rend_box.add_child(_rank_row(i + 1, int(rows[i].id), "这一关挖了", Cfg.money(rows[i].e)))
	elif mode == "solo":
		var row: Dictionary = rows[0]
		var passed := not bool(r.final)
		rend_box.add_child(_title("第 %d 关%s" % [int(r.round), "过关" if passed else "没过关"], 24, GOLD if passed else BAD))
		rend_box.add_child(Divider.new())
		rend_box.add_child(_l("手里的钱 %s / %s" % [Cfg.money(row.m), Cfg.money(r.target)], 12, DIM))
		rend_box.add_child(_l("这一关挖了 %s" % Cfg.money(row.e), 12, GOLD))
	elif mode == "race":
		rend_box.add_child(_title("第 %d 关结束" % int(r.round), 24))
		rend_box.add_child(Divider.new())
		rend_box.add_child(_l("手里的钱要到 %s 才算过关" % Cfg.money(r.target), 12, DIM))
		rows.sort_custom(func(x, y): return int(x.m) > int(y.m))
		for i in rows.size():
			var x: Dictionary = rows[i]
			var bad: bool = int(x.out) == 1
			var st := "这一关淘汰" if int(x.now) == 1 else ("已淘汰" if bad else "过关")
			rend_box.add_child(_rank_row(i + 1, int(x.id), st, Cfg.money(x.m), BAD if bad else DIM))
	else:
		rend_box.add_child(_title("第 %d / %d 局结束" % [int(r.round), int(cl.meta.rounds)], 24))
		rend_box.add_child(Divider.new())
		rows.sort_custom(func(x, y): return int(x.m) > int(y.m))
		for i in rows.size():
			rend_box.add_child(_rank_row(i + 1, int(rows[i].id), "这一局 +" + Cfg.money(rows[i].e), Cfg.money(rows[i].m)))
	rend_box.add_child(_spacer_v())
	var note := _l("马上出结果…" if bool(r.final) else "马上进商店…", 12, DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rend_box.add_child(note)


# ───── 整场结束 ─────
func _build_over() -> void:
	var glow := Color(1.0, 0.76, 0.36, 0.42)
	var glow_rect := Rect2(60, -40, 240, 130)
	over = _panel(Rect2(140, 18, 360, 324))
	over.add_child(_halo(glow, glow_rect))
	over_box = _vbox(over, 14)
	solo_over = _panel(Rect2(140, 72, 360, 216))
	solo_over.add_child(_halo(glow, glow_rect))
	solo_over_box = _vbox(solo_over, 14)


func _fill_over() -> void:
	var r: Dictionary = cl.cur.get("res", {})
	var sig := JSON.stringify([r, cl.is_host()])
	if r.is_empty() or _sig.get("over", "") == sig:
		return
	_sig["over"] = sig
	var mode := String(r.mode)
	if mode == "solo":
		_fill_solo_over(int(r.round), int(r.rows[0].tt))
		return
	_clear(over_box)
	var rows: Array = r.rows.duplicate()
	var head := ""
	var note := ""
	var lines := []
	if mode == "race":                        # 分屏：先比过关数，一样再比总共赚的钱
		rows.sort_custom(func(x, y): return int(x.ps) > int(y.ps) or (int(x.ps) == int(y.ps) and int(x.tt) > int(y.tt)))
		var tie: bool = rows.size() > 1 and int(rows[1].ps) == int(rows[0].ps) and int(rows[1].tt) == int(rows[0].tt)
		head = "止步第 %d 关" % int(r.round) if rows.size() == 1 else ("平局" if tie else cl.pname(int(rows[0].id)) + " 赢了")
		for i in rows.size():
			lines.append(_rank_row(i + 1, int(rows[i].id), "过了 %d 关" % int(rows[i].ps), Cfg.money(rows[i].tt)))
		note = "过关数一样的，按总共赚的钱排"
	elif mode == "co":
		var sum := 0
		for x in rows:
			sum += int(x.tt)
		head = "止步第 %d 关" % int(r.round)
		note = "全队一共赚了 %s" % Cfg.money(sum)
		rows.sort_custom(func(x, y): return int(x.tt) > int(y.tt))
		for i in rows.size():
			lines.append(_rank_row(i + 1, int(rows[i].id), "贡献", Cfg.money(rows[i].tt)))
	else:
		rows.sort_custom(func(x, y): return int(x.m) > int(y.m))
		var tie: bool = rows.size() > 1 and int(rows[1].m) == int(rows[0].m)
		head = "平局" if tie else cl.pname(int(rows[0].id)) + " 赢了"
		for i in rows.size():
			lines.append(_rank_row(i + 1, int(rows[i].id), "", Cfg.money(rows[i].m)))
	var title := _title(head, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_box.add_child(title)
	over_box.add_child(Divider.new())
	for l in lines:
		over_box.add_child(l)
	if note != "":
		over_box.add_child(_l(note, 12, DIM))
	# 颁奖：按这一场每个人的数据发，每人一个
	var awards: Array = r.get("awards", [])
	if not awards.is_empty():
		over_box.add_child(Divider.new())
		for a in awards:
			var id := int(a.id)
			var why := _l(String(a.say), 12, DIM)
			why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			why.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			why.clip_text = true
			over_box.add_child(_hbox([_dot(cl.pcolor(id)), _l(cl.pname(id), 12, cl.pcolor(id)), _l("【%s】" % String(a.n), 12, GOLD), why]))
	over_box.add_child(_spacer_v())
	over_box.add_child(Divider.new())
	var btns := [_b("离开", func(): Net.send({"t": "leave"}), "over_leave"), _spacer()]
	if cl.is_host():
		btns.append(_b("回房间再来", func(): Net.send({"t": "again"}), "again", "Primary"))
	else:
		btns.append(_l("等房主开下一场…", 12, DIM))
	over_box.add_child(_hbox(btns))


func _fill_solo_over(round_no: int, total: int) -> void:
	_clear(solo_over_box)
	var record: Dictionary = cl.update_solo_record(round_no, total)
	var head := _title("闯到第 %d 关" % round_no, 28)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	solo_over_box.add_child(head)
	solo_over_box.add_child(Divider.new())
	var earned := _l("本局一共挣了 %s" % Cfg.money(total), 16)
	earned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	solo_over_box.add_child(earned)
	var best := _l("最高纪录　 第 %d 关　%s" % [record.round, Cfg.money(record.total)], 14, DIM)
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	solo_over_box.add_child(best)
	if record.is_new:
		var badge := _title("新纪录！", 18)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		solo_over_box.add_child(badge)
	var again := _b("再来一局", cl.again_solo, "again", "Primary")
	again.custom_minimum_size.y = 40
	again.add_theme_font_size_override("font_size", 18)
	again.tooltip_text = "空格或回车"
	solo_over_box.add_child(again)
	solo_over_box.add_child(_b("回首页", cl.leave_solo, "over_leave"))


func _build_pause() -> void:
	pause_layer = Control.new()
	pause_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pause_layer)
	pause_shade = ColorRect.new()
	pause_shade.color = Color(0.04, 0.025, 0.03, 0.58)
	pause_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_layer.add_child(pause_shade)
	var panel := _panel(Rect2(200, 112, 240, 136))
	panel.reparent(pause_layer, false)
	var v := _vbox(panel, 14)
	pause_title = _title("已暂停")
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pause_title)
	v.add_child(Divider.new())
	pause_actions = VBoxContainer.new()
	v.add_child(pause_actions)
	resume_btn = _b("继续", func(): cl.request_solo_pause(false), "solo_resume", "Primary")
	resume_btn.custom_minimum_size.y = 28
	resume_btn.add_theme_font_size_override("font_size", 16)
	pause_actions.add_child(resume_btn)
	pause_actions.add_child(_b("回首页", _confirm_solo_leave.bind(true), "solo_leave"))
	leave_confirm = VBoxContainer.new()
	v.add_child(leave_confirm)
	var prompt := _l("当前闯关进度会结束", 12, DIM)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leave_confirm.add_child(prompt)
	leave_confirm.add_child(_hbox([_spacer(), _b("取消", _confirm_solo_leave.bind(false), "solo_leave_cancel"),
		_b("确认回首页", cl.leave_solo, "solo_leave_confirm"), _spacer()]))
	_confirm_solo_leave(false)


func _confirm_solo_leave(confirm: bool) -> void:
	pause_title.text = "回首页？" if confirm else "已暂停"
	pause_actions.visible = not confirm
	leave_confirm.visible = confirm


func _input(e: InputEvent) -> void:
	if cl.mode() != "solo" or not (e is InputEventKey and e.pressed and not e.echo):
		return
	var key: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
	if key == KEY_ESCAPE and cl.solo_can_pause():
		if pause_layer.visible and leave_confirm.visible:
			_confirm_solo_leave(false)
		else:
			cl.request_solo_pause(not cl.solo_paused())
		get_viewport().set_input_as_handled()
	elif cl.ph() == "over" and key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		cl.again_solo()
		get_viewport().set_input_as_handled()


# ───── 商店：整屏的场景，不是一块面板 ─────
# 后墙、货架、柜台是着色器画的；掌柜站在柜台后面，货摆在架子上，每件都是大图。
# 指到哪件，货架下面显示它的说明；点一下选中，再买或者还价。每次进店只上架一部分货（服务端定的）。
func _build_shop() -> void:
	shop = Control.new()
	shop.size = size
	shop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shop)
	shop_bg = _screen_bg(preload("res://art/shop_bg.png"))
	shop.add_child(shop_bg)
	# 掌柜：身后一团暖光，人站在柜台后面（脚被柜台挡住）
	shop_halo = _halo(Color(1.0, 0.72, 0.36, 0.55), Rect2(-36, 70, 250, 250))
	shop.add_child(shop_halo)
	shop_face = _pic("res://art/keeper_neutral.png", Vector2(172, 176))
	shop_face.position = Vector2(0, SHOP_FACE_Y)
	shop_face.size = Vector2(172, 176)
	shop.add_child(shop_face)
	# 原图柜台叠到人和光晕前面，遮住落在台面以下的部分。
	shop_counter = _screen_bg(shop_bg.texture)
	shop.add_child(shop_counter)
	# 左上：店名和第几关
	shop_head = _title("矿货商店", 24)
	shop_head.position = Vector2(16, 8)
	shop.add_child(shop_head)
	shop_sub = _l("", 12, DIM)
	shop_sub.position = Vector2(122, 17)
	shop.add_child(shop_sub)
	shop_timer = _l("", 12, DIM)
	shop_timer.position = Vector2(420, 12)
	shop_timer.size = Vector2(204, 14)
	shop_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shop.add_child(shop_timer)
	shop_seats = HBoxContainer.new()
	shop_seats.position = Vector2(230, 9)
	shop.add_child(shop_seats)
	# 掌柜说的话：一块小面板，贴着他的头
	var bubble := Control.new()
	bubble.position = Vector2(180, 40)
	bubble.size = Vector2(444, 38)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bb := ColorRect.new()
	bb.position = Vector2(-PAD, -PAD)
	bb.size = bubble.size + Vector2(PAD, PAD) * 2.0
	bb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	bm.shader = PANEL_SHADER
	bm.set_shader_parameter("size", bb.size)
	bm.set_shader_parameter("pad", PAD)
	bm.set_shader_parameter("ornament", 0.0)
	bb.material = bm
	bubble.add_child(bb)
	shop_say = _l("", 12, CREAM)
	shop_say.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	shop_say.position = Vector2(10, 5)
	shop_say.size = Vector2(424, 30)
	bubble.add_child(shop_say)
	shop.add_child(bubble)
	# 货架上的货（每次进店重新摆）
	shop_items = Control.new()
	shop_items.position = Vector2(220, 96)
	shop_items.size = Vector2(420, 134)
	shop_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop.add_child(shop_items)
	shop_desc = _l("", 12, CREAM)
	shop_desc.position = Vector2(180, 226)
	shop_desc.size = Vector2(444, 14)
	shop_desc.clip_text = true
	shop.add_child(shop_desc)
	# 选中一件以后：买下，或者出个价
	shop_sel_l = _l("", 12, DIM)
	shop_sel_l.custom_minimum_size = Vector2(150, 0)
	buy_btn = _b("买下", _buy_selected, "buy", "Primary")
	offer_edit = _edit("出多少钱", 5, "offer_edit")
	offer_edit.custom_minimum_size = Vector2(70, 0)
	offer_edit.text_submitted.connect(func(_t): _send_offer())
	offer_btn = _b("还价", _send_offer, "offer_btn")
	var act := _hbox([shop_sel_l, buy_btn, _spacer(), _l("或者", 12, DIM), offer_edit, offer_btn])
	act.position = Vector2(180, 246)
	act.size = Vector2(444, 24)
	shop.add_child(act)
	# 柜台上：钱、已有的道具、跟掌柜说话、下井
	shop_bar = ProgressBar.new()
	shop_bar.show_percentage = false
	shop_bar.max_value = 100
	shop_bar.position = Vector2(18, 304)
	shop_bar.size = Vector2(130, 5)
	shop.add_child(shop_bar)
	shop_mood = _l("", 12, CREAM)
	_outline(shop_mood)
	shop_mood.position = Vector2(18, 312)
	shop_mood.size = Vector2(150, 14)
	shop.add_child(shop_mood)
	shop_info = _l("", 12, GOLD)
	_outline(shop_info)
	shop_info.position = Vector2(180, 298)
	shop_info.size = Vector2(310, 14)
	shop.add_child(shop_info)
	shop_own = _l("", 12, CREAM)
	_outline(shop_own)
	shop_own.position = Vector2(180, 313)
	shop_own.size = Vector2(310, 14)
	shop_own.clip_text = true
	shop.add_child(shop_own)
	say_edit = _edit("跟掌柜说句话（带上数字就当出价）", 60, "say_edit")
	say_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	say_edit.text_submitted.connect(func(_t): _send_say())
	var talk := _hbox([say_edit, _b("说", _send_say, "say_btn")])
	talk.position = Vector2(180, 329)
	talk.size = Vector2(310, 22)
	shop.add_child(talk)
	ready_btn = _b("下 井", func(): Net.send({"t": "ready"}), "ready", "Primary")
	ready_btn.position = Vector2(504, 304)
	ready_btn.size = Vector2(120, 46)
	ready_btn.add_theme_font_size_override("font_size", 24)
	shop.add_child(ready_btn)


func _show_toast(t: String) -> void:
	toast_l.text = t
	_toast_t = 3.0


func _pick_seat(i: int) -> void:
	cl.shop_seat = i
	_shop_sel = ""
	refresh()


func _hover_item(k: String) -> void:
	_shop_hover = k
	if shop.visible:
		_fill_shop()


func _pick_item(k: String) -> void:
	_shop_sel = k
	_shop_hover = k
	refresh()


func _shop_pid() -> int:
	var ids: Array = cl.my_ids()
	if ids.is_empty():
		return 0
	return ids[clampi(cl.shop_seat, 0, ids.size() - 1)]


func _buy_selected() -> void:
	if _shop_sel != "":
		Net.send({"t": "buy", "i": _shop_pid(), "k": _shop_sel})


func _send_offer() -> void:
	if _shop_sel != "" and offer_edit.text.is_valid_int():
		Net.send({"t": "haggle", "i": _shop_pid(), "k": _shop_sel, "offer": int(offer_edit.text)})
		offer_edit.text = ""


func _send_say() -> void:
	if say_edit.text.strip_edges() != "":
		Net.send({"t": "say", "i": _shop_pid(), "k": _shop_sel, "text": say_edit.text})
		say_edit.text = ""


# 货架上的一件货：大图、名字、价签，整块都能点
func _make_card(k: String, x: float, index: int) -> Dictionary:
	var card := Control.new()
	card.position = Vector2(x, 0)
	card.size = Vector2(SHOP_CARD_WIDTH, 130)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var halo := _halo(Color(1.0, 0.8, 0.42, 0.0), Rect2(-8, 20, 100, 100))
	card.add_child(halo)
	var icon := _pic("res://art/icon_%s.png" % k, Vector2(64, 64))
	icon.size = Vector2(64, 64)
	var bottom := 56.5 if k == "polish" else 58.5   # 透明边不同，底边按主体像素计算
	icon.position = Vector2(10, SHOP_SHELF_Y - shop_items.position.y - bottom)
	icon.pivot_offset = Vector2(32, bottom)    # 指到货物时，以贴着搁板的底边为轴放大
	card.add_child(icon)
	var name_l := _l(String(Cfg.b().SHOP[k].n), 12, CREAM)
	_outline(name_l, 3)
	name_l.position = Vector2(-11, 24)
	name_l.size = Vector2(106, 14)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(name_l)
	var tag := _l("", 12, BAD)
	_outline(tag, 3)
	tag.position = Vector2(-11, 8)
	tag.size = Vector2(106, 14)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(tag)
	var price := _l("", 12, GOLD)
	_outline(price, 3)
	price.position = Vector2(-21, 116)
	price.size = Vector2(126, 14)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(price)
	var discount := _l("9折", 10, GOLD)
	_outline(discount)
	discount.position = Vector2(60, 117)
	discount.hide()
	card.add_child(discount)
	var hit := Button.new()                       # 看不见的按钮，盖住整件货，接住指到和点击
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.position = Vector2(0, 20)
	hit.size = Vector2(SHOP_CARD_WIDTH, 110)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	hit.pressed.connect(_pick_item.bind(k))
	hit.mouse_entered.connect(_hover_item.bind(k))
	card.add_child(hit)
	reg["item_" + k] = hit
	shop_items.add_child(card)
	return {"card": card, "icon": icon, "halo": halo, "name": name_l, "tag": tag, "price": price, "discount": discount, "born": _t + index * 0.07, "scale": 0.0}


func _fill_shop() -> void:
	var c: Dictionary = cl.cur
	var ids: Array = cl.my_ids()
	var pid := _shop_pid()
	var p: Dictionary = cl.pstate(pid)
	if p.is_empty() or not c.has("pr"):
		return
	var b := Cfg.b()
	shop_sub.text = "第 %d %s打完" % [int(c.rd), "局" if cl.mode() == "vs" else "关"]
	var keys: Array = c.pr.keys()
	# 货架：进一次店摆一次（上架的货变了才重摆）
	var shelf_sig := JSON.stringify([int(c.rd), keys])
	if _sig.get("shelf", "") != shelf_sig:
		_sig["shelf"] = shelf_sig
		for k in _cards.keys():
			reg.erase("item_" + k)
		_clear(shop_items)
		_cards = {}
		var x0 := (shop_items.size.x - SHOP_CARD_WIDTH * keys.size()) * 0.5
		for i in keys.size():
			_cards[keys[i]] = _make_card(keys[i], x0 + SHOP_CARD_WIDTH * i, i)
		_shop_sel = ""
		_shop_hover = ""
	var c_role: int = cl.pcharacter(pid)
	var discounted := Cfg.character(c_role).has("priceMul")
	var sig := JSON.stringify([pid, ids, c_role, c.pr, c.sale, p.get("ak", {}), p.m, p.tl, p.nx, p.r, int(p.out), _shop_sel, _shop_hover, c.get("ng", 0)])
	if _sig.get("shop", "") != sig:
		_sig["shop"] = sig
		_clear(shop_seats)
		if ids.size() > 1:                        # 本机有好几个人：轮流逛，点名字切换
			shop_seats.add_child(_l("现在是谁在买", 12, GOLD))
			for i in ids.size():
				var b2 := _b(cl.pname(ids[i]), _pick_seat.bind(i), "seat_%d" % i, "Small")
				b2.disabled = i == cl.shop_seat
				shop_seats.add_child(b2)
		var info := "手里的钱 " + Cfg.money(p.m)
		if c.has("ng"):
			info += "　　下一关累计要到 " + Cfg.money(c.ng)
		shop_info.text = info
		var own := "已有　"
		for k in b.TOOL_ORDER[cl.mode()]:
			own += "%s×%d　" % [b.SHOP[k].n, int(p.tl.get(k, 0))]
		for k in p.get("nx", {}).keys():
			own += "%s(下一局)　" % b.SHOP[k].n
		shop_own.text = own
		var gone: bool = int(p.out) == 1
		for k in keys:
			var cd: Dictionary = _cards[k]
			var def: Dictionary = b.SHOP[k]
			var listp := int(c.pr[k])
			var ask := int(p.ak.get(k, listp))
			var owned: bool = (not def.has("tool") and p.get("nx", {}).has(k)) or (def.has("tool") and int(p.tl.get(k, 0)) >= int(b.RULES.toolMax))
			var sold: bool = owned and not def.has("tool")
			cd.price.text = "已买" if sold else Cfg.money(ask)
			if not sold and not discounted and ask < listp:
				cd.price.text += "（原 %s）" % Cfg.money(listp)
			cd.discount.visible = discounted and not sold
			cd.tag.text = "特价" if k == String(c.sale) else ""
			cd.name.add_theme_color_override("font_color", GOLD if k == _shop_sel else CREAM)
			cd.icon.modulate = Color(0.45, 0.42, 0.4) if owned else Color(1, 1, 1)
			cd["owned"] = owned
		var sel_ok: bool = _shop_sel != "" and c.pr.has(_shop_sel)
		if sel_ok:
			var sdef: Dictionary = b.SHOP[_shop_sel]
			var sask := int(p.ak.get(_shop_sel, int(c.pr[_shop_sel])))
			shop_sel_l.text = "选中了 %s" % sdef.n
			shop_sel_l.add_theme_color_override("font_color", GOLD)
			buy_btn.text = "买下 %s" % Cfg.money(sask)
			buy_btn.disabled = gone or bool(_cards[_shop_sel].owned) or int(p.m) < sask
		else:
			shop_sel_l.text = "点一件货，再买或者还价"
			shop_sel_l.add_theme_color_override("font_color", DIM)
			buy_btn.text = "买下"
			buy_btn.disabled = true
		offer_btn.disabled = gone or not sel_ok
		offer_edit.editable = sel_ok and not gone
		ready_btn.disabled = int(p.r) == 1
		ready_btn.text = "等其他人…" if int(p.r) == 1 else "下 井"
		ready_btn.add_theme_font_size_override("font_size", 12 if int(p.r) == 1 else 24)
		var show: String = _shop_hover if _shop_hover != "" and c.pr.has(_shop_hover) else _shop_sel
		shop_desc.text = "%s：%s" % [b.SHOP[show].n, b.SHOP[show].d] if show != "" and b.SHOP.has(show) else "今天上架 %d 件。指到一件货上看它有什么用。" % keys.size()
	shop_say.text = "「" + String(p.get("ks", "")) + "」"
	var km := int(p.get("km", 0))
	shop_bar.value = km
	shop_mood.text = "掌柜的耐心 %d" % km if km > 0 else "掌柜不想再讲价了"
	# 同机玩家各自保留表情计时，来回切座位不会重播旧回复。
	for id in ids:
		var state: Dictionary = cl.pstate(id)
		var kn := int(state.get("kn", 0))
		var ka := String(state.get("ka", "idle"))
		var line: Dictionary = _keeper_lines.get(id, {})
		if line.is_empty() or int(line.kn) != kn or String(line.ka) != ka:
			_keeper_lines[id] = {"kn": kn, "ka": ka, "since": _t}
	_update_keeper_face(pid)
	shop_timer.text = "%d 秒后自动下井" % ceili(cl.time_left())


func _update_keeper_face(pid: int) -> void:
	var line: Dictionary = _keeper_lines.get(pid, {})
	var ka := String(line.get("ka", "idle"))
	var age := _t - float(line.get("since", _t))
	var face := "neutral"
	if ka == "bye" or (ka in KEEPER_EXPRESSIONS and age < 3.0):
		_blink_at = -1.0
		face = ka
		if ka in ["happy", "angry"] and floori(age / 0.22) % 2 == 1:
			face += "_move"
	else:
		if _blink_at < 0.0:
			_blink_at = _t + randf_range(3.0, 5.0)
		elif _t >= _blink_at + 0.15:
			_blink_at = maxf(_blink_at, _t - 0.15) + randf_range(3.0, 5.0)
		if ka == "idle" and int(line.get("kn", 0)) > 0 and age < 1.0:
			if floori(age / 0.14) % 2 == 0:
				face = "neutral_talk"
		elif _t >= _blink_at:
			face = "neutral_blink"
	if face != _face:
		_face = face
		if not _keeper_faces.has(face):
			_keeper_faces[face] = load("res://art/keeper_%s.png" % face)
		shop_face.texture = _keeper_faces[face]
		shop_halo.modulate = Color(1.0, 0.42, 0.3, 0.55) if face.begins_with("angry") else Color(1.0, 0.72, 0.36, 0.55)


# ───── 刷新：按当前阶段决定显示哪一块 ─────
func refresh() -> void:
	var ph: String = cl.ph()
	if ph != _last_ph:
		if ph == "over":
			Sfx.play("win")
		if ph != "" and ph != "lobby":
			help.visible = false
		if ph != "play" and ph != "count":
			emo_box.visible = false
		_last_ph = ph
	home.visible = ph == ""
	home_bg.visible = home.visible
	lobby.visible = ph == "lobby" and not help.visible
	hud.visible = ph == "play" or ph == "count"
	var solo: bool = cl.mode() == "solo"
	emo_btn.visible = not solo
	if solo:
		emo_box.visible = false
	var paused: bool = cl.solo_paused()
	pause_btn.visible = cl.solo_can_pause() and not paused
	pause_layer.visible = paused
	resume_btn.disabled = not Net.up
	if not paused:
		_confirm_solo_leave(false)
	rend.visible = ph == "rend"
	shop.visible = ph == "shop"
	over.visible = ph == "over" and not solo
	solo_over.visible = ph == "over" and solo
	if ph != "over":
		_sig.erase("over")
	net_l.visible = not Net.up
	if ph != "shop":
		_shop_sel = ""
		_shop_hover = ""
		_keeper_lines.clear()
		_blink_at = -1.0
		_sig.erase("shop")
		_sig.erase("shelf")
	if lobby.visible:
		_fill_lobby()
	elif hud.visible:
		_fill_hud()
	elif rend.visible:
		_fill_rend()
	elif shop.visible:
		_fill_shop()
	elif ph == "over":
		_fill_over()


func _process(dt: float) -> void:
	_t += dt
	if _toast_t > 0.0:
		_toast_t -= dt
		var a := clampf(_toast_t, 0.0, 1.0)
		toast_l.modulate.a = a
		toast_band.modulate.a = a
		toast_band.visible = toast_l.text != ""
		if _toast_t <= 0.0:
			toast_l.text = ""
			toast_band.visible = false
	if cl.ph() == "count":
		count_l.text = str(maxi(1, ceili(cl.time_left())))
	elif cl.ph() == "shop":
		shop_timer.text = "%d 秒后自动下井" % ceili(cl.time_left())
		_update_keeper_face(_shop_pid())
		var fl := 1.0 + 0.05 * sin(_t * 6.3) + 0.03 * sin(_t * 14.1)        # 店里的灯轻轻摇曳
		shop_halo.modulate.a = 0.5 * fl
		shop_face.position.y = SHOP_FACE_Y + sin(_t * 1.7) * 1.2           # 掌柜站着轻轻晃
		for k in _cards.keys():
			var cd: Dictionary = _cards[k]
			var want := 0.0 if _t < float(cd.born) else (1.22 if k == _shop_hover else (1.12 if k == _shop_sel else 1.0))
			cd.scale = lerpf(float(cd.scale), want, minf(1.0, dt * 12.0))   # 进店时一件件从架子上冒出来；指到的那件变大
			cd.icon.scale = Vector2.ONE * float(cd.scale)
			cd.icon.modulate.a = clampf(float(cd.scale) * 1.5, 0.0, 1.0)
			var glow := 0.75 if k == _shop_hover else (0.5 if k == _shop_sel else 0.0)
			cd.halo.modulate.a = lerpf(cd.halo.modulate.a, glow, minf(1.0, dt * 10.0))


# 自动测试用：当前看得见的按钮、输入框在画面上的中心位置（窗口像素）
func rects() -> Dictionary:
	var out := {}
	var ws: Vector2i = get_tree().root.size
	for k in reg.keys():
		var c: Control = reg[k]
		if is_instance_valid(c) and c.is_visible_in_tree():
			var p: Vector2 = get_viewport().get_final_transform() * (c.get_global_transform_with_canvas() * (c.size / 2.0))
			if p.x >= 0 and p.y >= 0 and p.x < ws.x and p.y < ws.y:      # 跑到画面外的不算看得见
				out[k] = [roundi(p.x), roundi(p.y)]
	return out
