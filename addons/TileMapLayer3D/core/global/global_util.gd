extends RefCounted
class_name GlobalUtil


static var _cached_shader: Shader = null
static var _cached_shader_double_sided: Shader = null
static var _cached_shader_box_repeat: Shader = null
static var _cached_preview_shader: Shader = null



static func create_unshaded_material(
	color: Color,
	cull_disabled: bool = false,
	render_priority: int = GlobalConstants.DEFAULT_RENDER_PRIORITY
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = render_priority
	if cull_disabled:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

# Sampler + has_normal_texture guard MUST be set together so the shader never desyncs.
static func set_normal_map_params(material: ShaderMaterial, normal_tex: Texture2D) -> void:
	if material == null:
		return
	material.set_shader_parameter("normal_texture", normal_tex)
	material.set_shader_parameter("has_normal_texture", normal_tex != null)


static func create_tile_material(texture: Texture2D, filter_mode: int = 0, render_priority: int = 0, debug_show_red_backfaces: bool = true, normal_tex: Texture2D = null) -> ShaderMaterial:
	if not _cached_shader:
		_cached_shader = load("uid://huf0b1u2f55e")

	if not _cached_shader_double_sided:
		_cached_shader_double_sided = load("uid://6otniuywb7v8")

	var material: ShaderMaterial = ShaderMaterial.new()

	if debug_show_red_backfaces:
		material.shader = _cached_shader
	else:
		material.shader = _cached_shader_double_sided
	material.render_priority = render_priority

	if texture:
		material.set_shader_parameter("albedo_texture", texture)
		material.set_shader_parameter("debug_show_backfaces", debug_show_red_backfaces)

		var use_nearest: bool = (filter_mode == 0 or filter_mode == 1)
		material.set_shader_parameter("use_nearest_texture", use_nearest)

	set_normal_map_params(material, normal_tex)

	return material


static func create_box_repeat_tile_material(texture: Texture2D, filter_mode: int = 0, render_priority: int = 0, normal_tex: Texture2D = null) -> ShaderMaterial:
	if not _cached_shader_box_repeat:
		_cached_shader_box_repeat = load("res://addons/TileMapLayer3D/shaders/tile_multimesh_box_repeat.gdshader")

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _cached_shader_box_repeat
	material.render_priority = render_priority

	if texture:
		material.set_shader_parameter("albedo_texture", texture)
		material.set_shader_parameter("side_normal_y_threshold", GlobalConstants.BOX_SIDE_NORMAL_Y_THRESHOLD)

		var use_nearest: bool = (filter_mode == 0 or filter_mode == 1)
		material.set_shader_parameter("use_nearest_texture", use_nearest)

	set_normal_map_params(material, normal_tex)

	return material


static func create_preview_material(texture: Texture2D, uv_region_min: Vector2, uv_region_max: Vector2, filter_mode: int = 0, render_priority: int = 99
) -> ShaderMaterial:
	if not _cached_preview_shader:
		_cached_preview_shader = load("uid://chk7vtf6p8lwg")

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _cached_preview_shader
	material.render_priority = render_priority

	if texture:
		material.set_shader_parameter("atlas_texture", texture)
		material.set_shader_parameter("uv_region_min", uv_region_min)
		material.set_shader_parameter("uv_region_max", uv_region_max)

		var use_nearest: bool = (filter_mode == 0 or filter_mode == 1)
		material.set_shader_parameter("use_nearest_texture", use_nearest)

	return material

static func update_preview_material_uv(material: ShaderMaterial,uv_region_min: Vector2,uv_region_max: Vector2
) -> void:
	if material:
		material.set_shader_parameter("uv_region_min", uv_region_min)
		material.set_shader_parameter("uv_region_max", uv_region_max)

static func safe_connect(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)

static func safe_disconnect(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)


enum TileOrientation {
	FLOOR = 0,
	CEILING = 1,
	WALL_NORTH = 2,
	WALL_SOUTH = 3,
	WALL_EAST = 4,
	WALL_WEST = 5,

	FLOOR_TILT_POS_X = 6,
	FLOOR_TILT_NEG_X = 7,
	CEILING_TILT_POS_X = 8,
	CEILING_TILT_NEG_X = 9,

	WALL_NORTH_TILT_POS_Y = 10,
	WALL_NORTH_TILT_NEG_Y = 11,
	WALL_NORTH_TILT_POS_X = 12,
	WALL_NORTH_TILT_NEG_X = 13,

	WALL_SOUTH_TILT_POS_Y = 14,
	WALL_SOUTH_TILT_NEG_Y = 15,
	WALL_SOUTH_TILT_POS_X = 16,
	WALL_SOUTH_TILT_NEG_X = 17,

	WALL_EAST_TILT_POS_X = 18,
	WALL_EAST_TILT_NEG_X = 19,
	WALL_EAST_TILT_POS_Y = 20,
	WALL_EAST_TILT_NEG_Y = 21,

	WALL_WEST_TILT_POS_X = 22,
	WALL_WEST_TILT_NEG_X = 23,
	WALL_WEST_TILT_POS_Y = 24,
	WALL_WEST_TILT_NEG_Y = 25,

}

const ORIENTATION_DATA: Dictionary = {
	TileOrientation.FLOOR: {
		"base": TileOrientation.FLOOR,
		"scale": Vector3.ONE,
		"depth_axis": "y",
		"tilt_offset_axis": "",
	},
	TileOrientation.FLOOR_TILT_POS_X: {
		"base": TileOrientation.FLOOR,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "y",
		"tilt_offset_axis": "y",
	},
	TileOrientation.FLOOR_TILT_NEG_X: {
		"base": TileOrientation.FLOOR,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "y",
		"tilt_offset_axis": "y",
	},

	TileOrientation.CEILING: {
		"base": TileOrientation.CEILING,
		"scale": Vector3.ONE,
		"depth_axis": "y",
		"tilt_offset_axis": "",
	},
	TileOrientation.CEILING_TILT_POS_X: {
		"base": TileOrientation.CEILING,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "y",
		"tilt_offset_axis": "y",
	},
	TileOrientation.CEILING_TILT_NEG_X: {
		"base": TileOrientation.CEILING,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "y",
		"tilt_offset_axis": "y",
	},

	TileOrientation.WALL_NORTH: {
		"base": TileOrientation.WALL_NORTH,
		"scale": Vector3.ONE,
		"depth_axis": "z",
		"tilt_offset_axis": "",
	},
	TileOrientation.WALL_NORTH_TILT_POS_Y: {
		"base": TileOrientation.WALL_NORTH,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},
	TileOrientation.WALL_NORTH_TILT_NEG_Y: {
		"base": TileOrientation.WALL_NORTH,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},

	TileOrientation.WALL_NORTH_TILT_POS_X: {
		"base": TileOrientation.WALL_NORTH,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},
	TileOrientation.WALL_NORTH_TILT_NEG_X: {
		"base": TileOrientation.WALL_NORTH,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},

	TileOrientation.WALL_SOUTH: {
		"base": TileOrientation.WALL_SOUTH,
		"scale": Vector3.ONE,
		"depth_axis": "z",
		"tilt_offset_axis": "",
	},
	TileOrientation.WALL_SOUTH_TILT_POS_Y: {
		"base": TileOrientation.WALL_SOUTH,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},
	TileOrientation.WALL_SOUTH_TILT_NEG_Y: {
		"base": TileOrientation.WALL_SOUTH,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},
	TileOrientation.WALL_SOUTH_TILT_POS_X: { 
		"base": TileOrientation.WALL_SOUTH,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},
	TileOrientation.WALL_SOUTH_TILT_NEG_X: { 
		"base": TileOrientation.WALL_SOUTH,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},

	TileOrientation.WALL_EAST: {
		"base": TileOrientation.WALL_EAST,
		"scale": Vector3.ONE,
		"depth_axis": "x",
		"tilt_offset_axis": "",
	},
	TileOrientation.WALL_EAST_TILT_POS_X: {
		"base": TileOrientation.WALL_EAST,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},
	TileOrientation.WALL_EAST_TILT_NEG_X: {
		"base": TileOrientation.WALL_EAST,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},
	TileOrientation.WALL_EAST_TILT_POS_Y: {  
		"base": TileOrientation.WALL_EAST,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},
	TileOrientation.WALL_EAST_TILT_NEG_Y: {  
		"base": TileOrientation.WALL_EAST,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},


	TileOrientation.WALL_WEST: {
		"base": TileOrientation.WALL_WEST,
		"scale": Vector3.ONE,
		"depth_axis": "x",
		"tilt_offset_axis": "",
	},
	TileOrientation.WALL_WEST_TILT_POS_X: {
		"base": TileOrientation.WALL_WEST,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},
	TileOrientation.WALL_WEST_TILT_NEG_X: {
		"base": TileOrientation.WALL_WEST,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},
	TileOrientation.WALL_WEST_TILT_POS_Y: { 
		"base": TileOrientation.WALL_WEST,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},
	TileOrientation.WALL_WEST_TILT_NEG_Y: {  
		"base": TileOrientation.WALL_WEST,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},
}

const TILT_SEQUENCES: Dictionary = {
	TileOrientation.FLOOR: [
		TileOrientation.FLOOR,
		TileOrientation.FLOOR_TILT_POS_X,
		TileOrientation.FLOOR_TILT_NEG_X
	],
	TileOrientation.CEILING: [
		TileOrientation.CEILING,
		TileOrientation.CEILING_TILT_POS_X,
		TileOrientation.CEILING_TILT_NEG_X
	],
	TileOrientation.WALL_NORTH: [
		TileOrientation.WALL_NORTH,
		TileOrientation.WALL_NORTH_TILT_POS_Y,
		TileOrientation.WALL_NORTH_TILT_NEG_Y,
		TileOrientation.WALL_NORTH_TILT_NEG_X, 
		TileOrientation.WALL_NORTH_TILT_POS_X, 

	],
	TileOrientation.WALL_SOUTH: [
		TileOrientation.WALL_SOUTH,
		TileOrientation.WALL_SOUTH_TILT_POS_Y,
		TileOrientation.WALL_SOUTH_TILT_NEG_Y,
		TileOrientation.WALL_SOUTH_TILT_POS_X, 
		TileOrientation.WALL_SOUTH_TILT_NEG_X 
	],
	TileOrientation.WALL_EAST: [
		TileOrientation.WALL_EAST,
		TileOrientation.WALL_EAST_TILT_POS_X,
		TileOrientation.WALL_EAST_TILT_NEG_X,
		TileOrientation.WALL_EAST_TILT_POS_Y, 
		TileOrientation.WALL_EAST_TILT_NEG_Y 
	],
	TileOrientation.WALL_WEST: [
		TileOrientation.WALL_WEST,
		TileOrientation.WALL_WEST_TILT_POS_X,
		TileOrientation.WALL_WEST_TILT_NEG_X,
		TileOrientation.WALL_WEST_TILT_POS_Y,
		TileOrientation.WALL_WEST_TILT_NEG_Y
	],
}


static func _is_external_resource_file(res: Resource) -> bool:
	if res == null:
		return false
	var path: String = res.resource_path
	if path.is_empty():
		return false
	if path.contains("::"):
		return false
	return true


static func _save_external_resource(TileMapLayer3D: Node, res: Resource, label: String) -> void:
	if not GlobalUtil._is_external_resource_file(res):
		return
	var err: int = ResourceSaver.save(res, res.resource_path)
	if err != OK:
		push_warning(
			"TileMapLayer3D '%s': failed to save res external %s to '%s' (error %d)"
			% [TileMapLayer3D.name, label, res.resource_path, err]
		)





static func get_orientation_depth_axis(orientation: int) -> String:
	var data: Dictionary = ORIENTATION_DATA.get(orientation, {})
	return data.get("depth_axis", "")

## Checks if two base orientations (0-5) conflict (same depth_axis = overlap).
## Tilted tiles (6+) never conflict.
static func orientations_conflict(orientation_a: int, orientation_b: int) -> bool:
	if orientation_a == orientation_b:
		return false
	# Only base orientations (0-5) can conflict - tilted tiles (6+) never conflict
	if orientation_a > 5 or orientation_b > 5:
		return false
	var axis_a: String = get_orientation_depth_axis(orientation_a)
	var axis_b: String = get_orientation_depth_axis(orientation_b)
	return axis_a != "" and axis_a == axis_b

static func get_opposite_orientation(orientation: int) -> int:
	match orientation:
		TileOrientation.FLOOR:        return TileOrientation.CEILING
		TileOrientation.CEILING:      return TileOrientation.FLOOR
		TileOrientation.WALL_NORTH:   return TileOrientation.WALL_SOUTH
		TileOrientation.WALL_SOUTH:   return TileOrientation.WALL_NORTH
		TileOrientation.WALL_EAST:    return TileOrientation.WALL_WEST
		TileOrientation.WALL_WEST:    return TileOrientation.WALL_EAST
		_: return -1

## Tiny offset along surface normal to prevent Z-fighting.
## Handles flat tiles unconditionally; handles BOX/PRISM when box_prism_enabled=true.
static func calculate_flat_tile_offset(orientation: int, mesh_mode: int,box_prism_enabled: bool = false, is_decal: bool = false) -> Vector3:
	if mesh_mode == GlobalConstants.MeshMode.BOX_MESH or \
	   mesh_mode == GlobalConstants.MeshMode.PRISM_MESH:
		if box_prism_enabled and orientation >= 0 and orientation < GlobalConstants.BOX_PRISM_ORIENTATION_OFFSETS_ALTERNATIVE.size():
			return GlobalConstants.BOX_PRISM_ORIENTATION_OFFSETS_ALTERNATIVE[orientation] * GlobalConstants.BOX_PRISM_Z_OFFSET_SCALE
		return Vector3.ZERO

	if mesh_mode != GlobalConstants.MeshMode.FLAT_SQUARE and \
	   mesh_mode != GlobalConstants.MeshMode.FLAT_TRIANGULE and \
	   mesh_mode != GlobalConstants.MeshMode.FLAT_ARCH_CORNER and \
	   mesh_mode != GlobalConstants.MeshMode.FLAT_ARCH and \
	   mesh_mode != GlobalConstants.MeshMode.FLAT_ARCH_I and \
	   mesh_mode != GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I and \
	   mesh_mode != GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP and \
	   mesh_mode != GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I and \
	   mesh_mode != GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO and \
	   mesh_mode != GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C and \
	   mesh_mode != GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I and \
	   mesh_mode != GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S and \
	   mesh_mode != GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
		return Vector3.ZERO

	if GlobalConstants.FLAT_TILE_ORIENTATION_OFFSET <= 0.0:
		return Vector3.ZERO

	if is_decal:
		# Decals may require a larger offset to prevent z-fighting due to their own depth bias and rendering quirks.


		return get_rotation_axis_for_orientation(orientation) * GlobalConstants.DECAL_NODE_OFFSET
		
	return get_rotation_axis_for_orientation(orientation) * GlobalConstants.FLAT_TILE_ORIENTATION_OFFSET



static func get_tile_rotation_basis(orientation: int, tilt_angle: float = 0.0) -> Basis:
	var actual_tilt: float = tilt_angle if tilt_angle != 0.0 else GlobalConstants.TILT_ANGLE_RAD

	match orientation:
		TileOrientation.FLOOR:
			return Basis.IDENTITY

		TileOrientation.CEILING:
			return Basis(Vector3(1, 0, 0), deg_to_rad(180))

		TileOrientation.WALL_NORTH:
			return Basis(Vector3(1, 0, 0), deg_to_rad(90))

		TileOrientation.WALL_SOUTH:
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-180))
			return Basis(Vector3(1, 0, 0), deg_to_rad(-90)) * rotation_correction

		TileOrientation.WALL_EAST:
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-90))
			return Basis(Vector3(0, 0, 1), PI / 2.0) * rotation_correction

		TileOrientation.WALL_WEST:
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(90))
			return Basis(Vector3(0, 0, 1), -PI / 2.0) * rotation_correction

		TileOrientation.FLOOR_TILT_POS_X:
			return Basis(Vector3.RIGHT, actual_tilt)

		TileOrientation.FLOOR_TILT_NEG_X:
			return Basis(Vector3.RIGHT, -actual_tilt)

		TileOrientation.CEILING_TILT_POS_X:
			var ceiling_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(180))
			var tilt: Basis = Basis(Vector3.RIGHT, actual_tilt)
			return ceiling_base * tilt

		TileOrientation.CEILING_TILT_NEG_X:
			var ceiling_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(180))
			var tilt: Basis = Basis(Vector3.RIGHT, -actual_tilt)
			return ceiling_base * tilt

		TileOrientation.WALL_NORTH_TILT_POS_Y:
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(90))
			var tilt: Basis = Basis(Vector3.UP, actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_NORTH_TILT_NEG_Y:
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(90))
			var tilt: Basis = Basis(Vector3.UP, -actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_NORTH_TILT_POS_X: 
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(90))
			var tilt: Basis = Basis(Vector3.RIGHT, actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_NORTH_TILT_NEG_X:
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(90))
			var tilt: Basis = Basis(Vector3.RIGHT, -actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_SOUTH_TILT_POS_Y:
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-180))
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(-90)) * rotation_correction
			var tilt: Basis = Basis(Vector3.UP, actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_SOUTH_TILT_NEG_Y:
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-180))
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(-90)) * rotation_correction
			var tilt: Basis = Basis(Vector3.UP, -actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_SOUTH_TILT_POS_X: 
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-180))
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(-90)) * rotation_correction
			var tilt: Basis = Basis(Vector3.RIGHT, actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_SOUTH_TILT_NEG_X:
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-180))
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(-90)) * rotation_correction
			var tilt: Basis = Basis(Vector3.RIGHT, -actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_EAST_TILT_POS_X:
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.RIGHT, actual_tilt)
			return wall_base * tilt

		TileOrientation.WALL_EAST_TILT_NEG_X:
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.RIGHT, -actual_tilt)
			return wall_base * tilt

		TileOrientation.WALL_EAST_TILT_POS_Y: 
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.FORWARD, actual_tilt)
			return wall_base * tilt

		TileOrientation.WALL_EAST_TILT_NEG_Y: 
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.FORWARD, -actual_tilt)
			return wall_base * tilt

		TileOrientation.WALL_WEST_TILT_POS_X:
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), -PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.RIGHT, actual_tilt)
			return wall_base * tilt

		TileOrientation.WALL_WEST_TILT_NEG_X:
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), -PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.RIGHT, -actual_tilt)
			return wall_base * tilt

		TileOrientation.WALL_WEST_TILT_POS_Y: 
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), -PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.FORWARD, actual_tilt)
			return wall_base * tilt

		TileOrientation.WALL_WEST_TILT_NEG_Y: 
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), -PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.FORWARD, -actual_tilt)
			return wall_base * tilt

		_:
			push_warning("Invalid orientation basis for rotation: ", orientation)
			return Basis.IDENTITY


