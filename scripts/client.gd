# 客户端的对局逻辑：收服务端的状态，在最近两帧之间插值，算出每口井该画什么；把玩家的按键发给服务端。
# 规则全在服务端算，这里不做任何判定。
extends Node

const Cfg = preload("res://scripts/cfg.gd")

signal changed                   # 房间名单或对局状态变了，界面要刷新
signal toast(text: String)

var meta := {}                   # 房间名单；空 = 不在房间里
var prev := {}                   # 上一帧状态
var cur := {}                    # 最新一帧状态
var view_ang := {}               # 玩家 id → 屏幕上此刻画出来的角度（放钩时发给服务端做补偿）
var shop_seat := 0               # 商店里正在操作的是本机第几个人
var main: Node                   # 主场景，用来找到某口井放特效
var last_toast := ""
var keys_seen := 0               # 收到了几次放钩按键（排查按键问题用）
var fires_sent := 0              # 发出了几次放钩
var auto := false                 # 测试用：自动瞄准放钩（只有带 test=1 打开页面、并由联调脚本打开时才生效）
var auto_gx := false              # 测试用：自动瞄准时主动去钩巨型金块（合作里要一个人先钩住、另一个人来帮）
var _auto_ghost := 0.0
var _miner_reactions := {}      # 玩家 id → 中炸、扔炸药、收获各自的开始时间（毫秒）
var _miner_motion := {}         # 玩家 id → 上次显示的帧、绞盘的播放进度
var _t := 0.0
var _emo := {}                   # 玩家 id → {text, t}：刚喊的话，在头上显示 3 秒
var emo_seen := 0                # 一共看到几次喊话（联调脚本用）
var ev_seen := {}                # 每种事件各收到几次（联调脚本用它确认"丢石头""拉不动"这些真的发生过）
var _pred := {}                  # 玩家 id → {t, ang}：本机刚按了放钩，服务端还没回话，先在本地把钩子画出去
var hitstop_until := 0.0         # 顿帧：在这个时刻（毫秒）之前画面停住不动
var _tab_hidden := false
var _visibility_callback: JavaScriptObject
var _solo_best := {"round": 0, "total": 0}
var solo_character := 0
var _tick_s := -1                # 最后几秒的滴答声响到第几秒了

const EMOTE_KEYS := [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N]
const EMOTE_KEY_NAMES := ["Z", "X", "C", "V", "B", "N"]

const CRANK := ["crank1", "crank2", "crank3", "crank4"]
const STRAIN := ["pull", "pull2"]
const HEAVY_WEIGHT := 5.0

const DEMO_ITEMS := [
	{"id": -1, "t": 0, "x": 300, "y": 330, "by": 0}, {"id": -2, "t": 2, "x": 900, "y": 470, "by": 0}, {"id": -3, "t": 4, "x": 600, "y": 580, "by": 0},
	{"id": -4, "t": 5, "x": 230, "y": 600, "by": 0}, {"id": -5, "t": 1, "x": 1040, "y": 310, "by": 0}, {"id": -6, "t": 6, "x": 460, "y": 450, "by": 0},
	{"id": -7, "t": 7, "x": 760, "y": 360, "by": 0}, {"id": -8, "t": 9, "x": 1100, "y": 600, "by": 0}, {"id": -9, "t": 3, "x": 130, "y": 420, "by": 0},
]


func _ready() -> void:
	Net.got_meta.connect(_on_meta)
	Net.got_state.connect(_on_state)
	Net.got_err.connect(_on_err)
	Net.got_left.connect(_on_left)
	Net.link_changed.connect(func(_up): changed.emit())
	if OS.has_feature("web"):
		var saved = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('dj_solo_character')}catch(e){return null}})()", true)
		if saved is String and saved.is_valid_int():
			var c := int(saved)
			if c >= 0 and c < Cfg.b().CHARACTERS.size():
				solo_character = c
		var document := JavaScriptBridge.get_interface("document")
		_visibility_callback = JavaScriptBridge.create_callback(_on_visibility_changed)
		document.addEventListener("visibilitychange", _visibility_callback)
		_on_visibility_changed([])


func _exit_tree() -> void:
	if _visibility_callback != null:
		JavaScriptBridge.get_interface("document").removeEventListener("visibilitychange", _visibility_callback)


func _on_visibility_changed(_args: Array) -> void:
	_tab_hidden = bool(JavaScriptBridge.get_interface("document").hidden)
	if _tab_hidden:
		request_solo_pause(true)


