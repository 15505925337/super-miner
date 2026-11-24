# 主场景：把画面拼起来，把联机逻辑、界面接进来，并提供画质开关、截图、测帧率的入口。
#
# 渲染流程（每一层都是一个离屏画布，按从上到下的顺序画）：
#   玩法层（屏幕原始分辨率：手绘底图、矿物、矿工、钩子、点缀的灯光和法线贴图）
#     ─→ 泛光（逐级缩小再放大）─→ 合成 + 调色 + 暗角 ─→ 屏幕
# 分屏对战时，每人的井各画在一块小画布上，再摆进玩法层里各自的小窗。
# 界面和所有的字（scripts/ui.gd）画在最上面，不参与泛光和暗角。
#
# 画面按 640×360 设计。窗口正好是整数倍时用整数倍；不是整数倍时按比例放大到铺满（用户定的）。
#
# 启动参数（桌面版写在 -- 后面，如 -- --q=mid；网页版写在网址问号后面，如 ?q=mid&r=1234）：
#   q=ultra|high|mid|low  画质（电脑默认超高，手机和平板默认高）
#   fx=0             关掉全部光影
#   gi=0|1           超高档全局光照  gib/gis/gir   反光、阴影、分辨率除数
#   gid=0            关掉黑灯时值钱物件的彩光（默认保留）
#   demo=1           固定演示局      dark=1       演示局固定黑灯
#   r=<房间号>       直接进这个房间   name=<名字>   玩家名字
#   server=<地址>    服务端地址（桌面版用，默认 ws://127.0.0.1:8060）
#   tier=0..3        强制显示第几层的画面（只影响显示，看图用）
#   shot=<名字>      截一张图后保存   delay=<秒>    截图前等多少秒（默认 2）
#   bench=<秒>       测这么多秒的帧率  lights=<数量> 把同屏真灯加到这么多盏（压力测试）
#   hud=1            显示左上角的调试文字    test=1   打开自动测试用的接口
#   hookdbg=1        显示每个钩爪的抓取判定圆
#   claw=1..5        强制显示指定等级的钩爪贴图，只影响本机画面
# 调试按键：[ 和 ] 换画质，\ 开关光影，` 显示或隐藏调试文字。
extends Node

const Cfg = preload("res://scripts/cfg.gd")
const WELL := preload("res://scenes/well.tscn")
const CLIENT := preload("res://scripts/client.gd")
const UI := preload("res://scripts/ui.gd")
const GI := preload("res://scripts/gi.gd")
const SH_DOWN := preload("res://shaders/bloom_down.gdshader")
const SH_UP := preload("res://shaders/bloom_up.gdshader")
const SH_FINAL := preload("res://shaders/final.gdshader")
const MAX_LEVELS := 5
const PANE_SIZE := Vector2i(960, 540)     # 分屏小窗的画布大小（640×360 的 1.5 倍，缩放后还清楚）
const DUMP_TIMEOUT_MS := 15000
# 演示局只摆图。各层共享坐标（640×360），大石头放在岩石层左灯和井壁之间。
const DEMO_LAYOUT := {
	"gs": Vector2(78, 136), "gm": Vector2(210, 197), "gl": Vector2(96, 273), "gx": Vector2(422, 235),
	"gem": Vector2(305, 255), "rub": Vector2(485, 157), "bug": Vector2(552, 279), "key": Vector2(358, 165),
	"rl": Vector2(158, 132), "rs": Vector2(475, 310), "tnt": Vector2(556, 192), "bag": Vector2(205, 303),
}

var quality: int = Cfg.Q.ULTRA
var fx_on := true
var k := 1.0                     # 放大倍数：窗口像素 ÷ 设计像素
var off := Vector2.ZERO          # 640×360 的设计区域在窗口里的左上角（窗口像素）
var args := {}
var is_web := false

var client: Node
var ui: Control
var well: Node2D                 # 主画面的那口井（合作、同屏对战、单人）
var panes: Array = []            # 分屏对战的小窗：[{vp, well, rect}]
var split_root: Control
var _split := false
var _pane_of_player := {}        # 玩家 id → 第几个小窗
var world_vp: SubViewport
var down_vps: Array[SubViewport] = []
var down_mats: Array[ShaderMaterial] = []
var up_vps: Array[SubViewport] = []
var up_mats: Array[ShaderMaterial] = []
var final_mat: ShaderMaterial
var label: Label