static func get_base_tile_orientation(orientation: int) -> TileOrientation:
	if ORIENTATION_DATA.has(orientation):
		return ORIENTATION_DATA[orientation]["base"]
	return orientation


static func get_tilt_sequence(orientation: int) -> Array:
	var base: int = get_base_tile_orientation(orientation)
	return TILT_SEQUENCES.get(base, [])




static func _get_snapped_cardinal_vector(direction_vector: Vector3) -> Vector3:
	var abs_x: float = abs(direction_vector.x)
	var abs_y: float = abs(direction_vector.y)
	var abs_z: float = abs(direction_vector.z)

	if abs_x > abs_y and abs_x > abs_z:
		return Vector3(sign(direction_vector.x), 0, 0)
	elif abs_y > abs_z:
		return Vector3(0, sign(direction_vector.y), 0)
	else:
		return Vector3(0, 0, sign(direction_vector.z))

static func get_scale_for_orientation(
	orientation: int,
	scale_factor: float = 0.0,
	mesh_mode: int = 0,
	depth_scale: float = 1.0
) -> Vector3:
	if not ORIENTATION_DATA.has(orientation):
		return Vector3.ONE

	var base_scale: Vector3 = ORIENTATION_DATA[orientation]["scale"]
	var depth_axis: String = ORIENTATION_DATA[orientation]["depth_axis"]

	var result: Vector3 = base_scale

	if scale_factor != 0.0 and base_scale != Vector3.ONE:
		result = Vector3.ONE
		if base_scale.x != 1.0:
			result.x = scale_factor
		if base_scale.y != 1.0:
			result.y = scale_factor
		if base_scale.z != 1.0:
			result.z = scale_factor

	var is_box_or_prism: bool = (
		mesh_mode == GlobalConstants.MeshMode.BOX_MESH or
		mesh_mode == GlobalConstants.MeshMode.PRISM_MESH
	)
	if depth_scale != 1.0 and is_box_or_prism:
		result.y *= depth_scale

	return result