# ───── 小工具 ─────
func ph() -> String:
	if meta.is_empty():
		return ""
	if cur.is_empty():
		return "" if mode() == "solo" else "lobby"
	return String(cur.ph)


func mode() -> String:
	return String(meta.get("mode", "vs"))


func solo_can_pause() -> bool:
	return mode() == "solo" and ph() in ["count", "play"]


func solo_paused() -> bool:
	return solo_can_pause() and (bool(cur.get("paused", false)) or not Net.up)


func request_solo_pause(paused: bool) -> void:
	if solo_can_pause():
		Net.send({"t": "pause", "paused": paused})


func leave_solo() -> void:
	if Net.up:
		Net.send({"t": "leave"})
	else:
		_reset()


func again_solo() -> void:
	if mode() == "solo" and ph() == "over":
		Net.send({"t": "again"})


func set_solo_character(c: int) -> void:
	solo_character = c
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('dj_solo_character', '%d')}catch(e){}" % c, true)


func update_solo_record(round_no: int, total: int) -> Dictionary:
	var web := OS.has_feature("web")
	if web:
		var saved = JavaScriptBridge.eval("""(function(){
			try {
				var r = JSON.parse(localStorage.getItem('dj_solo_best'));
				if (r && Number.isSafeInteger(r.round) && r.round > 0 &&
				    Number.isSafeInteger(r.total) && r.total >= 0) return JSON.stringify(r);
			} catch (e) {}
			return '{}';
		})()""", true)
		var record: Dictionary = JSON.parse_string(String(saved))
		if _beats_solo_record(int(record.get("round", 0)), int(record.get("total", 0))):
			_solo_best = record
	var is_new := _beats_solo_record(round_no, total)
	if is_new:
		_solo_best = {"round": round_no, "total": total}
		if web:
			JavaScriptBridge.eval("try{localStorage.setItem('dj_solo_best',%s)}catch(e){}" % JSON.stringify(JSON.stringify(_solo_best)), true)
	return {"round": int(_solo_best.round), "total": int(_solo_best.total), "is_new": is_new}


func _beats_solo_record(round_no: int, total: int) -> bool:
	return round_no > int(_solo_best.round) or (round_no == int(_solo_best.round) and total > int(_solo_best.total))


func my_ids() -> Array:
	var out := []
	for v in meta.get("you", []):
		out.append(int(v))
	return out


func seat_of(id: int) -> int:
	return my_ids().find(id)


func pmeta(id: int) -> Dictionary:
	for p in meta.get("players", []):
		if int(p.id) == id:
			return p
	return {}


func pname(id: int) -> String:
	return String(pmeta(id).get("name", "?"))


func pcolor(id: int) -> Color:
	return Cfg.COLORS[pcharacter(id)]


func pcharacter(id: int) -> int:
	var c := int(pmeta(id).get("c", 0))
	return c if ph() == "lobby" else int(pstate(id).get("c", c))


func pstate(id: int) -> Dictionary:
	return cur.get("pm", {}).get(id, {})


func is_host() -> bool:
	return bool(meta.get("host", false))


func say(text: String) -> void:
	last_toast = text
	toast.emit(text)


# ───── 服务端来的消息 ─────
func _on_meta(m: Dictionary) -> void:
	if meta.is_empty() or String(meta.get("code", "")) != String(m.code):
		prev = {}
		cur = {}
		_miner_reactions.clear()
		_miner_motion.clear()
		shop_seat = 0
	meta = m
	Net.set_url_room(String(m.code))
	changed.emit()


func _on_state(m: Dictionary) -> void:
	if meta.is_empty():
		return
	m["_t"] = float(Time.get_ticks_msec())
	var pm := {}
	for p in m.P:
		pm[int(p.i)] = p
	m["pm"] = pm
	if m.has("F"):
		var fm := []
		for arr in m.F:
			var d := {}
			for c in arr:
				d[int(c[0])] = c
			fm.append(d)
		m["fm"] = fm
	prev = cur
	cur = m
	if solo_paused():
		_pred.clear()
	if _tab_hidden and not solo_paused() and String(prev.get("ph", "")) != ph():
		request_solo_pause(true)
	if not String(m.ph) in ["count", "play"]:
		_miner_reactions.clear()
		_miner_motion.clear()
	for e in m.get("E", []):
		_on_event(e)
	changed.emit()


