# 超高档的二维全局光照。遮挡、发光和解算按设计坐标绘制，不受窗口缩放和井的震动影响。
extends Node2D

const Cfg := preload("res://scripts/cfg.gd")
const SH_MASK := preload("res://shaders/gi_mask.gdshader")
const SH_JFA := preload("res://shaders/gi_jfa.gdshader")
const SH_DISTANCE := preload("res://shaders/gi_distance.gdshader")
const SH_LIGHT := preload("res://shaders/gi_light.gdshader")
const SH_SHADOW := preload("res://shaders/gi_shadow.gdshader")
const SH_RESOLVE := preload("res://shaders/gi_resolve.gdshader")
const SH_BACKGROUND := preload("res://shaders/gi_background.gdshader")
const SH_RECEIVE := preload("res://shaders/gi_receive.gdshader")
const DEFAULT_DIVISOR := 2
const DEFAULT_BOUNCE := 1.10
const DEFAULT_SHADOW := 1.45
const JFA_JUMPS := [512, 256, 128, 64, 32, 16, 8, 4, 2, 1, 1]
const DESIGN_SIZE := Vector2i(Cfg.GW, Cfg.GH)
const DESIGN_PX := Vector2.ONE / Vector2(DESIGN_SIZE)

# 颜色和中心强度（RGBA）、衰减尺度、光照覆盖半径（设计像素）。
const ITEM_EMISSION := {
	"gs": [Color(1.0, 0.65, 0.20, 0.39), 22.0, 72.0],
	"gm": [Color(1.0, 0.65, 0.20, 0.45), 30.0, 92.0],
	"gl": [Color(1.0, 0.65, 0.20, 0.51), 37.0, 116.0],
	"gx": [Color(1.0, 0.65, 0.20, 0.56), 46.0, 140.0],
	"gem": [Color(0.26, 0.64, 1.0, 0.53), 32.0, 100.0],
	"rub": [Color(1.0, 0.30, 0.57, 0.51), 30.0, 96.0],
	"bug": [Color(0.69, 0.38, 1.0, 0.47), 31.0, 96.0],
	"key": [Color(1.0, 0.76, 0.27, 0.43), 24.0, 76.0],
}
const LAMP_STRENGTH := 0.77
const LAMP_FALLOFF := Vector2(66.0, 126.0)
const LAMP_REACH := 204.0
const LAVA_COLOR := Color(1.0, 0.24, 0.08, 0.64)
const HEAD_COLOR := Color(1.0, 0.88, 0.58, 0.34)
# 沿用任务 01、02 量出的 52 个头灯灯芯坐标。按原图 512×512 记。
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

var _items: Dictionary
var _miners: Dictionary
var _divisor: int
var _bounce: float
var _shadow: float
var _keep_dark_glow: bool
var _dark := 0.0
var _active := false
var _mask_vp: SubViewport
var _distance_vp: SubViewport
var _passes: Array[SubViewport] = []
var _emitters := Node2D.new()
var _mask_mat := ShaderMaterial.new()
var _shadow_mat: ShaderMaterial
var _resolve_mat: ShaderMaterial
var _receive_mat := ShaderMaterial.new()
var _mask_nodes := {}
var _moving_lights := {}
var _tier_lights := Node2D.new()
var _overlay: ColorRect


func _init(items: Dictionary, miners: Dictionary, divisor: int, bounce: float, shadow: float, keep_dark_glow: bool) -> void:
	_items = items
	_miners = miners
	_divisor = divisor
	_bounce = bounce
	_shadow = shadow
	_keep_dark_glow = keep_dark_glow