static func get_tilt_offset_for_orientation(orientation: int, grid_size: float, offset_factor: float = 0.0) -> Vector3:
	if not ORIENTATION_DATA.has(orientation):
		return Vector3.ZERO

	var offset_axis: String = ORIENTATION_DATA[orientation]["tilt_offset_axis"]
	if offset_axis.is_empty():
		return Vector3.ZERO

	var actual_factor: float = offset_factor if offset_factor != 0.0 else GlobalConstants.TILT_POSITION_OFFSET_FACTOR
	var offset_value: float = grid_size * actual_factor

	match offset_axis:
		"x": return Vector3(offset_value, 0, 0)
		"y": return Vector3(0, offset_value, 0)
		"z": return Vector3(0, 0, offset_value)
		_: return Vector3.ZERO


static func get_orientation_tolerance(orientation: int, tolerance: float) -> Vector3:
	var depth_tolerance: float = GlobalConstants.AREA_ERASE_DEPTH_TOLERANCE

	if not ORIENTATION_DATA.has(orientation):
		push_warning("GlobalUtil.get_orientation_tolerance(): Unknown orientation %d, using FLOOR tolerance" % orientation)
		return Vector3(tolerance, depth_tolerance, tolerance)

	var depth_axis: String = ORIENTATION_DATA[orientation]["depth_axis"]

	match depth_axis:
		"x": return Vector3(depth_tolerance, tolerance, tolerance)
		"y": return Vector3(tolerance, depth_tolerance, tolerance)
		"z": return Vector3(tolerance, tolerance, depth_tolerance)
		_: return Vector3(tolerance, depth_tolerance, tolerance)