var _acc_t := 0.0
var _acc_n := 0
var _fps := 0.0
var _frames := 0
var _ready_ms := -1.0
var _bench_left := -1.0
var _bench_wait := 3.0
var _bench_dts := PackedFloat32Array()
var _stat_t := 0.0
var _bloom := -1.0
var _focus_t := 0.0
var _menu := 0.0
var _last_view := {}
var _gi_requested := true
var _gi_active := false
var _gi_divisor := GI.DEFAULT_DIVISOR
var _gi_bounce := GI.DEFAULT_BOUNCE
var _gi_shadow := GI.DEFAULT_SHADOW
var _gi_dark_glow := true
var _demo_view := {}
var _demo_time := 0.0
var _dump_name := ""
var _dump_remaining := 0
var _dump_index := 0
var _dump_step_index := -1
var _dump_last_draw_at := 0


func _ready() -> void:
	is_web = OS.has_feature("web")
	args = Cfg.args()
	var qi := Cfg.Q_NAMES.find(String(args.get("q", "")))
	quality = qi if qi >= 0 else _default_quality()
	fx_on = String(args.get("fx", "1")) != "0"
	_gi_requested = String(args.get("gi", "1")) != "0"
	var divisor := String(args.get("gir", str(GI.DEFAULT_DIVISOR)))
	if divisor in ["1", "2", "4"]:
		_gi_divisor = int(divisor)
	_gi_bounce = _gi_strength("gib", GI.DEFAULT_BOUNCE)
	_gi_shadow = _gi_strength("gis", GI.DEFAULT_SHADOW)
	_gi_dark_glow = args.get("gid", "1") == "1"
	if args.get("demo", "0") == "1":
		_prepare_demo()

	# 分屏用的四块小画布，要排在玩法层前面，保证同一帧里先画好
	for i in int(Cfg.b().MAXP):
		var vp := _make_vp()
		vp.size = PANE_SIZE
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var w: Node2D = WELL.instantiate()
		w.scale = Vector2.ONE * (PANE_SIZE.x / float(Cfg.GW))
		vp.add_child(w)
		add_child(vp)
		w.set_scale_k(PANE_SIZE.x / float(Cfg.GW))
		panes.append({"vp": vp, "well": w, "rect": null})

	world_vp = _make_vp()
	well = WELL.instantiate()
	world_vp.add_child(well)
	var mid := CanvasLayer.new()
	mid.layer = 5
	split_root = Control.new()
	split_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	split_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split_root.visible = false
	var dark := ColorRect.new()
	dark.color = Color(0.09, 0.16, 0.42, 1.0)
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split_root.add_child(dark)
	for p in panes:
		var r := TextureRect.new()
		r.texture = p.vp.get_texture()
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.visible = false
		split_root.add_child(r)
		p.rect = r
	mid.add_child(split_root)
	# 小窗里的开箱弹图直接画到最终玩法画布，按小窗比例采样一次。
	var chest_layer := Node2D.new()
	mid.add_child(chest_layer)
	well.chest_layer = chest_layer
	for p in panes:
		p.well.chest_layer = chest_layer
	world_vp.add_child(mid)
	add_child(world_vp)

	# 泛光：先建好最多 5 级缩小、4 级放大，按画质决定用几级
	for i in MAX_LEVELS:
		var p := _make_pass(SH_DOWN)
		down_vps.append(p[0])
		down_mats.append(p[1])
		add_child(p[0])
	up_vps.resize(MAX_LEVELS - 1)
	up_mats.resize(MAX_LEVELS - 1)
	for i in range(MAX_LEVELS - 2, -1, -1):          # 放大要从最小的一级往回画，所以倒着加进场景
		var p := _make_pass(SH_UP)
		up_vps[i] = p[0]
		up_mats[i] = p[1]
		add_child(p[0])

	var out := CanvasLayer.new()
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	final_mat = ShaderMaterial.new()
	final_mat.shader = SH_FINAL
	final_mat.set_shader_parameter("world_tex", world_vp.get_texture())
	rect.material = final_mat
	out.add_child(rect)
	add_child(out)

	# 联机逻辑和界面
	if _demo_view.is_empty():
		client = CLIENT.new()
		client.main = self
		add_child(client)
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 60
	ui = UI.new()
	ui.cl = client
	ui.demo_only = not _demo_view.is_empty()
	ui_layer.add_child(ui)
	add_child(ui_layer)

	var dbg := CanvasLayer.new()
	dbg.layer = 100
	label = Label.new()
	label.position = Vector2(4, 348)
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 2)
	label.visible = args.get("hud", "0") == "1" and not args.has("shot")
	dbg.add_child(label)
	add_child(dbg)

	get_tree().root.size_changed.connect(_layout)
	_apply()
	if not _demo_view.is_empty() and _demo_view.info.dark > 0.0:
		well.set_dark_now(_demo_view.info.dark)

	if args.has("lights"):
		well.set_light_count(int(args["lights"]))
	if args.has("bench"):
		_bench_left = float(args["bench"])
	if args.has("shot"):
		if not is_web:
			# 截图时关掉垂直同步：窗口被别的窗口挡住时，macOS 会把带垂直同步的窗口降到每秒一两帧，截图要等很久
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_shot(String(args["shot"]))


