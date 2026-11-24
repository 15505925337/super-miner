# 全局常量。玩法数值不写在这里，统一读 shared/balance.json（和服务端共用一份）。
extends RefCounted

const GW := 640                      # 设计基准宽（游戏像素）
const GH := 360                      # 设计基准高
const S := 0.5                       # 服务端坐标（原型的 1280×720）换成游戏像素要乘的倍数

enum Q { LOW, MID, HIGH, ULTRA }
const Q_NAMES := ["low", "mid", "high", "ultra"]

# 四个角色的颜色：红、蓝、绿、紫
const COLORS := [Color("ff6f61"), Color("45c8f0"), Color("7be08a"), Color("b99aff")]

# 物件类型 → 图片名
const ART := {
	"gs": "gold_s", "gm": "gold_m", "gl": "gold_l", "gx": "gold_xl", "rs": "rock_s", "rl": "rock_l",
	"gem": "gem", "rub": "ruby", "bag": "bag", "tnt": "tnt", "bug": "beetle", "fos": "fossil",
	"key": "key", "chest": "chest",
}
# 全黑时贴图自发光的叠加比例。宝袋和宝箱另乘各层的黑灯倍率。
const DARK_GLOW := {
	"gs": 0.58, "gm": 0.53, "gl": 0.48, "gx": 0.48,
	"gem": 0.77, "rub": 0.77, "bug": 0.77,
	"key": 0.76, "bag": 0.14, "chest": 0.22,
}
const GOLD := ["gs", "gm", "gl", "gx"]
# 这些东西画的时候各带一个固定的倾斜角度（照原型）
const TILT := GOLD + ["rs", "rl", "fos"]
const SPARKLE := GOLD + ["gem", "rub", "bug", "key"]

# 同一台设备上最多四个人，各用一组按键：放钩键、三个道具键
const KEYSETS := [
	{"fire": [KEY_SPACE, KEY_DOWN], "tools": [KEY_1, KEY_2, KEY_3], "label": "空格", "tl": ["1", "2", "3"]},
	{"fire": [KEY_ENTER, KEY_KP_ENTER], "tools": [KEY_8, KEY_9, KEY_0], "label": "回车", "tl": ["8", "9", "0"]},
	{"fire": [KEY_F], "tools": [KEY_R, KEY_T, KEY_Y], "label": "F", "tl": ["R", "T", "Y"]},
	{"fire": [KEY_J], "tools": [KEY_U, KEY_I, KEY_O], "label": "J", "tl": ["U", "I", "O"]},
]

static var _b := {}
static var _args := {}
static var _args_done := false
static var _font: Font = null
static var _font_done := false


# 数值表
static func b() -> Dictionary:
	if _b.is_empty():
		_b = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance.json"))
	return _b


static func character(c: int) -> Dictionary:
	return b().CHARACTERS[c]


static func type_key(t) -> String:
	return String(b().TYPES[int(t)].k)


static func type_index(key: String) -> int:
	var types: Array = b().TYPES
	for i in types.size():
		if String(types[i].k) == key:
			return i
	return 0


static func tier_of(depth: int) -> int:
	return clampi((depth - 1) >> 1, 0, b().LAYERS.size() - 1)


# 启动参数：桌面版写在 -- 后面（--q=mid），网页版写在网址问号后面（?q=mid）
static func args() -> Dictionary:
	if _args_done:
		return _args
	_args_done = true
	var list: PackedStringArray = OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		var s = JavaScriptBridge.eval("window.location.search.substring(1)", true)
		if s is String and s != "":
			list = s.split("&")
	for a in list:
		var t := String(a).trim_prefix("--")
		var i := t.find("=")
		if i < 0:
			_args[t] = "1"
		else:
			_args[t.substr(0, i)] = t.substr(i + 1).uri_decode()
	return _args


# 中文字体：fonts/ui.woff2（缝合像素字体，SIL OFL 1.1）。没有这个文件就退回引擎自带字体，中文会显示成方框
static func font() -> Font:
	if _font_done:
		return _font
	_font_done = true
	for p in ["res://fonts/ui.otf", "res://fonts/ui.ttf", "res://fonts/ui.woff2"]:
		if ResourceLoader.exists(p):
			var f = load(p)
			if f is FontFile:
				f.hinting = TextServer.HINTING_NONE
				f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
				_font = f
				break
	return _font


static func money(v) -> String:
	var s := str(int(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return "¥" + s + out