## SINGLE SOURCE OF TRUTH for tile transform construction.
## Transform order (DO NOT CHANGE): Scale -> Orient -> Rotate.
## Pass 0.0 for spin/tilt/scale/offset to use GlobalConstants defaults.
static func build_tile_transform(
	grid_pos: Vector3,
	orientation: int,
	mesh_rotation: int,
	grid_size: float,
	is_face_flipped: bool = false,
	spin_angle: float = 0.0,
	tilt_angle: float = 0.0,
	scale_factor: float = 0.0,
	offset_factor: float = 0.0,
	mesh_mode: int = 0,
	depth_scale: float = 1.0,
	invert_depth: bool = false,
) -> Transform3D:
	var transform: Transform3D = Transform3D()

	var scale_vector: Vector3 = get_scale_for_orientation(orientation, scale_factor, mesh_mode, depth_scale)

	var is_triangle_shape: bool = (
		mesh_mode == GlobalConstants.MeshMode.FLAT_TRIANGULE or
		mesh_mode == GlobalConstants.MeshMode.PRISM_MESH
	)
	if is_triangle_shape and mesh_rotation % 2 == 1:
		scale_vector = Vector3(scale_vector.z, scale_vector.y, scale_vector.x)

	var scale_basis: Basis = Basis.from_scale(scale_vector)

	var orientation_basis: Basis = get_tile_rotation_basis(orientation, tilt_angle)

	var combined_basis: Basis = orientation_basis * scale_basis

	if is_face_flipped:
		var flip_basis: Basis = Basis.from_scale(Vector3(1, 1, -1))
		combined_basis = combined_basis * flip_basis

	if mesh_rotation > 0:
		combined_basis = apply_mesh_rotation(combined_basis, orientation, mesh_rotation, spin_angle)

	var world_pos: Vector3 = grid_to_world(grid_pos, grid_size)

	if invert_depth and (mesh_mode == GlobalConstants.MeshMode.BOX_MESH or mesh_mode == GlobalConstants.MeshMode.PRISM_MESH):
		var extrusion_dir: Vector3 = orientation_basis * Vector3.UP
		world_pos -= extrusion_dir * depth_scale * grid_size

	if orientation >= TileOrientation.FLOOR_TILT_POS_X:
		var tilt_offset: Vector3 = get_tilt_offset_for_orientation(orientation, grid_size, offset_factor)
		world_pos += tilt_offset

	transform.basis = combined_basis
	transform.origin = world_pos

	return transform


