# 音效：全部是程序合成的。启动时按下面的配方算出波形，不需要任何音效文件，也不用下载。
# 用法：Sfx.play("coin")；Sfx.play("coin", 1.2) 调高音调；按 M 键或 Sfx.set_muted(true) 静音（网页版会记住）。
extends Node

const RATE := 22050
# 每个音效由几段声音叠起来。每段：[波形, 起始频率, 结束频率, 从第几秒开始, 持续几秒, 音量, 衰减快慢]
# 波形：sine 纯音、tri 柔一点的音、square 电子音、noise 沙沙声（频率越低越闷）
const DEFS := {
	"fire": [["noise", 3200, 700, 0.0, 0.13, 0.22, 16], ["sine", 520, 210, 0.0, 0.11, 0.16, 14]],                 # 放钩：嗖
	"grab": [["square", 940, 720, 0.0, 0.05, 0.16, 38], ["noise", 5000, 3000, 0.0, 0.04, 0.2, 55]],               # 钩中：咔
	"thud": [["sine", 150, 58, 0.0, 0.18, 0.6, 13], ["noise", 900, 300, 0.0, 0.07, 0.22, 30]],                    # 钩到石头：闷响
	"coin": [["sine", 1320, 1320, 0.0, 0.09, 0.28, 16], ["sine", 1760, 1760, 0.07, 0.24, 0.28, 10]],              # 进账：叮
	"big": [["sine", 880, 880, 0.0, 0.3, 0.22, 8], ["sine", 1109, 1109, 0.07, 0.3, 0.22, 8], ["sine", 1319, 1319, 0.14, 0.3, 0.22, 8], ["sine", 1760, 1760, 0.21, 0.42, 0.24, 6]],   # 大钱：一串上行音
	"boom": [["noise", 620, 120, 0.0, 0.5, 0.8, 7], ["sine", 92, 34, 0.0, 0.45, 0.7, 6]],                         # 爆炸
	"miss": [["sine", 270, 150, 0.0, 0.13, 0.2, 13]],                                                              # 钩空
	"atk": [["sine", 1250, 300, 0.0, 0.3, 0.22, 4], ["sine", 150, 58, 0.3, 0.18, 0.55, 13], ["noise", 900, 300, 0.3, 0.07, 0.2, 30]],   # 石头砸下来：咻——咚
	"emo": [["tri", 660, 660, 0.0, 0.06, 0.25, 20], ["tri", 990, 990, 0.06, 0.11, 0.25, 16]],                     # 喊话：嘀嘟
	"event": [["square", 520, 520, 0.0, 0.14, 0.14, 6], ["square", 520, 520, 0.18, 0.14, 0.14, 6], ["square", 780, 780, 0.36, 0.32, 0.16, 5]],   # 随机事件来了
	"tick": [["sine", 1000, 1000, 0.0, 0.04, 0.2, 40]],                                                            # 最后几秒的滴答
	"go": [["sine", 660, 660, 0.0, 0.1, 0.25, 12], ["sine", 990, 990, 0.1, 0.28, 0.28, 8]],                       # 开挖
	"win": [["tri", 523, 523, 0.0, 0.4, 0.24, 6], ["tri", 659, 659, 0.12, 0.4, 0.24, 6], ["tri", 784, 784, 0.24, 0.4, 0.24, 6], ["tri", 1047, 1047, 0.36, 0.6, 0.26, 4]],   # 整场结束
	"lock": [["square", 210, 210, 0.0, 0.08, 0.16, 20], ["square", 160, 160, 0.1, 0.14, 0.16, 14]],               # 宝箱打不开
	"heavy": [["sine", 112, 86, 0.0, 0.32, 0.5, 5]],                                                               # 拉不动
	"buy": [["sine", 880, 880, 0.0, 0.08, 0.24, 16], ["sine", 1175, 1175, 0.07, 0.2, 0.24, 10]],                  # 买东西
	"frz": [["noise", 6000, 2500, 0.0, 0.35, 0.2, 6], ["sine", 1800, 900, 0.0, 0.3, 0.12, 6]],                    # 冰冻、剪刀
}

var muted := false
var played := 0                  # 一共放了几次（联调脚本用它确认声音真的触发了）
var _streams := {}
var _players: Array = []
var _next := 0
var _queue: Array = []


func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_queue = DEFS.keys()
	if OS.has_feature("web"):
		muted = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('dj_mute')==='1'}catch(e){return false}})()", true) == true


func _process(_dt: float) -> void:
	if not _queue.is_empty():                    # 一帧只合成一个，免得启动时卡一下
		var k: String = _queue.pop_front()
		_streams[k] = _build(DEFS[k])


func play(sound: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	played += 1
	if muted or not _streams.has(sound):
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.pitch_scale = pitch
	p.volume_db = -9.0 + vol_db
	p.play()


func set_muted(m: bool) -> void:
	muted = m
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('dj_mute','%s')}catch(e){}" % ("1" if m else "0"), true)


func _build(parts: Array) -> AudioStreamWAV:
	var total := 0.0
	for v in parts:
		total = maxf(total, float(v[3]) + float(v[4]))
	var n := int(total * RATE) + 1
	var buf := PackedFloat32Array()
	buf.resize(n)
	for v in parts:
		var wave := String(v[0])
		var f0 := float(v[1])
		var f1 := float(v[2])
		var d := float(v[4])
		var amp := float(v[5])
		var dec := float(v[6])
		var i0 := int(float(v[3]) * RATE)
		var cnt := int(d * RATE)
		var ph := 0.0
		var lp := 0.0
		for i in cnt:
			var t := float(i) / RATE
			var f := f0 * pow(f1 / f0, t / d)
			var s := 0.0
			if wave == "noise":                      # 沙沙声过一个简单的低通，频率越低越闷
				lp += (randf() * 2.0 - 1.0 - lp) * minf(1.0, f / 5500.0)
				s = lp * 1.6
			else:
				ph += TAU * f / RATE
				if wave == "sine":
					s = sin(ph)
				elif wave == "square":
					s = 0.6 if sin(ph) > 0.0 else -0.6
				else:
					s = asin(sin(ph)) * 0.6366
			var env := exp(-dec * t) * minf(1.0, t / 0.004) * minf(1.0, (d - t) / 0.012)
			buf[i0 + i] += s * amp * env
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = bytes
	return st