func _prepare_demo() -> void:
	var tier := clampi(int(args.get("tier", "1")), 0, 3)
	var dark: bool = args.get("dark", "0") == "1"
	var items := []
	for kind in DEMO_LAYOUT:
		var pos: Vector2 = DEMO_LAYOUT[kind] / Cfg.S
		items.append({"id": items.size() + 1, "t": Cfg.type_index(kind), "x": pos.x, "y": pos.y})
	var player := {"id": 1, "c": 0, "x": Cfg.GW * 0.5 / Cfg.S, "ang": 0.0, "len": 104.0, "st": 0, "fz": 0, "sg": 0}
	_demo_view = {
		"players": [player], "fields": [items], "split": false,
		"info": {"tier": tier, "live": true, "paused": false, "dark": float(dark)},
		"hud": {"plate": "演示局 · " + String(Cfg.b().LAYERS[tier]), "plank": "", "clock": "黑灯" if dark else ""},
	}


func _make_vp() -> SubViewport:
	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	return vp


func _make_pass(shader: Shader) -> Array:
	var vp := _make_vp()
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = shader
	r.material = m
	vp.add_child(r)
	return [vp, m]


func _default_quality() -> int:
	if not is_web:
		return Cfg.Q.HIGH if OS.has_feature("mobile") else Cfg.Q.ULTRA
	# iPad 的 Safari 可报告 Macintosh，结合触点数识别其桌面模式。
	var mobile := bool(JavaScriptBridge.eval(
		"/Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent) || " +
		"(/Macintosh/i.test(navigator.userAgent) && navigator.maxTouchPoints > 1)", true))
	return Cfg.Q.HIGH if mobile else Cfg.Q.ULTRA


func _gi_strength(key: String, fallback: float) -> float:
	var value := String(args.get(key, str(fallback)))
	return clampf(float(value), 0.0, 2.0) if value.is_valid_float() else fallback


func _update_gi() -> void:
	_gi_active = quality == Cfg.Q.ULTRA and _gi_requested and fx_on and not _split
	well.set_gi(_gi_active, _gi_divisor, _gi_bounce, _gi_shadow, _gi_dark_glow)


