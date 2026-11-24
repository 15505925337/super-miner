# 和服务端的连接：WebSocket + JSON。断了自动重连，重连后按身份令牌认回原来的座位。
extends Node

const Cfg = preload("res://scripts/cfg.gd")

signal got_meta(m: Dictionary)
signal got_state(m: Dictionary)
signal got_err(m: Dictionary)
signal got_left(m: Dictionary)
signal link_changed(is_up: bool)

var ws := WebSocketPeer.new()
var url := ""
var token := ""                  # 身份令牌：网页版存在这个标签页里，刷新也不变
var returning := false           # 这个标签页之前来过（刷新或断线重来）
var up := false
var want_room := ""              # 连上以后自动回的房间
var my_name := ""
var is_web := false
var _retry := 0
var _wait := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_web = OS.has_feature("web")
	var args := Cfg.args()
	if args.get("demo", "0") == "1":
		set_process(false)
		return
	if is_web:
		url = str(JavaScriptBridge.eval("(location.protocol==='https:'?'wss://':'ws://')+location.host", true))
		var r = JavaScriptBridge.eval("(function(){try{var t=sessionStorage.getItem('dj_token'),old=!!t;if(!t){t=Math.random().toString(36).slice(2)+Date.now().toString(36);sessionStorage.setItem('dj_token',t);}return (old?'1':'0')+t;}catch(e){return ''}})()", true)
		if r is String and r.length() > 8:
			returning = r.begins_with("1")
			token = r.substr(1)
		var n = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('dj_name')||''}catch(e){return ''}})()", true)
		if n is String:
			my_name = n
	if args.has("server"):
		url = String(args["server"])
	if url == "":
		url = "ws://127.0.0.1:8060"
	if args.has("token"):
		token = String(args["token"])
	if token.length() < 8:
		token = "t%08x%08x" % [randi(), randi()]
	if args.has("name"):
		my_name = String(args["name"])
	if args.has("r") and (returning or my_name != ""):
		want_room = String(args["r"])
	_open()


func _open() -> void:
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.connect_to_url(url)


func send(o: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(o))


func save_name(n: String) -> void:
	my_name = n
	if is_web:
		JavaScriptBridge.eval("try{localStorage.setItem('dj_name',%s)}catch(e){}" % JSON.stringify(n), true)


# 把房间号写进网址（?r=1234），这样刷新页面或把网址发给别人都能直接进这个房间
func set_url_room(code: String) -> void:
	want_room = code
	if is_web:
		JavaScriptBridge.eval("(function(c){try{var u=new URL(location.href);if(c)u.searchParams.set('r',c);else u.searchParams.delete('r');history.replaceState(null,'',u)}catch(e){}})(%s)" % JSON.stringify(code), true)


func invite_url(code: String) -> String:
	if is_web:
		return str(JavaScriptBridge.eval("location.origin+location.pathname", true)) + "?r=" + code
	return url.replace("ws://", "http://").replace("wss://", "https://") + "/?r=" + code


func _process(dt: float) -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not up:
			up = true
			_retry = 0
			send({"t": "hello", "token": token})
			if want_room != "":
				send({"t": "join", "code": want_room, "name": my_name})     # 刷新或断线后自动回房间
			link_changed.emit(true)
		while ws.get_available_packet_count() > 0:
			var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if m is Dictionary:
				match String(m.get("t", "")):
					"meta": got_meta.emit(m)
					"s": got_state.emit(m)
					"err": got_err.emit(m)
					"left": got_left.emit(m)
	elif st == WebSocketPeer.STATE_CLOSED:
		if up:
			up = false
			link_changed.emit(false)
		_wait -= dt
		if _wait <= 0.0:
			_wait = minf(4.0, 0.4 + _retry * 0.6)
			_retry += 1
			_open()