func _on_err(m: Dictionary) -> void:
	say(String(m.get("msg", "出错了")))
	if int(m.get("gone", 0)) == 1:
		_reset()


func _on_left(m: Dictionary) -> void:
	if m.has("msg"):
		say(String(m.msg))
	_reset()


func _reset() -> void:
	meta = {}
	prev = {}
	cur = {}
	_miner_reactions.clear()
	_miner_motion.clear()
	_pred.clear()
	Net.set_url_room("")
	changed.emit()


func _on_event(e: Dictionary) -> void:
	if main == null:
		return
	var s: float = Cfg.S
	var now := float(Time.get_ticks_msec())
	var fun: Dictionary = Cfg.b().FUN
	var en := String(e.get("e", ""))
	ev_seen[en] = int(ev_seen.get(en, 0)) + 1
	if en == "atk" and int(e.get("g", 0)) == 1:
		ev_seen["ghost"] = int(ev_seen.get("ghost", 0)) + 1
	match en:
		"go":
			Sfx.play("go")
		"fire":
			if seat_of(int(e.p)) < 0:                    # 自己放钩的声音在按键那一刻就响过了
				Sfx.play("fire", 1.0, -9.0)
		"miss":
			if seat_of(int(e.p)) >= 0:
				Sfx.play("miss")
		"grab":
			var kind := String(e.get("k", ""))
			var rock: bool = kind in ["rs", "rl"]
			var mine := seat_of(int(e.p)) >= 0
			var well: Node2D = main.well_for_field(int(e.get("f", 0)))
			if well != null:
				var p := pstate(int(e.p))
				var tip := Vector2(float(e.x), float(e.y))
				if not p.is_empty():
					var ang := float(p.a)
					tip = Vector2(float(p.x), float(Cfg.b().Y0)) + Vector2(sin(ang), cos(ang)) * float(p.l)
				well.fx_grab(tip * s, kind)
			if mine:                                     # 自己钩中：画面顿一下，值钱的顿得久一点
				hitstop_until = now + (45.0 if rock else 75.0)
				if well != null:
					well.shake(0.8 if rock else 1.2)
			Sfx.play("thud" if rock else "grab", 1.0, 0.0 if mine else -8.0)
		"get":
			var id := int(e.p)
			var well: Node2D = main.well_for_player(id)
			var v := int(e.v)
			var mine := seat_of(id) >= 0
			var kind := String(e.get("k", ""))
			if kind in ["rs", "rl"]:
				_react(id, "sad", now)
			elif v > 0:
				_react(id, "happy", now)
			if well != null:
				var label := String(e.get("s", ""))
				well.fx_text(well.miner_pos(id) + Vector2(0, -34), ("+" + Cfg.money(v) if v > 0 else "") + (" " + label if label != "" else ""), pcolor(id) if v > 0 else Color(0.8, 0.8, 0.8), 1.5 if v >= 500 else 1.0)
				if v >= 500:                             # 大钱：矿工身上闪一下金光，画面轻轻震一下
					well.fx_flash(well.miner_pos(id), 60.0, Color(1.0, 0.85, 0.4))
					if mine:
						well.shake(2.0)
				if kind == "chest" and mode() == "co":
					well.fx_chest(id)
			if v >= 500:
				Sfx.play("big", 1.0, 0.0 if mine else -6.0)
			elif v > 0:
				Sfx.play("coin", 0.85 + minf(0.5, v / 800.0), 0.0 if mine else -8.0)
			elif mine:
				Sfx.play("miss")
		"boom":
			if e.has("p"):
				match String(e.get("src", "")):
					"tnt":
						_react(int(e.p), "hit", now)
					"d":
						_react(int(e.p), "throw", now)
			var well: Node2D = main.well_for_field(int(e.get("f", 0)))
			if well != null:
				well.fx_boom(Vector2(float(e.x), float(e.y)) * s, float(e.r) * s)
				well.shake(3.5)
			Sfx.play("boom")
		"ast":
			var well: Node2D = main.well_for_field(int(e.get("f", 0)))
			if well != null:
				well.fx_text(Vector2(float(e.x), float(e.y)) * s, "合拉！", Color(0.6, 1, 0.7))
			Sfx.play("grab")
		"cut":
			var well: Node2D = main.well_for_field(int(e.get("f", 0)))
			if well != null:
				well.fx_text(Vector2(float(e.x), float(e.y)) * s, "绳子被剪断！", Color(1, 0.5, 0.45))
			say(String(e.get("by", "")) + " 用了剪刀")
			Sfx.play("frz", 1.4)
		"frz":
			say(String(e.get("by", "")) + " 用了冰冻，对手冻住 3 秒")
			Sfx.play("frz")
		"time":
			say(String(e.get("by", "")) + " 用了沙漏，本关 +8 秒")
			Sfx.play("buy")
		"atk":                                           # 分屏：有人往别人井里丢了一块石头
			var well: Node2D = main.well_for_field(int(e.get("f", 0)))
			var hit_me := seat_of(int(e.to)) >= 0
			if well != null:
				well.fx_text(Vector2(float(e.x), float(e.y) - 30.0) * s, pname(int(e.by)) + " 丢来一块石头", Color(1, 0.6, 0.45))
				if hit_me:
					well.shake(2.5)
			say("%s%s往 %s 井里丢了一块石头" % [pname(int(e.by)), "（已淘汰）" if int(e.get("g", 0)) == 1 else " 连续钩中，", pname(int(e.to))])
			Sfx.play("atk", 1.0, 0.0 if (hit_me or seat_of(int(e.by)) >= 0) else -6.0)
		"heavy":                                         # 合作：巨型金块一个人拉不动
			var well: Node2D = main.well_for_field(int(e.get("f", 0)))
			if well != null:
				well.fx_text(Vector2(float(e.x), float(e.y) - 40.0) * s, "太重了！要人帮忙", Color(1, 0.85, 0.4), 1.3)
			say("%s 钩住了巨型金块，一个人拉不动，快去帮忙" % pname(int(e.p)))
			Sfx.play("heavy")
		"lock":                                          # 合作：宝箱打不开
			var well: Node2D = main.well_for_player(int(e.p))
			if well != null:
				well.fx_text(well.miner_pos(int(e.p)) + Vector2(0, -34), String(e.get("s", "锁着")), Color(1, 0.6, 0.45))
			Sfx.play("lock")
		"emo":
			var k := int(e.k)
			var list: Array = fun.emotes
			if k >= 0 and k < list.size():
				_emo[int(e.p)] = {"text": String(list[k]), "t": now}
				emo_seen += 1
				if ph() != "play" and ph() != "count":   # 不在井上的时候（结算、商店），喊的话显示在提示条里
					say("%s：%s" % [pname(int(e.p)), String(list[k])])
				Sfx.play("emo")
		"event":
			var k := String(e.k)
			if int(e.on) == 1:
				say(String({"rain": "金矿雨来了！", "cave": "塌方了！掉下来一堆石头", "dark": "灯灭了！只看得清钩灯照到的地方"}.get(k, "")))
				Sfx.play("boom" if k == "cave" else "event")
				main.shake_all(4.0 if k == "cave" else 1.5)
			else:
				say("灯亮了")
				Sfx.play("go")