func _ready() -> void:
	name = "GI"
	# 暂停时保留前一帧的物件与姿势，仍可切档和重排窗口。
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_mask_vp = _viewport(DESIGN_SIZE)
	_mask_vp.name = "Occlusion"
	_mask_vp.add_child(_rect(Color.BLACK))
	_mask_mat.shader = SH_MASK

	var nearest := _jfa_pass(_mask_vp, 0)
	for jump in JFA_JUMPS:
		nearest = _jfa_pass(nearest, jump)
	_distance_vp = _viewport(DESIGN_SIZE)
	_distance_vp.name = "Distance"
	var distance_mat := _pass_material(_distance_vp, SH_DISTANCE)
	distance_mat.set_shader_parameter("seeds", nearest.get_texture())
	distance_mat.set_shader_parameter("mask_tex", _mask_vp.get_texture())
	distance_mat.set_shader_parameter("design_size", DESIGN_SIZE)
	_distance_vp.add_child(nearest)

	var size := DESIGN_SIZE / _divisor
	var shadow_vp := _viewport(size)
	shadow_vp.name = "WallShadow"
	_shadow_mat = _pass_material(shadow_vp, SH_SHADOW)
	_shadow_mat.set_shader_parameter("distance_tex", _distance_vp.get_texture())
	_shadow_mat.set_shader_parameter("design_size", Vector2(DESIGN_SIZE))
	_shadow_mat.set_shader_parameter("wall_shadow_strength", _shadow / DEFAULT_SHADOW)
	shadow_vp.add_child(_distance_vp)

	var light_vp := _light_buffer(size, "SceneLight", _tier_lights)
	var emission_vp := _light_buffer(size, "Emission", _emitters)
	var resolve_vp := _viewport(size)
	resolve_vp.name = "Resolve"
	# RGBA 中的 A 保存井壁遮挡。透明视口配合无混合写入保留四个通道。
	resolve_vp.transparent_bg = true
	_resolve_mat = _pass_material(resolve_vp, SH_RESOLVE)
	_resolve_mat.set_shader_parameter("light_px", Vector2.ONE / Vector2(size))
	_resolve_mat.set_shader_parameter("design_px", DESIGN_PX)
	_resolve_mat.set_shader_parameter("light_tex", light_vp.get_texture())
	_resolve_mat.set_shader_parameter("emission_tex", emission_vp.get_texture())
	_resolve_mat.set_shader_parameter("shadow_tex", shadow_vp.get_texture())
	# 先画三个输入视口，再合成与滤波，主井最后读取。
	resolve_vp.add_child(shadow_vp)
	resolve_vp.add_child(light_vp)
	resolve_vp.add_child(emission_vp)
	add_child(resolve_vp)

	var overlay_mat := ShaderMaterial.new()
	overlay_mat.shader = SH_BACKGROUND
	overlay_mat.set_shader_parameter("resolved_tex", resolve_vp.get_texture())
	overlay_mat.set_shader_parameter("emission_tex", emission_vp.get_texture())
	overlay_mat.set_shader_parameter("bounce_strength", _bounce)
	overlay_mat.set_shader_parameter("daylight_strength", _bounce / DEFAULT_BOUNCE)
	_overlay = ColorRect.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.size = Vector2(DESIGN_SIZE)
	_overlay.z_index = -2
	_overlay.material = overlay_mat
	_overlay.hide()
	add_child(_overlay)

	_receive_mat.shader = SH_RECEIVE
	_receive_mat.set_shader_parameter("resolved_tex", resolve_vp.get_texture())
	_receive_mat.set_shader_parameter("bounce_strength", _bounce)


func _jfa_pass(previous: SubViewport, jump: int) -> SubViewport:
	var vp := _viewport(DESIGN_SIZE)
	vp.name = "Seed" if jump == 0 else "Jump%d" % jump
	# RGBA 存的是整数坐标，透明通道也要保留。
	vp.transparent_bg = true
	var mat := _pass_material(vp, SH_JFA)
	mat.set_shader_parameter("src", previous.get_texture())
	mat.set_shader_parameter("design_size", DESIGN_SIZE)
	mat.set_shader_parameter("jump", jump)
	vp.add_child(previous)
	return vp


func _light_buffer(size: Vector2i, label: String, emitters: Node2D) -> SubViewport:
	var vp := _viewport(size)
	vp.name = label
	vp.add_child(_rect(Color.BLACK))
	emitters.scale = Vector2.ONE / float(_divisor)
	vp.add_child(emitters)
	return vp


func _pass_material(vp: SubViewport, shader: Shader) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var rect := _rect(Color.WHITE)
	rect.material = mat
	vp.add_child(rect)
	return mat


func _viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_passes.append(vp)
	return vp


