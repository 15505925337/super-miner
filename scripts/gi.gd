# 超高档的二维全局光照。遮挡、发光和解算按设计坐标绘制，不受窗口缩放和井的震动影响。
extends Node2D

const Cfg := preload("res://scripts/cfg.gd")
const SH_MASK := preload("res://shaders/gi_mask.gdshader")
const SH_LIGHT := preload("res://shaders/gi_light.gdshader")
const SH_RESOLVE := preload("res://shaders/gi_resolve.gdshader")
const SH_BACKGROUND := preload("res://shaders/gi_background.gdshader")
const SH_RECEIVE := preload("res://shaders/gi_receive.gdshader")
const DEFAULT_DIVISOR := 2
const DEFAULT_BOUNCE := 0.70
const DEFAULT_SHADOW := 0.85
const DESIGN_SIZE := Vector2i(Cfg.GW, Cfg.GH)
const DESIGN_PX := Vector2.ONE / Vector2(DESIGN_SIZE)

# 颜色和中心强度（RGBA）、作用半径（设计像素）。
const ITEM_EMISSION := {
	"gs": [Color(1.0, 0.65, 0.20, 0.26), 24.0],
	"gm": [Color(1.0, 0.65, 0.20, 0.30), 30.0],
	"gl": [Color(1.0, 0.65, 0.20, 0.34), 38.0],
	"gx": [Color(1.0, 0.65, 0.20, 0.40), 51.0],
	"gem": [Color(0.32, 0.85, 1.0, 0.35), 34.0],
	"rub": [Color(1.0, 0.34, 0.46, 0.34), 32.0],
	"bug": [Color(0.80, 0.48, 1.0, 0.31), 34.0],
	"key": [Color(1.0, 0.80, 0.36, 0.27), 26.0],
}
const LAMP_STRENGTH := 0.38
const LAMP_RADIUS := 148.0
const LAVA_COLOR := Color(1.0, 0.24, 0.08, 0.42)
const LAVA_RADIUS := 92.0
const HEAD_COLOR := Color(1.0, 0.88, 0.58, 0.26)
const HEAD_RADIUS := 38.0
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
var _active := false
var _mask_vp: SubViewport
var _light_vp: SubViewport
var _resolve_vp: SubViewport
var _emitters := Node2D.new()
var _mask_mat := ShaderMaterial.new()
var _resolve_mat := ShaderMaterial.new()
var _receive_mat := ShaderMaterial.new()
var _mask_nodes := {}
var _moving_lights := {}
var _tier_lights := Node2D.new()
var _overlay: ColorRect


func _init(items: Dictionary, miners: Dictionary, divisor: int, bounce: float, shadow: float) -> void:
	_items = items
	_miners = miners
	_divisor = divisor
	_bounce = bounce
	_shadow = shadow


func _ready() -> void:
	name = "GI"
	# 暂停时保留前一帧的物件与姿势，仍可切档和重排窗口。
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_mask_vp = _viewport(DESIGN_SIZE)
	_mask_vp.name = "Occlusion"
	_mask_vp.add_child(_rect(Color.BLACK))
	_mask_mat.shader = SH_MASK

	var size := Vector2i(DESIGN_SIZE.x / _divisor, DESIGN_SIZE.y / _divisor)
	_light_vp = _viewport(size)
	_light_vp.name = "Emission"
	_light_vp.add_child(_rect(Color.BLACK))
	_emitters.scale = Vector2.ONE / float(_divisor)
	_emitters.add_child(_tier_lights)
	_light_vp.add_child(_emitters)

	_resolve_vp = _viewport(size)
	_resolve_vp.name = "Resolve"
	# 解算贴图的 RGB 装反光、A 装阴影，写入时保留独立的四个通道。
	_resolve_vp.transparent_bg = true
	_resolve_mat.shader = SH_RESOLVE
	_resolve_mat.set_shader_parameter("design_px", DESIGN_PX)
	_resolve_mat.set_shader_parameter("mask_tex", _mask_vp.get_texture())
	_resolve_mat.set_shader_parameter("light_tex", _light_vp.get_texture())
	var resolve := _rect(Color.WHITE)
	resolve.material = _resolve_mat
	_resolve_vp.add_child(resolve)
	# 视口按从内到外的顺序绘制，遮挡先于发光，解算先于主井。
	_light_vp.add_child(_mask_vp)
	_resolve_vp.add_child(_light_vp)
	add_child(_resolve_vp)

	var overlay_mat := ShaderMaterial.new()
	overlay_mat.shader = SH_BACKGROUND
	overlay_mat.set_shader_parameter("resolved_tex", _resolve_vp.get_texture())
	overlay_mat.set_shader_parameter("bounce_strength", _bounce)
	overlay_mat.set_shader_parameter("shadow_strength", _shadow)
	_overlay = ColorRect.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.size = Vector2(DESIGN_SIZE)
	_overlay.z_index = -2
	_overlay.material = overlay_mat
	_overlay.hide()
	add_child(_overlay)

	_receive_mat.shader = SH_RECEIVE
	_receive_mat.set_shader_parameter("resolved_tex", _resolve_vp.get_texture())
	_receive_mat.set_shader_parameter("bounce_strength", _bounce)