func _react(id: int, pose: String, now: float) -> void:
	var reactions: Dictionary = _miner_reactions.get_or_add(id, {})
	if pose == "happy" or pose == "sad":
		reactions["result"] = pose
	reactions[pose] = now


func _haul_speed(c: Dictionary, p: Dictionary, weight: float) -> float:
	if c.has("hv"):
		return 0.0
	# 用快照里的游戏时间和收绳量，连同合拉、大力和帮拉角度的影响一起反映到动作中。
	if not p.is_empty() and int(c.it) == int(p.it) and int(c.s) == int(p.s) and int(p.fz) == 0:
		var dt := float(prev.tl) - float(cur.tl)
		if dt > 0.0:
			return maxf(0.0, (float(p.l) - float(c.l)) / dt)
	var b := Cfg.b()
	var role := Cfg.character(pcharacter(int(c.i)))
	var heavy := float(role.get("heavyMul", 1.0)) if weight >= float(role.get("heavyMin", INF)) else 1.0
	return float(b.HAUL_V) / weight * (float(b.STRONG) if int(c.sg) == 1 else 1.0) * heavy


func _miner_frame(o: Dictionary, c: Dictionary, p: Dictionary, now: float, paused: bool) -> String:
	var anim: Dictionary = _miner_motion.get_or_add(int(o.id), {"frame": "idle", "cycle": 0.0, "motion": "", "at": now})
	var dt := (now - float(anim.at)) / 1000.0
	anim.at = now
	if paused or int(o.fz) == 1:
		return String(anim.frame)
	var st := int(o.st)
	var frame := "idle"
	var motion := ""
	var fps := 0.0
	if st == 0:
		frame = "idle2" if floori(now / 1000.0 + int(o.c) * 0.5) % 2 == 1 else "idle"
	elif st == 3:
		motion = "crank"
		fps = 12.0 * float(Cfg.character(int(o.c)).get("emptyHookMul", 1.0))
	elif st == 2 or st == 4:
		var items: Dictionary = cur.fm[int(o.fi)] if cur.has("fm") and int(o.fi) < cur.fm.size() else {}
		var it: Array = items.get(int(c.it), [])
		var weight := float(Cfg.b().TYPES[int(it[1])].w) if not it.is_empty() else 1.0
		var speed := _haul_speed(c, p, weight)
		if weight >= HEAVY_WEIGHT and int(o.sg) == 0:
			motion = "strain"
			fps = minf(10.0, 2.8 + speed / 90.0)
		else:
			motion = "crank"
			fps = minf(18.0, 3.5 + speed / 95.0)
	if motion != "":
		var frames := STRAIN if motion == "strain" else CRANK
		anim.cycle = fposmod(float(anim.cycle) + dt * fps, frames.size()) if anim.motion == motion else 0.0
		frame = frames[floori(float(anim.cycle))]
	anim.motion = motion

	var reactions: Dictionary = _miner_reactions.get(int(o.id), {})
	var happy_ms := now - float(reactions.get("happy", -1e9))
	if now - float(reactions.get("hit", -1e9)) < 1000.0:
		frame = "hit"
	elif now - float(reactions.get("throw", -1e9)) < 400.0:
		frame = "throw"
	elif reactions.get("result") == "sad" and now - float(reactions.get("sad", -1e9)) < 800.0:
		frame = "sad"
	elif reactions.get("result") == "happy" and happy_ms < 700.0:
		frame = "happy2" if happy_ms >= 200.0 and happy_ms < 460.0 else "happy"
	anim.frame = frame
	return frame