# 按当前画质和光影开关，把各层的参数设好
func _apply() -> void:
	var hi := quality >= Cfg.Q.HIGH
	var low := quality == Cfg.Q.LOW
	well.apply(quality, fx_on)
	for p in panes:
		p.well.apply(quality, fx_on)
	var bloom_on := fx_on and not low
	var levels := 5 if hi else 4
	for i in MAX_LEVELS:
		down_vps[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS if (bloom_on and i < levels) else SubViewport.UPDATE_DISABLED
	for i in MAX_LEVELS - 1:
		up_vps[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS if (bloom_on and i < levels - 1) else SubViewport.UPDATE_DISABLED
	_bloom = -1.0
	_layout()
	_update_gi()
	label.position.y = 4.0 if quality == Cfg.Q.ULTRA and _demo_view.is_empty() else 348.0


# 窗口大小变了（或画质变了）时重新排版
func _layout() -> void:
	var ws: Vector2i = get_tree().root.size
	if ws.x < 2 or ws.y < 2:
		return
	# 放大倍数：能整数倍就用整数倍（像素边缘最干净）；不够整数倍就按比例放大到铺满窗口
	var fit := minf(ws.x / float(Cfg.GW), ws.y / float(Cfg.GH))
	k = floorf(fit) if (fit >= 1.0 and fit - floorf(fit) < 0.04) else fit
	# 窗口比例不是 16:9 时：左右居中、顶边对齐，多出来的地方露出更多底图（不放矿石）
	off = Vector2(floorf((ws.x - Cfg.GW * k) / 2.0), 0.0)
	var hi := quality >= Cfg.Q.HIGH

	world_vp.size = ws
	well.scale = Vector2(k, k)
	well.set_base(off)
	well.set_scale_k(k)
	# 界面和字：让引擎按放大倍数重新生成字形，任何倍数下都清楚
	get_tree().root.content_scale_factor = k
	ui.position = off / k
	var draw_area := Rect2(-ui.position, Vector2(ws) / k)
	well.set_draw_area(draw_area)
	ui.set_draw_area(draw_area)

	# 泛光各级的分辨率：高档从 1/2 开始缩 5 级，中档从 1/4 开始缩 4 级
	var levels := 5 if hi else 4
	var base := 2 if hi else 4
	for i in levels:
		var d := base << i
		down_vps[i].size = Vector2i(maxi(1, ws.x / d), maxi(1, ws.y / d))
		var src_size: Vector2i = ws if i == 0 else down_vps[i - 1].size
		down_mats[i].set_shader_parameter("src", world_vp.get_texture() if i == 0 else down_vps[i - 1].get_texture())
		down_mats[i].set_shader_parameter("src_px", Vector2(1.0 / src_size.x, 1.0 / src_size.y))
		down_mats[i].set_shader_parameter("prefilter", i == 0)
		down_mats[i].set_shader_parameter("threshold", 0.90)
		down_mats[i].set_shader_parameter("knee", 0.08)
		down_mats[i].set_shader_parameter("spread", 2.0 if (i == 0 and base == 4) else 1.0)
	for i in levels - 1:
		up_vps[i].size = down_vps[i].size
		var src_vp: SubViewport = down_vps[levels - 1] if i == levels - 2 else up_vps[i + 1]
		up_mats[i].set_shader_parameter("src", src_vp.get_texture())
		up_mats[i].set_shader_parameter("src_px", Vector2(1.0 / src_vp.size.x, 1.0 / src_vp.size.y))
		up_mats[i].set_shader_parameter("add_tex", down_vps[i].get_texture())
	final_mat.set_shader_parameter("bloom_tex", up_vps[0].get_texture())


# 分屏时每个人的小窗：[x, y, 缩放]，单位是原型的 1280×720 坐标
func _pane_layout(players: Array) -> Array:
	var n := players.size()
	var mine: Array = client.my_ids()
	var me := -1
	for i in n:
		if int(players[i].id) == (mine[0] if mine.size() > 0 else -99):
			me = i
	if mine.size() == 1 and me >= 0 and int(players[me].out) == 0:
		# 一台设备一个人：自己一个大窗，对手在右边排一列小窗
		var out := []
		var j := 0
		for i in n:
			if i == me:
				out.append([0.0, 72.0, 0.8])
			else:
				out.append([1034.0, 72.0 + j * 192.0, 0.192])
				j += 1
		return out
	var res := []
	for i in n:
		# 同一台设备上有好几个人，或者自己已经淘汰在观战：平分屏幕
		res.append([i * 640.0, 180.0, 0.5] if n <= 2 else [(i % 2) * 640.0, (i >> 1) * 360.0, 0.5])
	return res


func well_for_field(fi: int) -> Node2D:
	if _split:
		for id in _pane_of_player.keys():
			var st: Dictionary = client.pstate(id)
			if not st.is_empty() and int(st.fi) == fi:
				return panes[_pane_of_player[id]].well
		return null
	return well


# 所有井一起震一下（塌方、金矿雨）
func shake_all(amount: float) -> void:
	well.shake(amount)
	for p in panes:
		p.well.shake(amount)


func well_for_player(id: int) -> Node2D:
	if _split:
		return panes[_pane_of_player[id]].well if _pane_of_player.has(id) else null
	return well


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_BRACKETLEFT:
				quality = maxi(Cfg.Q.LOW, quality - 1)
				_apply()
			KEY_BRACKETRIGHT:
				quality = mini(Cfg.Q.ULTRA, quality + 1)
				_apply()
			KEY_BACKSLASH:
				fx_on = not fx_on
				_apply()
			KEY_QUOTELEFT:
				label.visible = not label.visible


func _process(dt: float) -> void:
	if _dump_remaining > 0:
		_update_frame_dump()
	var visual_dt := Cfg.visual_delta(dt)
	_frames += 1
	if _frames == 3 and is_web:
		_ready_ms = float(JavaScriptBridge.eval("performance.now()", true))

	# 这一帧每口井画什么，字交给界面层画
	# 顿帧：自己刚钩中东西的那几十毫秒，画面停在上一帧不动
	var view: Dictionary = _last_view
	if not _demo_view.is_empty():
		_demo_time = fmod(_demo_time + visual_dt, TAU / 1.4)
		_demo_view.players[0].ang = 0.99 * sin(_demo_time * 1.4)
		view = _demo_view
	elif Cfg.dumping_frames or _last_view.is_empty() or float(Time.get_ticks_msec()) >= client.hitstop_until:
		view = client.build_view()
		_last_view = view
	var players: Array = view.players
	var huds := []
	if view.split != _split:
		well.clear_chest_popups()
		_split = view.split
		split_root.visible = _split
		well.visible = not _split
		_update_gi()
		for p in panes:
			p.well.clear_chest_popups()
			p.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			p.rect.visible = false
	if _split:
		var lay := _pane_layout(players)
		var u: float = Cfg.S * k
		_pane_of_player = {}
		for i in panes.size():
			var p: Dictionary = panes[i]
			var on := i < players.size()
			p.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
			p.rect.visible = on
			if not on:
				p.well.clear_chest_popups()
				continue
			var pl: Dictionary = players[i]
			_pane_of_player[int(pl.id)] = i
			var sc: float = float(lay[i][2])
			p.rect.position = off + Vector2(lay[i][0], lay[i][1]) * u
			p.rect.size = Vector2(1280, 720) * sc * u
			var fi := int(pl.fi)
			p.well.set_view(view.fields[fi] if fi < view.fields.size() else [], [pl], view.info)
			var h: Dictionary = view.hud.duplicate()
			h.origin = Vector2(lay[i][0], lay[i][1]) * Cfg.S
			h.scale = sc
			h.plank = "第 %d 关　%s / %s" % [int(client.cur.rd), Cfg.money(pl.m), Cfg.money(client.cur.get("tg", 0))]
			h.veil = "淘汰" if int(pl.out) == 1 else ""
			h.note = String(view.hud.note) if client.seat_of(int(pl.id)) == 0 else ""
			h.players = [pl]
			if p.well.has_chest_popups():
				h.chest_well = p.well
				h.to_screen = Transform2D(0.0, p.rect.size / Vector2(p.vp.size), 0.0, p.rect.position)
			huds.append(h)
	else:
		well.process_mode = Node.PROCESS_MODE_DISABLED if view.info.paused else Node.PROCESS_MODE_INHERIT
		well.set_view(view.fields[0], players, view.info)
		var h: Dictionary = view.hud.duplicate()
		h.origin = Vector2.ZERO
		h.scale = 1.0
		h.veil = ""
		h.players = players if view.info.live and _demo_view.is_empty() else []
		if well.has_chest_popups():
			h.chest_well = well
			h.to_screen = Transform2D.IDENTITY
		huds.append(h)
	ui.draw_hud(huds, _split)
	for h in huds:
		if h.has("chest_well"):
			var name_bounds: Array[Rect2] = []
			for box in h.name_bounds:
				name_bounds.append(Rect2(off + box.position * k, box.size * k))
			# 井的位置在本帧震动后确定，绘制前再对齐台沿。
			h.chest_well.layout_chest_popups.call_deferred(h.to_screen, name_bounds)
	# 有面板开着时，把后面的游戏画面虚化、压暗（渐入渐出）
	_menu = move_toward(_menu, 1.0 if ui.menu_open() else 0.0, visual_dt * 4.0)
	final_mat.set_shader_parameter("menu", _menu if fx_on else 0.0)
	final_mat.set_shader_parameter("menu_blur", 5.0 * k)
	var want_bloom: float = well.bloom if not _split else panes[0].well.bloom
	if quality == Cfg.Q.LOW or not fx_on:
		want_bloom = 0.0
	if want_bloom != _bloom:
		_bloom = want_bloom
		final_mat.set_shader_parameter("bloom_strength", _bloom)

	_acc_t += dt
	_acc_n += 1
	if _acc_t >= 0.5:
		_fps = _acc_n / _acc_t
		_acc_t = 0.0
		_acc_n = 0
		var ws: Vector2i = get_tree().root.size
		label.text = "%s%s  %d fps  %dx%d  x%.2f  lights %d" % [Cfg.Q_NAMES[quality].to_upper(), "" if fx_on else " (FX OFF)", roundi(_fps), ws.x, ws.y, k, well.light_count()]
	# 网页版：键盘焦点可能被页面上别的地方拿走（比如点到了游戏画面以外），那样按键就进不来了。
	# 只要游戏里没有输入框被选中，就把焦点拿回游戏画面
	_focus_t += dt
	if is_web and _focus_t >= 0.3:
		_focus_t = 0.0
		if not (get_viewport().gui_get_focus_owner() is LineEdit):
			JavaScriptBridge.eval("(function(){var c=document.querySelector('canvas'),a=document.activeElement;if(c&&a!==c&&!(a&&a.isContentEditable))c.focus()})()", true)
	_stat_t += dt
	if is_web and _stat_t >= (0.2 if args.has("test") else 1.0):
		_stat_t = 0.0
		JavaScriptBridge.eval("window.dmStats=%s" % JSON.stringify(_stats()), true)
		if args.has("test") and (client != null or args.get("test") == "1"):
			_test_hooks()
	if _bench_left > 0.0:
		if _bench_wait > 0.0:
			_bench_wait -= dt
		else:
			_bench_dts.append(dt)
			_bench_left -= dt
			if _bench_left <= 0.0:
				_bench_done()


func _stats() -> Dictionary:
	var ws: Vector2i = get_tree().root.size
	return {
		"q": Cfg.Q_NAMES[quality], "fx": fx_on, "fps": snappedf(_fps, 0.1), "w": ws.x, "h": ws.y, "k": snappedf(k, 0.001),
		"gi": int(_gi_active), "gir": _gi_divisor if quality == Cfg.Q.ULTRA else 0,
		"gid": int(_gi_active and _gi_dark_glow), "demo": int(not _demo_view.is_empty()),
		"lights": well.light_count(), "ready_ms": roundi(_ready_ms), "gpu": RenderingServer.get_video_adapter_name(), "frames": _frames,
	}


# 自动测试用：把对局的要点公布给网页。
func _test_state() -> Dictionary:
	var c: Dictionary = client.cur
	var ps := []
	for p in client.meta.get("players", []):
		var st: Dictionary = client.pstate(int(p.id))
		ps.append({"id": int(p.id), "name": p.name, "on": p.on, "bot": p.bot, "m": int(st.get("m", 0)), "e": int(st.get("e", 0)), "s": int(st.get("s", 0)), "a": st.get("a", 0),
			"cb": int(st.get("cb", 0)), "gc": st.get("gc", -1), "gn": int(st.get("gn", -1)), "hv": st.get("hv", -1), "fi": int(st.get("fi", 0)),
			"out": int(st.get("out", 0)), "ps": int(st.get("ps", 0)), "r": int(st.get("r", 0)), "tl": st.get("tl", {}), "nx": st.get("nx", {}), "ks": st.get("ks", ""), "km": st.get("km", 0), "ak": st.get("ak", {})})
	return {
		"up": Net.up, "ph": client.ph(), "code": client.meta.get("code", ""), "mode": client.meta.get("mode", ""), "host": client.is_host(), "you": client.my_ids(),
		"rd": int(c.get("rd", 0)), "dp": int(c.get("dp", 0)), "tl": float(c.get("tl", 0)), "tg": c.get("tg", 0), "te": c.get("te", 0), "players": ps, "toast": client.last_toast,
		"paused": bool(c.get("paused", false)), "res": c.get("res", {}), "pr": c.get("pr", {}), "split": _split, "items": c.F[0].size() if c.has("F") else -1, "rects": ui.rects(), "k": snappedf(k, 0.001),
		"keys": client.keys_seen, "fires": client.fires_sent, "focus": _focus_name(),
		"ev": c.get("ev", []), "ky": int(c.get("ky", 0)), "emo": client.emo_seen, "evn": client.ev_seen, "sfx": Sfx.played, "muted": Sfx.muted, "fk": _field_kinds(c),
	}


func _test_hooks() -> void:
	var state := {}
	if client != null:
		state = _test_state()
		client.auto_gx = bool(JavaScriptBridge.eval("!!window.dmAutoGx", true))
		client.auto = bool(JavaScriptBridge.eval("!!window.dmAuto", true))
	var q = JavaScriptBridge.eval("""(() => {
		const dump = window.dmState?.dump;
		window.dmState = %s;
		if (dump) window.dmState.dump = dump;
		const q = window.dmQ || [];
		window.dmQ = [];
		return JSON.stringify(q);
	})()""" % JSON.stringify(state), true)
	var commands = JSON.parse_string(q) if q is String and q.length() > 2 else null
	if not commands is Array:
		return
	var local_enabled: bool = args.get("test") == "1"
	for cmd in commands:
		if not cmd is Dictionary:
			continue
		match cmd.get("t"):
			"frameDump":
				if local_enabled:
					_start_frame_dump(cmd)
			"showChest":
				if not local_enabled or client == null or client.ph() != "play":
					continue
				var id := int(cmd.get("i", -1))
				var w := well_for_player(id)
				if w != null:
					w.fx_chest(id)
			_:
				if client != null:
					Net.send(cmd)


func _start_frame_dump(cmd: Dictionary) -> void:
	var count = cmd.get("n", 0)
	var dump_name = cmd.get("name", "frame")
	if not dump_name is String or not (count is int or count is float):
		return
	if count < 1 or count > 9007199254740991 or count != floorf(count):
		return
	if _dump_remaining > 0 or bool(JavaScriptBridge.eval("!!(window.dmState.dump && !window.dmState.dump.done)", true)):
		return
	_dump_name = dump_name
	_dump_remaining = int(count)
	_dump_index = 0
	JavaScriptBridge.eval("window.dmState.dump={name:%s,remaining:%d,pending:0,failed:0,done:false}" % [JSON.stringify(_dump_name), _dump_remaining], true)


func _update_frame_dump() -> void:
	if not Cfg.dumping_frames:
		# 在下一次 _process 开头切换，整帧用同一个步长。
		_begin_dump_frames()
	var missed := _expire_dump_if_stalled(Time.get_ticks_msec())
	if missed > 0:
		JavaScriptBridge.eval("""(() => {
			const dump = window.dmState.dump;
			dump.remaining = 0;
			dump.failed += %d;
			dump.error = 'render_timeout';
			dump.done = dump.pending === 0;
		})()""" % missed, true)
		return
	# 等上一帧画完再推进，停绘期间的 _process 不累计动画时间。
	Cfg.dump_delta = 0.0
	if _dump_step_index != _dump_index:
		_dump_step_index = _dump_index
		Cfg.dump_delta = Cfg.DUMP_STEP
		if client != null:
			client.step_dump_view()


func _begin_dump_frames() -> void:
	Cfg.dumping_frames = true
	_dump_last_draw_at = Time.get_ticks_msec()
	_dump_step_index = -1
	if client != null:
		client.begin_dump_view(_dump_remaining)
	RenderingServer.frame_post_draw.connect(_dump_frame)


func _dump_frame() -> void:
	_dump_last_draw_at = Time.get_ticks_msec()
	var name_in_file := "dump_%s_%03d_f%d" % [_dump_name, _dump_index, Engine.get_frames_drawn()]
	var img := get_viewport().get_texture().get_image()
	_dump_index += 1
	_dump_remaining -= 1
	if _dump_remaining == 0:
		_end_dump_frames()
	# 截取下一帧不等上传，所有请求结算后才标记完成。
	var js := """(() => {
		const dump = window.dmState.dump;
		dump.remaining = %d;
		dump.pending++;
		const controller = new AbortController();
		let timer;
		const deadline = new Promise((_, reject) => {
			timer = setTimeout(() => { controller.abort(); reject(new Error('upload_timeout')); }, %d);
		});
		const upload = Promise.resolve().then(() => %s);
		Promise.race([upload, deadline]).then(response => { if (!response.ok) dump.failed++; })
			.catch(() => { dump.failed++; })
			.finally(() => {
				clearTimeout(timer);
				dump.pending--;
				dump.done = dump.remaining === 0 && dump.pending === 0;
			});
	})()""" % [_dump_remaining, DUMP_TIMEOUT_MS, _shot_request(name_in_file, img, "controller.signal")]
	JavaScriptBridge.eval(js, true)


func _expire_dump_if_stalled(now: int) -> int:
	if _dump_remaining == 0 or now - _dump_last_draw_at < DUMP_TIMEOUT_MS:
		return 0
	var missed := _dump_remaining
	_end_dump_frames()
	return missed


func _end_dump_frames() -> void:
	if RenderingServer.frame_post_draw.is_connected(_dump_frame):
		RenderingServer.frame_post_draw.disconnect(_dump_frame)
	_dump_remaining = 0
	_dump_last_draw_at = 0
	Cfg.dumping_frames = false
	Cfg.dump_delta = 0.0
	if is_instance_valid(client):
		client.end_dump_view()


func _exit_tree() -> void:
	if Cfg.dumping_frames:
		_end_dump_frames()


func _shot_request(shot_name: String, img: Image, abort_signal := "") -> String:
	if img == null or img.is_empty():
		return "Promise.reject()"
	var png := img.save_png_to_buffer()
	if png.is_empty():
		return "Promise.reject()"
	var b64 := Marshalls.raw_to_base64(png)
	var url := JSON.stringify("/__shot?name=" + shot_name.uri_encode())
	var signal_option := "" if abort_signal.is_empty() else ",signal:" + abort_signal
	return "fetch(%s,{method:'POST',body:Uint8Array.from(atob('%s'),c=>c.charCodeAt(0))%s})" % [url, b64, signal_option]


# 每口井里各种东西有几个（联调脚本用它确认"井里多了石头""掉了金块"）
func _field_kinds(c: Dictionary) -> Array:
	var out := []
	for arr in c.get("F", []):
		var d := {}
		for it in arr:
			var kk := Cfg.type_key(int(it[1]))
			d[kk] = int(d.get(kk, 0)) + 1
		out.append(d)
	return out


func _focus_name() -> String:
	var f := get_viewport().gui_get_focus_owner()
	if f == null:
		return ""
	for key in ui.reg.keys():
		if ui.reg[key] == f:
			return key
	return f.get_class()


func _bench_done() -> void:
	var dts := Array(_bench_dts)
	dts.sort()
	var n := dts.size()
	var sum := 0.0
	for d in dts:
		sum += d
	var r := _stats()
	r["bench_frames"] = n
	r["bench_secs"] = snappedf(sum, 0.01)
	r["fps_avg"] = snappedf(n / sum, 0.1)
	r["ms_median"] = snappedf(dts[n / 2] * 1000.0, 0.01)
	r["ms_p99"] = snappedf(dts[mini(n - 1, int(n * 0.99))] * 1000.0, 0.01)
	r["ms_max"] = snappedf(dts[n - 1] * 1000.0, 0.01)
	var js := JSON.stringify(r)
	print("BENCH " + js)
	if is_web:
		JavaScriptBridge.eval("window.dmBench=%s;fetch('/__stats?name=%s',{method:'POST',body:JSON.stringify(window.dmBench)}).catch(()=>{})" % [js, String(args.get("name", "bench"))], true)
	elif not args.has("shot"):
		get_tree().quit()


# 截图：等画面稳定后把最终画面存成 PNG。桌面版直接写到 shots/，网页版发给服务端保存
func _shot(shot_name: String) -> void:
	await get_tree().create_timer(float(args.get("delay", "2"))).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if is_web:
		JavaScriptBridge.eval("%s.then(()=>{window.dmShotDone=%s}).catch(()=>{})" % [_shot_request(shot_name, img), JSON.stringify(shot_name)], true)
	else:
		var shot_dir := ProjectSettings.globalize_path("res://shots")
		var err := DirAccess.make_dir_recursive_absolute(shot_dir)
		if err == OK:
			err = img.save_png(shot_dir.path_join(shot_name + ".png"))
		if err == OK:
			print("SHOT " + shot_name)
		else:
			push_error("截图保存失败：" + error_string(err))
		get_tree().quit(int(err != OK))