static func get_rotation_axis_for_orientation(orientation: int) -> Vector3:
	match orientation:
		TileOrientation.FLOOR:
			return Vector3.UP

		TileOrientation.CEILING:
			return Vector3.DOWN

		TileOrientation.WALL_NORTH:
			return Vector3.BACK

		TileOrientation.WALL_SOUTH:
			return Vector3.FORWARD

		TileOrientation.WALL_EAST:
			return Vector3.LEFT

		TileOrientation.WALL_WEST:
			return Vector3.RIGHT

		TileOrientation.FLOOR_TILT_POS_X, TileOrientation.FLOOR_TILT_NEG_X:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.CEILING_TILT_POS_X, TileOrientation.CEILING_TILT_NEG_X:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.WALL_NORTH_TILT_POS_Y, TileOrientation.WALL_NORTH_TILT_NEG_Y:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.WALL_NORTH_TILT_POS_X, TileOrientation.WALL_NORTH_TILT_NEG_X:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.WALL_SOUTH_TILT_POS_Y, TileOrientation.WALL_SOUTH_TILT_NEG_Y:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.WALL_SOUTH_TILT_POS_X, TileOrientation.WALL_SOUTH_TILT_NEG_X:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.WALL_EAST_TILT_POS_X, TileOrientation.WALL_EAST_TILT_NEG_X:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.WALL_EAST_TILT_POS_Y, TileOrientation.WALL_EAST_TILT_NEG_Y:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.WALL_WEST_TILT_POS_X, TileOrientation.WALL_WEST_TILT_NEG_X:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.WALL_WEST_TILT_POS_Y, TileOrientation.WALL_WEST_TILT_NEG_Y:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		_:
			push_warning("Invalid axis orientation for rotation: ", orientation)
			return Vector3.UP