func _rect(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = color
	return rect


func set_tier(conf: Dictionary, lava: bool, ground_y: float) -> void:
	var direction: Vector2 = conf.light_dir.normalized()
	_shadow_mat.set_shader_parameter("key_direction", direction)
	_resolve_mat.set_shader_parameter("key_direction", direction)
	_overlay.material.set_shader_parameter("ground_y", ground_y)
	for light in _tier_lights.get_children():
		_tier_lights.remove_child(light)
		light.queue_free()
	for pos in conf.lamps:
		var lamp := _new_light(_tier_lights, Color(conf.light_col, LAMP_STRENGTH),
			Vector2(LAMP_FALLOFF.y, LAMP_REACH))
		lamp.material.set_shader_parameter("falloff_scale", Vector2(LAMP_FALLOFF.y / LAMP_FALLOFF.x, 1.0))
		lamp.material.set_shader_parameter("light_dir", conf.light_dir)
		_move_light(lamp, pos)
	if lava:
		var magma := _new_light(_tier_lights, LAVA_COLOR, Vector2(76.0, 172.0), Cfg.GW * 0.5)
		_move_light(magma, Vector2(Cfg.GW * 0.5, Cfg.GH))


func set_dark(dark: float) -> void:
	_dark = dark
	_overlay.material.set_shader_parameter("darkness", dark)
	_shadow_mat.set_shader_parameter("daylight", 1.0 - dark)
	_receive_mat.set_shader_parameter("light_fade", 1.0 - dark)
	for light in _tier_lights.get_children():
		_update_light_fade(light)
	for light in _moving_lights.values():
		_update_light_fade(light)


func _update_light_fade(light: ColorRect) -> void:
	var fade := (1.0 - _dark) * (1.0 - _dark)
	if _keep_dark_glow and light.get_meta("dark_glow", false):
		fade = lerpf(1.0, 0.65, _dark)
	light.material.set_shader_parameter("light_fade", fade)


func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	set_process(on)
	_overlay.visible = on
	for vp in _passes:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		for item in _items.values():
			if item.sprite.material == _receive_mat:
				item.sprite.material = null


func _new_light(parent: Node2D, color: Color, range_px: Vector2,
		half_width: float = 0.0, dark_glow: bool = false) -> ColorRect:
	var light := ColorRect.new()
	light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	light.size = Vector2(2.0 * (range_px.y + half_width), 2.0 * range_px.y)
	var mat := ShaderMaterial.new()
	mat.shader = SH_LIGHT
	mat.set_shader_parameter("design_size", Vector2(DESIGN_SIZE))
	mat.set_shader_parameter("energy", Vector4(color.r, color.g, color.b, color.a))
	mat.set_shader_parameter("falloff_px", range_px.x)
	mat.set_shader_parameter("reach", range_px.y)
	mat.set_shader_parameter("line_half_width", half_width)
	light.material = mat
	if dark_glow:
		light.set_meta("dark_glow", true)
	_update_light_fade(light)
	parent.add_child(light)
	return light


func _move_light(light: ColorRect, center: Vector2) -> void:
	light.position = center - light.size * 0.5
	light.material.set_shader_parameter("center", center)


func _sync_light(source: Sprite2D, center: Vector2, color: Color, range_px: Vector2,
		dark_glow: bool, seen: Dictionary) -> void:
	var id := source.get_instance_id()
	seen[id] = true
	var light: ColorRect = _moving_lights.get(id)
	if light == null:
		light = _new_light(_emitters, color, range_px, 0.0, dark_glow)
		_moving_lights[id] = light
	_move_light(light, center)
	light.material.set_shader_parameter("opacity", source.get_parent().modulate.a)


func _sync_sprite(source: Sprite2D, pose: Transform2D, opacity: float, seen: Dictionary) -> void:
	var id := source.get_instance_id()
	seen[id] = true
	var mask: Sprite2D = _mask_nodes.get(id)
	if mask == null:
		mask = Sprite2D.new()
		mask.material = _mask_mat
		mask.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_mask_vp.add_child(mask)
		_mask_nodes[id] = mask
	var tex := source.texture
	mask.texture = tex.diffuse_texture if tex is CanvasTexture else tex
	mask.centered = source.centered
	mask.offset = source.offset
	mask.transform = pose
	mask.flip_h = source.flip_h
	mask.flip_v = source.flip_v
	mask.modulate.a = opacity


func _sync_rope(source: Line2D, pose: Transform2D, seen: Dictionary) -> void:
	var id := source.get_instance_id()
	seen[id] = true
	var mask: Line2D = _mask_nodes.get(id)
	if mask == null:
		mask = Line2D.new()
		mask.default_color = Color.WHITE
		mask.width = source.width
		mask.joint_mode = source.joint_mode
		mask.begin_cap_mode = source.begin_cap_mode
		mask.end_cap_mode = source.end_cap_mode
		mask.antialiased = source.antialiased
		_mask_vp.add_child(mask)
		_mask_nodes[id] = mask
	mask.transform = pose
	mask.points = source.points


func _remove_old(nodes: Dictionary, seen: Dictionary) -> void:
	for id in nodes.keys():
		if not seen.has(id):
			nodes[id].hide()
			nodes[id].queue_free()
			nodes.erase(id)


func _process(_dt: float) -> void:
	var to_design := global_transform.affine_inverse()
	_receive_mat.set_shader_parameter("well_origin", global_position)
	_receive_mat.set_shader_parameter("well_inv_size", DESIGN_PX / global_scale)
	var seen_masks := {}
	var seen_lights := {}
	for item in _items.values():
		var sprite: Sprite2D = item.sprite
		var pose := to_design * sprite.global_transform
		_sync_sprite(sprite, pose, item.modulate.a, seen_masks)
		if sprite.material != _receive_mat:
			sprite.material = _receive_mat
		if ITEM_EMISSION.has(item.kind):
			var emission: Array = ITEM_EMISSION[item.kind]
			_sync_light(sprite, pose.origin, emission[0], Vector2(emission[1], emission[2]), true, seen_lights)
	for miner in _miners.values():
		var sprite: Sprite2D = miner.sprite
		var pose := to_design * sprite.global_transform
		_sync_sprite(sprite, pose, miner.root.modulate.a, seen_masks)
		var hook: Node2D = miner.hook
		if hook.visible:
			_sync_sprite(hook.claw_sprite, to_design * hook.claw_sprite.global_transform, 1.0, seen_masks)
			_sync_rope(hook.rope_edge, to_design * hook.rope_edge.global_transform, seen_masks)
			var source: Vector2 = HEAD_LAMPS[miner.c][miner.frame]
			var head := pose * ((source / 512.0 - Vector2.ONE * 0.5) * sprite.texture.get_size())
			_sync_light(sprite, head, HEAD_COLOR, Vector2(37.0, 116.0), false, seen_lights)
	_remove_old(_mask_nodes, seen_masks)
	_remove_old(_moving_lights, seen_lights)