# ───── 发给服务端的操作 ─────
func create(mode_key: String, player_name: String) -> void:
	if mode_key != "solo" or not player_name.strip_edges().is_empty():
		Net.save_name(player_name)
	var msg := {"t": "create", "name": player_name, "mode": mode_key}
	if mode_key == "solo":
		msg["c"] = solo_character
	Net.send(msg)


func join(code: String, player_name: String) -> void:
	Net.save_name(player_name)
	Net.send({"t": "join", "code": code.strip_edges(), "name": player_name})


func fire_seat(seat: int) -> void:
	var ids := my_ids()
	keys_seen += 1
	if ph() == "play" and not solo_paused() and seat < ids.size():
		fires_sent += 1
		var ang := snappedf(float(view_ang.get(ids[seat], 0.0)), 0.001)
		Net.send({"t": "fire", "i": ids[seat], "a": ang})
		# 不等服务端回话：钩子正在摆的话，按下这一刻就在本地把它画出去、把声音放出来。
		# 判定还是服务端的，这里只是不让手上感觉到那几十毫秒的来回
		var c: Dictionary = pstate(ids[seat])
		if not c.is_empty() and int(c.s) == 0 and int(c.fz) == 0 and int(c.out) == 0 and not _pred.has(ids[seat]):
			_pred[ids[seat]] = {"t": float(Time.get_ticks_msec()), "ang": ang}
			Sfx.play("fire")


# 快捷喊话：只发编号。服务端限了频率（2 秒一次）
func emote(k: int) -> void:
	var ids := my_ids()
	if ids.size() > 0 and ph() != "" and ph() != "lobby" and mode() != "solo":
		Net.send({"t": "emote", "i": ids[0], "k": k})


func tool_seat(seat: int, index: int) -> void:
	var ids := my_ids()
	var order: Array = Cfg.b().TOOL_ORDER[mode()]
	if ph() == "play" and not solo_paused() and seat < ids.size() and index < order.size():
		Net.send({"t": "tool", "i": ids[seat], "k": order[index]})