static func apply_mesh_rotation(base_basis: Basis, orientation: int, rotation_steps: int, spin_angle: float = 0.0) -> Basis:
	if rotation_steps == 0:
		return base_basis

	var rotation_axis: Vector3 = get_rotation_axis_for_orientation(orientation)

	var actual_angle: float = spin_angle if spin_angle != 0.0 else GlobalConstants.SPIN_ANGLE_RAD

	var angle: float = float(rotation_steps) * actual_angle

	var rotation_basis: Basis = Basis(rotation_axis, angle)

	return rotation_basis * base_basis


static func grid_to_world(grid_pos: Vector3, grid_size: float) -> Vector3:
	return (grid_pos + GlobalConstants.GRID_ALIGNMENT_OFFSET) * grid_size

static func world_to_grid(world_pos: Vector3, grid_size: float) -> Vector3:
	return (world_pos / grid_size) - GlobalConstants.GRID_ALIGNMENT_OFFSET




static func make_tile_key(grid_pos: Vector3, orientation: int) -> int:
	return TileKeySystem.make_tile_key_int(grid_pos, orientation)

static func parse_tile_key(tile_key: String) -> Dictionary:
	var parts: PackedStringArray = tile_key.split(",")
	if parts.size() != 4:
		push_warning("Invalid tile key format: ", tile_key)
		return {}

	var grid_pos := Vector3(
		parts[0].to_float(),
		parts[1].to_float(),
		parts[2].to_float()
	)
	var orientation: int = parts[3].to_int()

	return {
		"grid_pos": grid_pos,
		"orientation": orientation
	}

static func migrate_placement_data(old_dict: Dictionary) -> Dictionary:
	var new_dict: Dictionary = {}

	for old_key in old_dict.keys():
		if old_key is String:
			var new_key: int = TileKeySystem.migrate_string_key(old_key)
			if new_key != -1:
				new_dict[new_key] = old_dict[old_key]
			else:
				push_warning("GlobalUtil: Failed to migrate tile key: ", old_key)
		else:
			new_dict[old_key] = old_dict[old_key]

	return new_dict


static func calculate_normalized_uv(uv_rect: Rect2, atlas_size: Vector2) -> Dictionary:
	var uv_min: Vector2 = uv_rect.position / atlas_size
	var uv_max: Vector2 = (uv_rect.position + uv_rect.size) / atlas_size


	var uv_color: Color = Color(uv_min.x, uv_min.y, uv_max.x, uv_max.y)

	return {
		"uv_min": uv_min,
		"uv_max": uv_max,
		"uv_color": uv_color
	}


static func encode_uv_freeze_rotation(uv_max_y: float, mesh_rotation: int, freeze_uv: bool) -> float:
	if not freeze_uv:
		return uv_max_y
	return uv_max_y + float(mesh_rotation + 1) * 2.0


static func transform_uv_for_baking(uv: Vector2, mesh_rotation: int, is_flipped: bool) -> Vector2:
	var result: Vector2 = uv

	result.y = 1.0 - result.y

	if is_flipped:
		result.x = 1.0 - result.x

	match mesh_rotation:
		1:
			result = Vector2(result.y, 1.0 - result.x)
		2:
			result = Vector2(1.0 - result.x, 1.0 - result.y)
		3:
			result = Vector2(1.0 - result.y, result.x)

	return result



## Appends triangle tile geometry to mesh arrays.
## uv_rect must be in NORMALIZED [0-1] coordinates (NOT pixel coordinates).
static func add_triangle_geometry(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	transform: Transform3D,
	uv_rect: Rect2,
	grid_size: float
) -> void:

	var half_width: float = grid_size * 0.5
	var half_height: float = grid_size * 0.5

	# Define local vertices (right triangle, counter-clockwise)
	# These are in local tile space (centered at origin)
	# MUST MATCH tile_mesh_generator.gd geometry!
	var local_verts: Array[Vector3] = [
		Vector3(-half_width, 0.0, -half_height),
		Vector3(half_width, 0.0, -half_height),
		Vector3(-half_width, 0.0, half_height)
	]

	#   UV coordinates for triangle in NORMALIZED [0-1] space
	# uv_rect should be pre-normalized before calling this function
	# Map triangle vertices to UV space - MUST MATCH generator UVs!
	var tile_uvs: Array[Vector2] = [
		uv_rect.position,
		Vector2(uv_rect.end.x, uv_rect.position.y),
		Vector2(uv_rect.position.x, uv_rect.end.y)
	]

	var normal: Vector3 = transform.basis.y.normalized()
	var v_offset: int = vertices.size()

	for i: int in range(3):
		vertices.append(transform * local_verts[i])
		uvs.append(tile_uvs[i])
		normals.append(normal)

	indices.append(v_offset + 0)
	indices.append(v_offset + 1)
	indices.append(v_offset + 2)