func _viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	return vp


func _rect(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = color
	return rect


func set_tier(conf: Dictionary, lava: bool) -> void:
	_resolve_mat.set_shader_parameter("light_dir", conf.light_dir)
	for light in _tier_lights.get_children():
		_tier_lights.remove_child(light)
		light.queue_free()
	for pos in conf.lamps:
		var lamp := _new_light(_tier_lights, Color(conf.light_col, LAMP_STRENGTH), LAMP_RADIUS, 0.0)
		_move_light(lamp, pos)
	if lava:
		var magma := _new_light(_tier_lights, LAVA_COLOR, LAVA_RADIUS, 0.0, Cfg.GW * 0.5)
		_move_light(magma, Vector2(Cfg.GW * 0.5, Cfg.GH))


func set_dark(dark: float) -> void:
	_resolve_mat.set_shader_parameter("light_fade", 1.0 - dark)


func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	set_process(on)
	_overlay.visible = on
	for vp in [_mask_vp, _light_vp, _resolve_vp]:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		for item in _items.values():
			if item.sprite.material == _receive_mat:
				item.sprite.material = null


func _new_light(parent: Node2D, color: Color, radius: float, skip: float, half_width: float = 0.0) -> ColorRect:
	var light := ColorRect.new()
	light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	light.size = Vector2(2.0 * (radius + half_width), 2.0 * radius)
	var mat := ShaderMaterial.new()
	mat.shader = SH_LIGHT
	mat.set_shader_parameter("mask_tex", _mask_vp.get_texture())
	mat.set_shader_parameter("design_size", Vector2(DESIGN_SIZE))
	mat.set_shader_parameter("energy", Vector4(color.r, color.g, color.b, color.a))
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("source_skip", skip)
	mat.set_shader_parameter("line_half_width", half_width)
	light.material = mat
	parent.add_child(light)
	return light


func _move_light(light: ColorRect, center: Vector2) -> void:
	light.position = center - light.size * 0.5
	light.material.set_shader_parameter("center", center)


func _sync_light(source: Sprite2D, center: Vector2, color: Color, radius: float, skip: float, seen: Dictionary) -> void:
	var id := source.get_instance_id()
	seen[id] = true
	var light: ColorRect = _moving_lights.get(id)
	if light == null:
		light = _new_light(_emitters, color, radius, skip)
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
			# 发光点在贴图内，短射线跳过自己的发光核心。
			var skip := sprite.texture.get_width() * sprite.scale.x * 0.40
			_sync_light(sprite, pose.origin, emission[0], emission[1], skip, seen_lights)
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
			_sync_light(sprite, head, HEAD_COLOR, HEAD_RADIUS, 8.0, seen_lights)
	_remove_old(_mask_nodes, seen_masks)
	_remove_old(_moving_lights, seen_lights)