func _unhandled_input(e: InputEvent) -> void:
	if solo_paused():
		return
	if e is InputEventKey and e.pressed and not e.echo:      # 喊话和静音在哪个阶段都能按（输入框里打字时按键到不了这里）
		var code0: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		var ei: int = EMOTE_KEYS.find(code0)
		if ei >= 0 and ph() != "" and ph() != "lobby" and mode() != "solo":
			emote(ei)
			get_viewport().set_input_as_handled()
			return
		if code0 == KEY_M:
			Sfx.set_muted(not Sfx.muted)
			say("声音已关" if Sfx.muted else "声音已开")
			get_viewport().set_input_as_handled()
			return
	if ph() != "play":
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		for seat in my_ids().size():
			var ks: Dictionary = Cfg.KEYSETS[seat]
			if code in ks.fire:
				fire_seat(seat)
				get_viewport().set_input_as_handled()
				return
			var ti: int = ks.tools.find(code)
			if ti >= 0:
				tool_seat(seat, ti)
				get_viewport().set_input_as_handled()
				return
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		fire_seat(0)
	elif e is InputEventScreenTouch and e.pressed:
		fire_seat(0)


func _process(dt: float) -> void:
	_t += dt
	if solo_paused():
		_pred.clear()
		return
	if auto and ph() == "play":
		_auto_step()
	if ph() == "play":                                   # 最后 5 秒，每秒滴答一声
		var left := ceili(time_left())
		if left <= 5 and left >= 1 and left != _tick_s:
			_tick_s = left
			Sfx.play("tick")
	else:
		_tick_s = -1
		_pred.clear()


# 测试用的自动瞄准：沿屏幕上此刻的角度看钩子最先碰到什么，对准了值钱的东西就放钩（和服务端电脑玩家的算法一样）。
# 只替联调脚本"按键"，放钩还是走正常的消息，判定仍然在服务端。
func _auto_step() -> void:
	var ids := my_ids()
	if ids.is_empty():
		return
	var c: Dictionary = pstate(ids[0])
	if c.is_empty() or not cur.has("F"):
		return
	if int(c.out) == 1:                                  # 淘汰了：能丢石头就丢
		if mode() == "race" and float(c.get("gc", 1.0)) <= 0.0 and int(c.get("gn", 0)) > 0 and _t - _auto_ghost > 1.0:
			_auto_ghost = _t
			fire_seat(0)
		return
	if int(c.s) != 0 or int(c.fz) == 1:
		return
	var fi := int(c.fi)
	if fi >= cur.F.size():
		return
	var b := Cfg.b()
	var ang := float(view_ang.get(ids[0], 0.0))
	var sx := sin(ang)
	var cx := cos(ang)
	var first := ""
	var ft := 1e9
	var aimed := false
	var co2: bool = mode() == "co" and meta.get("players", []).size() >= int(b.FUN.coop.minPlayers)
	var ky := int(cur.get("ky", 0))
	for it in cur.F[fi]:
		var tp: Dictionary = b.TYPES[int(it[1])]
		var held := int(it[4]) != 0
		# 合作：别人吊着的巨型金块可以去帮；自己不先去钩巨型金块（auto_gx 打开时才钩）；宝箱等别人拿到钥匙再拉
		if held and not (co2 and String(tp.k) == "gx" and int(it[4]) != ids[0]):
			continue
		# 这两样不该去钩，但会挡路：照样算进"钩子最先碰到什么"，碰到的是它们就不出手
		var no: bool = co2 and ((not held and String(tp.k) == "gx" and not auto_gx) or (String(tp.k) == "chest" and (ky == 0 or ky == ids[0])))
		var dx := float(it[2]) - float(c.x)
		var dy := float(it[3]) - float(b.Y0)
		var along := dx * sx + dy * cx
		var perp := absf(dx * cx - dy * sx)
		var rr := float(tp.r) + float(b.HOOK_R)
		if along < float(b.MINL) or perp >= rr:
			continue
		var t := along - sqrt(rr * rr - perp * perp)
		if t < ft:
			ft = t
			first = "rs" if no else String(tp.k)
			aimed = perp < float(tp.r) * 0.5
	if first != "" and aimed and not (first in ["tnt", "rs", "rl"]):
		fire_seat(0)


# 剩余时间：服务端发来的数再减去这一帧到现在过了多久
func time_left() -> float:
	if cur.is_empty():
		return 0.0
	var elapsed := 0.0 if solo_paused() else (Time.get_ticks_msec() - float(cur._t)) / 1000.0
	return maxf(0.0, float(cur.tl) - elapsed)