static func create_baked_mesh_material(
	texture: Texture2D,
	filter_mode: int = 0,
	render_priority: int = 0,
	enable_alpha: bool = true,
	enable_toon_shading: bool = true,
	normal_tex: Texture2D = null
) -> StandardMaterial3D:

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = texture
	material.cull_mode = BaseMaterial3D.CULL_BACK

	if normal_tex != null:
		material.normal_enabled = true
		material.normal_texture = normal_tex

	match filter_mode:
		0:
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		1:
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		2:
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		3:
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	if enable_alpha:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5

	if enable_toon_shading:
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		material.specular_mode = BaseMaterial3D.SPECULAR_TOON

	material.render_priority = render_priority

	return material


static func create_array_mesh_from_arrays(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	tangents: PackedFloat32Array = PackedFloat32Array(),
	mesh_name: String = ""
) -> ArrayMesh:

	var final_tangents: PackedFloat32Array = tangents
	if final_tangents.is_empty():
		final_tangents = generate_tangents_for_mesh(vertices, uvs, normals, indices)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = final_tangents
	arrays[Mesh.ARRAY_INDEX] = indices

	var array_mesh: ArrayMesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	if not mesh_name.is_empty():
		array_mesh.resource_name = mesh_name

	return array_mesh

static func generate_tangents_for_mesh(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array
) -> PackedFloat32Array:

	var tangents: PackedFloat32Array = PackedFloat32Array()
	tangents.resize(vertices.size() * 4)

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i: int in range(vertices.size()):
		st.set_uv(uvs[i])
		st.set_normal(normals[i])
		st.add_vertex(vertices[i])

	for idx: int in indices:
		st.add_index(idx)

	st.generate_tangents()

	var temp_arrays: Array = st.commit_to_arrays()
	if temp_arrays[Mesh.ARRAY_TANGENT]:
		tangents = temp_arrays[Mesh.ARRAY_TANGENT]

	return tangents


static func get_grid_positions_in_area_with_snap(
	min_pos: Vector3,
	max_pos: Vector3,
	orientation: int,
	snap_size: float = 1.0
) -> Array[Vector3]:
	var positions: Array[Vector3] = []

	var actual_min: Vector3 = Vector3(
		min(min_pos.x, max_pos.x),
		min(min_pos.y, max_pos.y),
		min(min_pos.z, max_pos.z)
	)
	var actual_max: Vector3 = Vector3(
		max(min_pos.x, max_pos.x),
		max(min_pos.y, max_pos.y),
		max(min_pos.z, max_pos.z)
	)

	var min_snapped: Vector3 = Vector3(
		snappedf(actual_min.x, snap_size),
		snappedf(actual_min.y, snap_size),
		snappedf(actual_min.z, snap_size)
	)
	var max_snapped: Vector3 = Vector3(
		snappedf(actual_max.x, snap_size),
		snappedf(actual_max.y, snap_size),
		snappedf(actual_max.z, snap_size)
	)

	# Calculate number of steps (inclusive range)
	# Use round() to handle floating point precision issues
	var calc_steps = func(min_val: float, max_val: float) -> int:
		return int(round((max_val - min_val) / snap_size)) + 1

	match orientation:
		TileOrientation.FLOOR, TileOrientation.CEILING:
			var x_steps: int = calc_steps.call(min_snapped.x, max_snapped.x)
			var z_steps: int = calc_steps.call(min_snapped.z, max_snapped.z)
			for i in range(x_steps):
				var x: float = min_snapped.x + (i * snap_size)
				for j in range(z_steps):
					var z: float = min_snapped.z + (j * snap_size)
					positions.append(Vector3(x, actual_min.y, z))

		TileOrientation.WALL_NORTH, TileOrientation.WALL_SOUTH:
			var x_steps: int = calc_steps.call(min_snapped.x, max_snapped.x)
			var y_steps: int = calc_steps.call(min_snapped.y, max_snapped.y)
			for i in range(x_steps):
				var x: float = min_snapped.x + (i * snap_size)
				for j in range(y_steps):
					var y: float = min_snapped.y + (j * snap_size)
					positions.append(Vector3(x, y, actual_min.z))

		TileOrientation.WALL_EAST, TileOrientation.WALL_WEST:
			var z_steps: int = calc_steps.call(min_snapped.z, max_snapped.z)
			var y_steps: int = calc_steps.call(min_snapped.y, max_snapped.y)
			for i in range(z_steps):
				var z: float = min_snapped.z + (i * snap_size)
				for j in range(y_steps):
					var y: float = min_snapped.y + (j * snap_size)
					positions.append(Vector3(actual_min.x, y, z))

		_:
			var x_steps: int = calc_steps.call(min_snapped.x, max_snapped.x)
			var z_steps: int = calc_steps.call(min_snapped.z, max_snapped.z)
			for i in range(x_steps):
				var x: float = min_snapped.x + (i * snap_size)
				for j in range(z_steps):
					var z: float = min_snapped.z + (j * snap_size)
					positions.append(Vector3(x, actual_min.y, z))

	return positions

static func create_area_selection_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()

	material.albedo_color = GlobalConstants.AREA_FILL_BOX_COLOR

	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	material.render_priority = GlobalConstants.AREA_FILL_RENDER_PRIORITY

	material.no_depth_test = true

	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	return material


static func create_grid_line_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()

	material.albedo_color = color

	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	material.vertex_color_use_as_albedo = true

	material.render_priority = GlobalConstants.GRID_OVERLAY_RENDER_PRIORITY

	return material