# ───── 每一帧：算出每口井该画什么 ─────
func build_view() -> Dictionary:
	var b := Cfg.b()
	var now := float(Time.get_ticks_msec())
	var phase := ph()
	var live := phase == "play" or phase == "count"
	var paused := solo_paused()
	# 服务端每秒 30 帧，这里在最近两帧之间插值，画面才顺（故意比最新一帧慢 45 毫秒）
	var a := 1.0
	if live and not paused and prev.has("F") and not bool(prev.get("paused", false)) and float(cur._t) > float(prev._t):
		a = clampf((now - 45.0 - float(prev._t)) / (float(cur._t) - float(prev._t)), 0.0, 1.4)
	var fields := []
	if live and cur.has("F"):
		for fi in cur.F.size():
			var arr := []
			var pmap: Dictionary = prev.fm[fi] if prev.has("fm") and fi < prev.fm.size() else {}
			for c in cur.F[fi]:
				var x := float(c[2])
				var y := float(c[3])
				var by := int(c[4])
				var walk_dx := 0.0
				var q = pmap.get(int(c[0]))
				if q != null and absf(float(q[2]) - x) + absf(float(q[3]) - y) < 140.0:
					if phase == "play" and by == 0 and int(q[4]) == 0:
						walk_dx = x - float(q[2])
					x = float(q[2]) + (x - float(q[2])) * a
					y = float(q[3]) + (y - float(q[3])) * a
				arr.append({"id": int(c[0]), "t": int(c[1]), "x": x, "y": y, "by": by, "walk_dx": walk_dx})
			fields.append(arr)
	else:
		fields.append(DEMO_ITEMS)

	var list: Array = meta.get("players", [{"id": -1, "name": "", "c": 0}])
	var n := list.size()
	var players := []
	var multi_local := my_ids().size() > 1
	for idx in n:
		var mp: Dictionary = list[idx]
		var id := int(mp.id)
		var seat := seat_of(id)
		var o := {
			"id": id, "name": String(mp.name), "c": pcharacter(id), "x": roundf(float(b.W) * (idx + 1) / (n + 1)), "fi": 0, "out": 0, "ps": 0,
			"ang": float(b.AMP) * sin(_t * float(b.SWING) * 0.55 + idx * 1.7), "len": float(b.MINL), "st": 0, "fz": 0, "sg": 0, "seat": seat, "tag": "", "hint": "", "m": 0, "frame": "idle", "on": bool(mp.get("on", true)),
		}
		var c: Dictionary = pstate(id)
		if not c.is_empty():
			o.m = int(c.m)
			o.out = int(c.out)
			o.ps = int(c.ps)
			if live:
				var p: Dictionary = prev.get("pm", {}).get(id, {}) if prev.has("F") else {}
				if not p.is_empty() and absf(float(c.l) - float(p.l)) < 200.0:
					o.ang = float(p.a) + (float(c.a) - float(p.a)) * a
					o.len = float(p.l) + (float(c.l) - float(p.l)) * a
				else:
					o.ang = float(c.a)
					o.len = float(c.l)
				o.x = float(c.x)
				o.fi = int(c.fi)
				o.st = int(c.s)
				# 出钩预判：按下那一刻起本地先把钩子画出去；服务端的状态到了以后，在 0.3 秒里慢慢并回服务端的位置
				if _pred.has(id):
					var pr: Dictionary = _pred[id]
					var el: float = (now - float(pr.t)) / 1000.0
					var speed := float(b.EXT_V) * float(Cfg.character(int(o.c)).get("emptyHookMul", 1.0))
					var want := float(b.MINL) + speed * el
					if o.st == 0 and el < 0.3:
						o.st = 1
						o.ang = float(pr.ang)
						o.len = want
					elif o.st == 1 and el < 0.6:
						o.len = maxf(o.len, lerpf(o.len, want, clampf(1.0 - (el - 0.1) / 0.3, 0.0, 1.0)))
					else:
						_pred.erase(id)
				o.fz = int(c.fz)
				o.sg = int(c.sg)
				o.frame = _miner_frame(o, c, p, now, paused)
				# 矿工头上那行字：对战和分屏显示各自的钱；本机多人时再带上各自的道具和按键
				var tag := Cfg.money(o.m) if mode() != "co" else ""
				if int(c.sg) == 1:
					tag += " 大力"
				if int(c.get("cb", 0)) > 0 and o.out == 0:   # 分屏：连续钩中几次了，凑够就丢石头
					tag += " 连钩%d/%d" % [int(c.cb), int(c.get("cn", 0))]
				if mode() == "co" and int(cur.get("ky", 0)) == id:
					tag += " 拿着钥匙"
				o.tag = tag
				if c.has("hv"):                              # 合作：吊着巨型金块拉不动
					o.hint = "拉不动！等人来帮 %d" % ceili(float(c.hv))
				if seat > 0 and c.has("tl"):
					var order: Array = b.TOOL_ORDER[mode()]
					var hint := ""
					for ti in order.size():
						hint += "%s%d[%s] " % [String(b.SHOP[order[ti]].n).substr(0, 1), int(c.tl[order[ti]]), Cfg.KEYSETS[seat].tl[ti]]
					o.hint = hint
		if multi_local and seat >= 0 and live:          # 本机多人：名字上面一行写各自的按键
			o.hint = "%s放钩　%s" % [Cfg.KEYSETS[seat].label, o.hint]
		if not bool(mp.get("on", true)):
			o.name += "（掉线）"
		if _emo.has(id):                                 # 刚喊的话，头上显示 3 秒
			if now - float(_emo[id].t) < 3000.0:
				o.hint = "「%s」" % String(_emo[id].text)
			else:
				_emo.erase(id)
		view_ang[id] = o.ang
		players.append(o)

	var depth := int(cur.get("dp", 1)) if not cur.is_empty() else 1
	var tier: int = Cfg.tier_of(depth) if phase != "" and phase != "lobby" else 1
	if Cfg.args().has("tier"):
		tier = clampi(int(Cfg.args()["tier"]), 0, 3)
	var plate := ""
	var plank := ""
	var clock := ""
	if live:
		plate = "%s · 地下 %d 米" % [b.LAYERS[tier], depth * 30]
		clock = "%d 秒" % ceili(time_left()) if phase == "play" or mode() == "solo" else ""
		if mode() == "vs":
			plank = "第 %d / %d 局" % [int(cur.rd), int(meta.rounds)]
		elif mode() == "co":
			plank = "第 %d 关　%s / %s" % [int(cur.rd), Cfg.money(cur.get("te", 0)), Cfg.money(cur.get("tg", 0))]
		elif mode() == "solo":
			var me: Dictionary = pstate(my_ids()[0]) if not my_ids().is_empty() else {}
			plank = "第 %d 关　%s / %s" % [int(cur.rd), Cfg.money(me.get("m", 0)), Cfg.money(cur.get("tg", 0))]
		else:
			plank = "第 %d 关　目标 %s" % [int(cur.rd), Cfg.money(cur.get("tg", 0))]
	# 这一关的随机事件：倒计时的时候大字预告，开挖后在顶上写还有几秒
	var event := ""
	var event_big := ""
	var event_sub := ""
	var dark := 0.0
	if live and cur.has("ev"):
		var ev: Array = cur.ev
		var conf: Dictionary = b.FUN.events.get(String(ev[0]), {})
		var secs: float = maxf(0.0, float(ev[2]) - (now - float(cur._t)) / 1000.0) if phase == "play" and not paused else float(ev[2])
		if phase == "count":
			event_big = "本关事件：%s" % String(conf.get("n", ""))
			event_sub = String(conf.get("d", ""))
		elif int(ev[1]) == 0:
			event = "%s　%d 秒后" % [String(conf.get("n", "")), ceili(secs)]
		elif int(ev[1]) == 1:
			event = "%s　还剩 %d 秒" % [String(conf.get("n", "")), ceili(secs)]
			dark = 1.0 if String(ev[0]) == "dark" else 0.0
	# 分屏里自己被淘汰了：提示可以丢石头
	var note := ""
	if live and mode() == "race" and my_ids().size() > 0:
		var me: Dictionary = pstate(my_ids()[0])
		if int(me.get("out", 0)) == 1 and me.has("gn"):
			var gc: float = maxf(0.0, float(me.get("gc", 0.0)) - (now - float(cur._t)) / 1000.0)
			if int(me.gn) <= 0:
				note = "你淘汰了。这一关的石头丢完了"
			elif gc > 0.0:
				note = "你淘汰了。%d 秒后可以再丢石头（本关还剩 %d 块）" % [ceili(gc), int(me.gn)]
			else:
				note = "你淘汰了。按放钩键，往钱最多的人井里丢石头（本关还剩 %d 块）" % int(me.gn)
	return {
		"live": live, "split": live and mode() == "race" and n > 1, "fields": fields, "players": players,
		"info": {"live": live, "tier": tier, "dark": dark, "paused": paused},
		"hud": {"plate": plate + ("　" + event if event != "" else ""), "plank": plank, "clock": clock, "event": event, "event_big": event_big, "event_sub": event_sub, "note": note},
	}