static func get_editor_scale() -> float:
	if Engine.is_editor_hint():
		var ei: Object = Engine.get_singleton("EditorInterface")
		if ei:
			return ei.get_editor_scale()
	return 1.0


static func scale_ui_size(base_size: Vector2i) -> Vector2i:
	var scale: float = get_editor_scale()
	return Vector2i(int(base_size.x * scale), int(base_size.y * scale))


static func scale_ui_value(base_value: int) -> int:
	return int(base_value * get_editor_scale())

static func get_editor_ui_scale() -> float:
	var ei: Object = Engine.get_singleton("EditorInterface")
	if ei:
		return ei.get_editor_scale()
	return 1.0

static func get_current_theme() -> Theme:
	var ei: Object = Engine.get_singleton("EditorInterface")
	if ei:
		return ei.get_editor_theme()
	return null

static func apply_button_theme(button: Button, icon_name: String, size:float) -> void:
	if Engine.is_editor_hint():
		var ui_scale: float = get_editor_ui_scale()
		var editor_theme: Theme = null
		var ei: Object = Engine.get_singleton("EditorInterface")
		
		if ei:
			editor_theme = ei.get_editor_theme()


		var icon_size = size * ui_scale
		button.custom_minimum_size = Vector2(icon_size, icon_size)

		button.add_theme_font_size_override("font_size", int(10 * ui_scale))

		if editor_theme and editor_theme.has_icon(icon_name, "EditorIcons"):
			button.icon = editor_theme.get_icon(icon_name, "EditorIcons")
		else:
			button.text = icon_name




static func compute_anim_frame_info(anim_data: TileAnimData, atlas_size: Vector2 = Vector2.ZERO) -> Dictionary:
	var result: Dictionary = {}
	if anim_data.selection_uv_rects.is_empty() or anim_data.columns <= 0 or anim_data.rows <= 0:
		return result
	if anim_data.base_tile_size.x <= 0.0 or anim_data.base_tile_size.y <= 0.0:
		return result

	var first: Rect2 = anim_data.selection_uv_rects[0]
	var min_pos: Vector2 = first.position
	var max_end: Vector2 = first.position + first.size
	for rect: Rect2 in anim_data.selection_uv_rects:
		min_pos.x = minf(min_pos.x, rect.position.x)
		min_pos.y = minf(min_pos.y, rect.position.y)
		max_end.x = maxf(max_end.x, rect.position.x + rect.size.x)
		max_end.y = maxf(max_end.y, rect.position.y + rect.size.y)

	var strip_size: Vector2 = max_end - min_pos
	var frame_pixel_w: float = strip_size.x / anim_data.columns
	var frame_pixel_h: float = strip_size.y / anim_data.rows
	var frame_tiles_x: int = int(roundf(frame_pixel_w / anim_data.base_tile_size.x))
	var frame_tiles_y: int = int(roundf(frame_pixel_h / anim_data.base_tile_size.y))

	result["strip_size"] = strip_size
	result["frame_pixel_w"] = frame_pixel_w
	result["frame_pixel_h"] = frame_pixel_h
	result["frame_tiles_x"] = frame_tiles_x
	result["frame_tiles_y"] = frame_tiles_y
	result["tiles_per_frame"] = frame_tiles_x * frame_tiles_y

	if atlas_size.x > 0.0 and atlas_size.y > 0.0:
		result["anim_step_x"] = frame_pixel_w / atlas_size.x
		result["anim_step_y"] = frame_pixel_h / atlas_size.y

	return result


static func get_anim_frame0_tiles(anim_data: TileAnimData) -> Array[Rect2]:
	var info: Dictionary = compute_anim_frame_info(anim_data)
	if info.is_empty():
		return []
	var frame_tiles_x: int = info["frame_tiles_x"]
	var frame_tiles_y: int = info["frame_tiles_y"]
	var strip_tiles_x: int = frame_tiles_x * anim_data.columns
	var result: Array[Rect2] = []
	for row: int in range(frame_tiles_y):
		for col: int in range(frame_tiles_x):
			var idx: int = row * strip_tiles_x + col
			if idx < anim_data.selection_uv_rects.size():
				result.append(anim_data.selection_uv_rects[idx])
	return result

static func get_first_frame_texture(tileset_texture: Texture2D, anim_data: TileAnimData) -> Texture:
	if not tileset_texture:
		return null

	var scale : float = get_editor_ui_scale()
	var icon_size: int = GlobalConstants.BUTTOM_CONTEXT_UI_SIZE * scale

	var frame0_tiles: Array[Rect2] = get_anim_frame0_tiles(anim_data)

	var min_pos: Vector2 = frame0_tiles[0].position
	var max_end: Vector2 = frame0_tiles[0].position + frame0_tiles[0].size
	for rect: Rect2 in frame0_tiles:
		min_pos.x = minf(min_pos.x, rect.position.x)
		min_pos.y = minf(min_pos.y, rect.position.y)
		max_end.x = maxf(max_end.x, rect.position.x + rect.size.x)
		max_end.y = maxf(max_end.y, rect.position.y + rect.size.y)
	
	var tile_region: Rect2 = Rect2(min_pos, max_end - min_pos)
	var _src_image: Image = tileset_texture.get_image()
	if _src_image.is_compressed():
		_src_image.decompress()
	var image: Image = _src_image.get_region(tile_region)

	image.resize(icon_size, icon_size)
	var region_texture = ImageTexture.new().create_from_image(image)
	return region_texture
